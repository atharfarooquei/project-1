-- =====================================================================
-- NABD :: 0011 :: Coins, earn rules, verified reviews
-- ---------------------------------------------------------------------
-- COINS ARE NOT CREDITS. Two ledgers, deliberately never merged:
--
--   credits (0004)  paid entitlement. Cash or subscription came in for
--                   these. VAT was charged. They can be refundable.
--   coins   (here)  marketing giveaway. No cash came in. They are a
--                   promotional liability, expensed on redemption.
--
-- Merging them would break three things at once: revenue recognition
-- (you could no longer tell earned-free from paid-for), refunds (cash
-- must never be returned for a coin-funded credit), and the regulatory
-- story. A single balance that mixes paid-in value with promotional
-- value starts to look like stored value rather than loyalty.
--
-- The bridge is one-way: coins convert INTO credits at a controlled rate
-- at redemption. Credits never convert back into coins.
--
-- REGULATORY PERIMETER (founder decision, closed-loop):
--   - non-transferable between users
--   - never redeemable for cash, in whole or in part
--   - redeemable only against NABD's own services
--   - no secondary market, no gifting, no off-platform value
-- Those four properties are what keep this outside the CBUAE Stored
-- Value Facilities regime. They are enforced here by constraint and by
-- the absence of any transfer path, not by policy. If any of them is
-- ever relaxed, this file needs a licensing review before the code
-- changes. Note also: the product never calls these "tokens".
-- =====================================================================

create type app.coin_reason as enum (
  -- Earning
  'venue_review', 'class_review', 'event_review', 'photo_upload',
  'attribute_correction', 'first_checkin_at_venue', 'checkin_streak',
  'meet_attendance', 'referral_completed', 'social_follow_claim',
  'ugc_post_verified', 'profile_completed', 'challenge_completed',
  'survey_completed', 'promotional_grant',
  -- Spending and adjustment
  'redeemed_for_credits', 'redeemed_for_catalogue_item',
  'redeemed_marketplace_discount', 'expired', 'clawback_moderation',
  'clawback_fraud', 'admin_adjustment'
);

create type app.review_subject_type as enum ('venue', 'class', 'event', 'meet', 'programme');

create type app.moderation_status as enum (
  'pending', 'auto_approved', 'approved', 'rejected', 'removed', 'shadow_hidden'
);

create type app.claim_verification_method as enum (
  -- Ranked by how much the platform can actually prove. See the comment on
  -- app.campaign_claims before choosing a reward size.
  'system_verified', 'partner_confirmed', 'moderator_reviewed',
  'screenshot_submitted', 'self_attested'
);

-- ---------------------------------------------------------------------
-- Earn rules. Every rule is a budget line, not a feature flag.
-- ---------------------------------------------------------------------
-- A rewards programme without caps is an unbounded liability. Each rule
-- carries a per-user cap, a per-subject cap and a share of a programme
-- budget, and the engine refuses to award once any of them is reached.
-- ---------------------------------------------------------------------

create table app.coin_earn_rules (
  id                    uuid primary key default gen_random_uuid(),
  code                  text not null unique,
  reason                app.coin_reason not null,
  name_en               text not null,
  name_ar               text not null,
  description_en        text,
  description_ar        text,

  coins_awarded         integer not null check (coins_awarded > 0),

  -- Caps. Null means uncapped on that axis, which should be rare and
  -- deliberate.
  max_per_user_per_month integer check (max_per_user_per_month > 0),
  max_per_user_lifetime  integer check (max_per_user_lifetime > 0),
  -- e.g. one paid review per venue per member per 90 days
  max_per_subject        integer check (max_per_subject > 0),
  subject_cooldown_days  integer,

  -- Requires a granted visit to the subject within this window. This is
  -- what makes a review verified rather than asserted.
  requires_verified_visit boolean not null default false,
  verified_visit_window_hours integer not null default 72,

  -- Minimum quality bar before anything is awarded.
  min_structured_answers integer not null default 0,
  min_text_length       integer not null default 0,
  requires_photo        boolean not null default false,

  -- Hold the award until moderation clears, for anything a human should
  -- see before it is paid for.
  requires_moderation   boolean not null default false,

  active_from           timestamptz not null default now(),
  active_to             timestamptz,
  is_active             boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index coin_earn_rules_active_idx on app.coin_earn_rules (is_active, reason);

comment on table app.coin_earn_rules is
  'Each row is a marketing budget line. Changing coins_awarded changes a liability, so changes belong in the audit log.';

-- ---------------------------------------------------------------------
-- Programme budget. The stop valve.
-- ---------------------------------------------------------------------

create table app.coin_budgets (
  id                  uuid primary key default gen_random_uuid(),
  period_start        date not null,
  period_end          date not null,
  -- Ceiling on coins issued in the period across all rules.
  max_coins_issued    bigint not null check (max_coins_issued > 0),
  coins_issued        bigint not null default 0,
  -- Accounting value of one coin in AED, used for liability reporting and
  -- for the coin-to-credit conversion rate.
  coin_value_aed      numeric(8,4) not null default 0.0500,
  -- Expected share of issued coins that will ever be redeemed. Drives the
  -- provision; the rest is breakage.
  expected_redemption_rate numeric(5,4) not null default 0.6000,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  unique (period_start, period_end),
  constraint coin_budget_period check (period_end > period_start)
);

-- ---------------------------------------------------------------------
-- Coin ledger. Append-only, same discipline as credits.
-- ---------------------------------------------------------------------

create table app.coin_ledger (
  id                bigserial primary key,
  user_id           uuid not null references app.profiles(id) on delete cascade,
  delta             integer not null check (delta <> 0),
  reason            app.coin_reason not null,
  rule_id           uuid references app.coin_earn_rules(id),

  ref_type          text,     -- 'review' | 'visit' | 'referral' | 'campaign_claim' | 'redemption'
  ref_id            uuid,

  -- Coins expire. An unexpiring loyalty balance is a liability that only
  -- ever grows, and it removes the urgency that makes the mechanic work.
  expires_at        timestamptz,
  -- Awards held pending moderation are written with delta but not counted
  -- as available until released.
  held_until        timestamptz,
  released_at       timestamptz,

  idempotency_key   text unique,
  notes             text,
  created_by        uuid references app.profiles(id),
  created_at        timestamptz not null default now()
);

create index coin_ledger_user_idx on app.coin_ledger (user_id, created_at desc);
create index coin_ledger_ref_idx  on app.coin_ledger (ref_type, ref_id);
create index coin_ledger_rule_idx on app.coin_ledger (rule_id, created_at desc);
create index coin_ledger_live_idx on app.coin_ledger (user_id)
  where expires_at is null or expires_at > now();

-- Available balance excludes expired and still-held awards.
create or replace function app.coin_balance(p_user_id uuid)
returns integer language sql stable as $$
  select coalesce(sum(delta), 0)::integer
  from app.coin_ledger
  where user_id = p_user_id
    and (expires_at is null or expires_at > now())
    and (held_until is null or held_until <= now() or released_at is not null);
$$;

create or replace view app.coin_balances as
select
  p.id as user_id,
  coalesce(sum(cl.delta) filter (
    where (cl.expires_at is null or cl.expires_at > now())
      and (cl.held_until is null or cl.held_until <= now() or cl.released_at is not null)
  ), 0)::integer as available,
  coalesce(sum(cl.delta) filter (
    where cl.held_until > now() and cl.released_at is null
  ), 0)::integer as pending,
  coalesce(sum(cl.delta) filter (where cl.delta > 0), 0)::integer as lifetime_earned
from app.profiles p
left join app.coin_ledger cl on cl.user_id = p.id
group by p.id;

-- Outstanding coin liability, for the management accounts. Issued minus
-- redeemed minus expired, valued at coin_value_aed and provisioned at the
-- expected redemption rate.
create or replace view app.coin_liability as
select
  b.id as budget_id,
  b.period_start,
  b.period_end,
  b.coin_value_aed,
  b.expected_redemption_rate,
  coalesce(sum(cl.delta) filter (where cl.delta > 0), 0) as coins_issued,
  coalesce(-sum(cl.delta) filter (where cl.delta < 0), 0) as coins_settled,
  coalesce(sum(cl.delta), 0) as coins_outstanding,
  round(
    coalesce(sum(cl.delta), 0) * b.coin_value_aed * b.expected_redemption_rate, 2
  ) as provision_aed
from app.coin_budgets b
left join app.coin_ledger cl
  on cl.created_at >= b.period_start
 and cl.created_at < (b.period_end + 1)
group by b.id, b.period_start, b.period_end, b.coin_value_aed, b.expected_redemption_rate;

-- ---------------------------------------------------------------------
-- Reviews
-- ---------------------------------------------------------------------
-- Founder decision: coins are paid for STRUCTURED DATA, never for stars.
--
-- Paying for a star rating buys rating inflation, and rating inflation
-- destroys the discovery ranking that the whole product depends on. So
-- the star rating earns nothing, the structured attributes earn the
-- coins, and the reward is identical whether the review is glowing or
-- damning. That last property is an invariant in the rewards engine, not
-- a setting: the instant a positive review is worth more than a negative
-- one, the dataset is worthless.
--
-- Every incentivised review is flagged and must be displayed as such.
-- ---------------------------------------------------------------------

create table app.reviews (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references app.profiles(id) on delete cascade,
  subject_type      app.review_subject_type not null,
  subject_id        uuid not null,

  -- Proof the member was actually there. Null only for review types that
  -- do not require attendance.
  visit_id          uuid references app.visits(id) on delete set null,
  class_booking_id  uuid references app.class_bookings(id) on delete set null,
  registration_id   uuid references app.event_registrations(id) on delete set null,

  rating            smallint check (rating between 1 and 5),

  -- The part that earns. Structured, comparable across venues, and far
  -- more useful to the next member than prose:
  -- { "busy_level": "moderate", "cleanliness": 4, "equipment_working": true,
  --   "showers_clean": 3, "gender_policy_honoured": true,
  --   "staff_helpful": 4, "wait_for_equipment_min": 5,
  --   "aircon_adequate": true, "parking_available": true }
  attributes        jsonb not null default '{}'::jsonb,
  attribute_count   integer generated always as
                    (coalesce(jsonb_array_length(jsonb_path_query_array(attributes, '$.*')), 0)) stored,

  body              text,
  body_language     app.language_code,
  photos            text[] not null default '{}',

  -- Disclosure. A review the member was paid for must say so, wherever it
  -- is shown. This column drives that label; it is not optional metadata.
  is_incentivised   boolean not null default false,
  coins_awarded     integer not null default 0,

  moderation_status app.moderation_status not null default 'pending',
  moderation_notes  text,
  moderated_by      uuid references app.profiles(id),
  moderated_at      timestamptz,

  -- Anti-abuse. Hash of the normalised body, to catch the same text
  -- pasted across twenty venues.
  body_hash         text,
  -- Seconds between opening and submitting the form. A three-second
  -- review is not a review.
  composition_seconds integer,

  helpful_count     integer not null default 0,
  partner_response  text,
  partner_responded_at timestamptz,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- One paid review per attended occasion, not per venue. A member who
  -- visits weekly should be able to review again; they should not be able
  -- to review the same visit twice.
  constraint reviews_one_per_visit unique nulls not distinct (user_id, visit_id),
  constraint reviews_incentivised_has_coins
    check (not is_incentivised or coins_awarded > 0)
);

create index reviews_subject_idx on app.reviews (subject_type, subject_id, created_at desc);
create index reviews_user_idx    on app.reviews (user_id, created_at desc);
create index reviews_published_idx on app.reviews (subject_type, subject_id)
  where moderation_status in ('approved', 'auto_approved');
create index reviews_body_hash_idx on app.reviews (body_hash)
  where body_hash is not null;
create index reviews_moderation_queue_idx on app.reviews (created_at)
  where moderation_status = 'pending';

comment on column app.reviews.is_incentivised is
  'Drives a mandatory visible disclosure label. Undisclosed paid reviews are a consumer-protection exposure, not merely a trust problem.';

comment on column app.reviews.rating is
  'Earns nothing. Coins are awarded for attributes, never for the star. Deliberate.';

-- Published aggregate per subject, with the incentivised share exposed
-- rather than hidden. If that ratio climbs, the ranking is drifting and
-- somebody needs to know.
create or replace view app.review_aggregates as
select
  subject_type,
  subject_id,
  count(*)                                             as review_count,
  round(avg(rating)::numeric, 2)                       as rating_avg,
  count(*) filter (where is_incentivised)              as incentivised_count,
  round(
    count(*) filter (where is_incentivised)::numeric
      / nullif(count(*), 0) * 100, 1
  )                                                    as incentivised_pct,
  round(avg(rating) filter (where not is_incentivised)::numeric, 2)
                                                       as organic_rating_avg
from app.reviews
where moderation_status in ('approved', 'auto_approved')
  and rating is not null
group by subject_type, subject_id;

-- ---------------------------------------------------------------------
-- Campaign claims: follows, shares, user-generated content
-- ---------------------------------------------------------------------
-- Honest limitation, recorded in the schema rather than discovered later:
-- the platform CANNOT verify that a member followed a venue's Instagram
-- page. No major social platform exposes "does user X follow page Y" to a
-- third party. So a follow claim is self-attested and trivially gamed,
-- and it is priced accordingly: the verification_method column exists so
-- that reward size can be tied to how much the platform can actually
-- prove.
--
-- The marketing mechanics that ARE verifiable, and should therefore carry
-- the real rewards, are: a referral where the referred member completed a
-- check-in, UGC confirmed by the venue itself, and a share that produced
-- a tracked install.
-- ---------------------------------------------------------------------

create table app.campaigns (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  name_en           text not null,
  name_ar           text not null,
  rule_id           uuid not null references app.coin_earn_rules(id),

  -- Who is funding it. A venue-funded campaign is a partner marketing
  -- spend, not ours, and settles through the payout.
  funded_by         text not null default 'platform'
                    check (funded_by in ('platform', 'partner', 'sponsor')),
  partner_id        uuid references app.partners(id) on delete set null,
  sponsor_name      text,

  target_type       text check (target_type in ('venue', 'club', 'event', 'platform')),
  target_id         uuid,
  target_url        text,          -- the social page or link being promoted

  verification_method app.claim_verification_method not null default 'self_attested',
  max_claims_total  integer,
  claims_made       integer not null default 0,

  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  constraint campaign_window check (ends_at > starts_at)
);

create index campaigns_active_idx on app.campaigns (is_active, starts_at, ends_at);

create table app.campaign_claims (
  id                uuid primary key default gen_random_uuid(),
  campaign_id       uuid not null references app.campaigns(id) on delete cascade,
  user_id           uuid not null references app.profiles(id) on delete cascade,

  verification_method app.claim_verification_method not null,
  -- Whatever evidence exists. For a self-attested follow this is empty,
  -- which is the point.
  evidence_url      text,
  external_handle   text,
  external_post_id  text,

  status            text not null default 'pending'
                    check (status in ('pending', 'verified', 'rejected', 'expired')),
  verified_by       uuid references app.profiles(id),
  verified_at       timestamptz,
  rejection_reason  text,

  coins_awarded     integer not null default 0,
  created_at        timestamptz not null default now(),
  unique (campaign_id, user_id)
);

create index campaign_claims_queue_idx on app.campaign_claims (status, created_at)
  where status = 'pending';

-- ---------------------------------------------------------------------
-- Referrals. The one acquisition mechanic that is fully verifiable.
-- ---------------------------------------------------------------------

create table app.referrals (
  id                uuid primary key default gen_random_uuid(),
  referrer_id       uuid not null references app.profiles(id) on delete cascade,
  referred_id       uuid references app.profiles(id) on delete set null,
  code              citext not null unique,

  -- Coins pay out on the qualifying action, not on signup. Paying at
  -- signup buys dormant accounts.
  qualifying_action text not null default 'first_checkin'
                    check (qualifying_action in
                      ('signup', 'first_checkin', 'first_meet', 'first_subscription')),
  qualified_at      timestamptz,

  referrer_coins    integer not null default 0,
  referred_coins    integer not null default 0,
  status            text not null default 'pending'
                    check (status in ('pending', 'qualified', 'paid', 'void')),
  void_reason       text,
  created_at        timestamptz not null default now()
);

create index referrals_referrer_idx on app.referrals (referrer_id, status);
create index referrals_code_idx     on app.referrals (code);

-- ---------------------------------------------------------------------
-- Redemption catalogue
-- ---------------------------------------------------------------------
-- What coins can be turned into. Note what is absent: cash, transfers to
-- other members, and anything with off-platform value. That absence is
-- the regulatory perimeter.
-- ---------------------------------------------------------------------

create table app.redemption_items (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  name_en           text not null,
  name_ar           text not null,
  description_en    text,
  description_ar    text,

  kind              text not null check (kind in
                    ('credits', 'class_pass', 'event_ticket', 'marketplace_discount',
                     'merchandise', 'programme_discount')),
  coin_cost         integer not null check (coin_cost > 0),

  -- For kind = 'credits': how many credits the coins convert into. The
  -- one-way bridge between the two ledgers.
  credits_granted   integer check (credits_granted > 0),
  -- For discount kinds: value and the cap on how much of an order coins
  -- may cover. A coin-funded order that is 100 percent discounted is a
  -- free product paid for out of the marketing budget.
  discount_aed      numeric(10,2),
  max_order_share_pct numeric(5,2) check (max_order_share_pct between 0 and 100),

  ref_type          text,
  ref_id            uuid,

  stock_total       integer,
  stock_claimed     integer not null default 0,
  max_per_user      integer not null default 1,

  tier_required     app.tier_code,
  available_from    timestamptz,
  available_to      timestamptz,
  is_active         boolean not null default true,
  sort_order        integer not null default 0,
  created_at        timestamptz not null default now(),

  constraint redemption_credits_shape
    check (kind <> 'credits' or credits_granted is not null),
  constraint redemption_stock_not_exceeded
    check (stock_total is null or stock_claimed <= stock_total)
);

create index redemption_items_active_idx on app.redemption_items (is_active, sort_order);

create table app.redemptions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references app.profiles(id) on delete cascade,
  item_id           uuid not null references app.redemption_items(id) on delete restrict,
  coins_spent       integer not null check (coins_spent > 0),
  -- Snapshot of what the coins bought and at what rate, frozen. Catalogue
  -- prices change; a member's past redemption must not.
  fulfilment_snapshot jsonb not null default '{}'::jsonb,
  status            text not null default 'fulfilled'
                    check (status in ('pending', 'fulfilled', 'failed', 'reversed')),
  fulfilled_at      timestamptz,
  reversed_at       timestamptz,
  reversal_reason   text,
  idempotency_key   text unique,
  created_at        timestamptz not null default now()
);

create index redemptions_user_idx on app.redemptions (user_id, created_at desc);

-- ---------------------------------------------------------------------
-- Gates and maintenance
-- ---------------------------------------------------------------------

-- A review may only be marked incentivised if a verified visit backs it.
create or replace function app.enforce_review_verification()
returns trigger language plpgsql set search_path = app, public as $$
declare
  v_visit record;
begin
  if not new.is_incentivised then
    return new;
  end if;

  if new.visit_id is null
     and new.class_booking_id is null
     and new.registration_id is null then
    raise exception 'Incentivised review requires proof of attendance'
      using errcode = 'check_violation';
  end if;

  if new.visit_id is not null then
    select user_id, status, reversed_at into v_visit
    from app.visits where id = new.visit_id;

    if v_visit.user_id <> new.user_id then
      raise exception 'Review visit belongs to a different member'
        using errcode = 'check_violation';
    end if;
    if v_visit.status not in ('granted', 'manual_override') or v_visit.reversed_at is not null then
      raise exception 'Review must reference a granted, unreversed visit'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end $$;

create trigger reviews_verification_gate
  before insert or update on app.reviews
  for each row execute function app.enforce_review_verification();

-- Removing a review claws back the coins it earned. Without this, a member
-- can farm coins with content that is deleted the moment anyone looks.
create or replace function app.clawback_on_review_removal()
returns trigger language plpgsql set search_path = app, public as $$
begin
  if new.moderation_status in ('rejected', 'removed')
     and old.moderation_status not in ('rejected', 'removed')
     and new.coins_awarded > 0 then

    insert into app.coin_ledger (user_id, delta, reason, ref_type, ref_id, notes)
    values (new.user_id, -new.coins_awarded, 'clawback_moderation', 'review', new.id,
            'Review ' || new.moderation_status || ': ' || coalesce(new.moderation_notes, ''));
  end if;
  return new;
end $$;

create trigger reviews_clawback
  after update on app.reviews
  for each row execute function app.clawback_on_review_removal();

-- Keep the venue's denormalised rating in step with published reviews.
create or replace function app.sync_venue_rating()
returns trigger language plpgsql set search_path = app, public as $$
declare v_subject uuid;
begin
  v_subject := coalesce(new.subject_id, old.subject_id);

  if coalesce(new.subject_type, old.subject_type) <> 'venue' then
    return null;
  end if;

  update app.venues v
  set rating_avg = agg.rating_avg,
      rating_count = agg.review_count
  from app.review_aggregates agg
  where agg.subject_type = 'venue'
    and agg.subject_id = v_subject
    and v.id = v_subject;

  return null;
end $$;

create trigger reviews_venue_rating_sync
  after insert or update or delete on app.reviews
  for each row execute function app.sync_venue_rating();

-- Daily: expire coins past their date. Expiry is written as an explicit
-- negative entry rather than left implicit, so the ledger sums to the
-- balance without a date filter in reporting.
create or replace function app.expire_coins()
returns integer language plpgsql set search_path = app, public as $$
declare v_count integer := 0;
begin
  with expiring as (
    select user_id, sum(delta) as amount
    from app.coin_ledger
    where expires_at is not null
      and expires_at <= now()
      and delta > 0
      and not exists (
        select 1 from app.coin_ledger x
        where x.ref_type = 'expiry_of'
          and x.ref_id = app.coin_ledger.id
      )
    group by user_id
    having sum(delta) > 0
  )
  insert into app.coin_ledger (user_id, delta, reason, ref_type, notes)
  select user_id, -amount, 'expired', 'expiry_sweep', 'Automatic expiry'
  from expiring;

  get diagnostics v_count = row_count;

  insert into app.audit_log (action, subject_type, after_state)
  values ('coins.expiry_sweep', 'system', jsonb_build_object('members_affected', v_count));

  return v_count;
end $$;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------

alter table app.coin_earn_rules   enable row level security;
alter table app.coin_budgets      enable row level security;
alter table app.coin_ledger       enable row level security;
alter table app.reviews           enable row level security;
alter table app.campaigns         enable row level security;
alter table app.campaign_claims   enable row level security;
alter table app.referrals         enable row level security;
alter table app.redemption_items  enable row level security;
alter table app.redemptions       enable row level security;

create policy coin_earn_rules_read on app.coin_earn_rules
  for select using (is_active);

-- Budgets are commercially sensitive. Admin only; no member-facing policy.
create policy coin_budgets_admin on app.coin_budgets
  for select using (app.is_platform_admin());

-- Members read their own ledger. All writes are service-role: a member who
-- can insert a coin row has an unlimited balance.
create policy coin_ledger_owner on app.coin_ledger
  for select using (user_id = auth.uid() or app.is_platform_admin());

create policy reviews_public_read on app.reviews
  for select using (
    moderation_status in ('approved', 'auto_approved')
    or user_id = auth.uid()
    or app.is_platform_admin()
  );

create policy reviews_author_write on app.reviews
  for insert with check (user_id = auth.uid());

-- Editing is limited to the author, and only while still pending. A
-- review that has been approved and paid for cannot be quietly rewritten.
create policy reviews_author_update on app.reviews
  for update using (user_id = auth.uid() and moderation_status = 'pending')
  with check (user_id = auth.uid());

create policy campaigns_read on app.campaigns
  for select using (is_active and now() between starts_at and ends_at);

create policy campaign_claims_owner on app.campaign_claims
  for select using (user_id = auth.uid() or app.is_platform_admin());
create policy campaign_claims_create on app.campaign_claims
  for insert with check (user_id = auth.uid());

create policy referrals_owner on app.referrals
  for select using (
    referrer_id = auth.uid() or referred_id = auth.uid() or app.is_platform_admin()
  );

create policy redemption_items_read on app.redemption_items
  for select using (is_active);

create policy redemptions_owner on app.redemptions
  for select using (user_id = auth.uid() or app.is_platform_admin());

grant select on app.coin_balances, app.review_aggregates to authenticated;
grant insert, update on app.reviews to authenticated;
grant insert on app.campaign_claims to authenticated;
