-- =====================================================================
-- NABD :: 0004 :: Plans, subscriptions, pauses and the credit ledger
-- ---------------------------------------------------------------------
-- The credit ledger is append-only. Balances are derived, never stored as
-- a mutable column, because a mutable balance with concurrent writers is
-- how members end up with free access and partners end up unpaid.
-- =====================================================================

create table app.plans (
  id                    uuid primary key default gen_random_uuid(),
  code                  text not null unique,      -- 'core_monthly', 'elite_annual'
  tier                  app.tier_code not null,
  name_en               text not null,
  name_ar               text not null,
  description_en        text,
  description_ar        text,

  -- Prices are VAT-inclusive display prices; the VAT component is derived
  -- at invoice time. All amounts in AED fils-precision.
  price_aed             numeric(10,2) not null check (price_aed >= 0),
  billing_interval      text not null default 'month'
                        check (billing_interval in ('month', 'quarter', 'year')),
  vat_rate_pct          numeric(5,2) not null default 5.00,

  monthly_credits       integer not null default 0 check (monthly_credits >= 0),
  -- Unused credits carried into the next cycle, capped. Uncapped rollover
  -- creates a large unfunded liability on the balance sheet.
  credit_rollover_cap   integer not null default 0 check (credit_rollover_cap >= 0),

  -- Default per-venue monthly visit cap. Venue-level caps override.
  default_venue_monthly_cap integer not null default 4 check (default_venue_monthly_cap > 0),

  -- Emirates this plan grants access in. Empty = all.
  emirates_covered      app.emirate[] not null default '{}',

  max_pause_days_per_year integer not null default 30,
  min_pause_days        integer not null default 7,
  max_pauses_per_year   integer not null default 2,

  -- Provider price identifiers.
  stripe_price_id       text,
  stripe_product_id     text,

  features              jsonb not null default '{}'::jsonb,
  is_addon              boolean not null default false,
  is_public             boolean not null default true,
  sort_order            integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index plans_public_idx on app.plans (is_public, sort_order);

-- ---------------------------------------------------------------------
-- Subscriptions
-- ---------------------------------------------------------------------

create table app.subscriptions (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references app.profiles(id) on delete cascade,
  plan_id               uuid not null references app.plans(id) on delete restrict,

  status                app.subscription_status not null default 'active',

  provider              app.payment_provider not null default 'stripe',
  stripe_subscription_id text unique,
  stripe_customer_id    text,

  started_at            timestamptz not null default now(),
  current_period_start  timestamptz not null,
  current_period_end    timestamptz not null,
  trial_ends_at         timestamptz,

  cancel_at_period_end  boolean not null default false,
  cancelled_at          timestamptz,
  cancellation_reason   text,
  ended_at              timestamptz,

  -- Denormalised pause state for the hot path. The audit trail lives in
  -- app.subscription_pauses; these three columns exist so the check-in
  -- entitlement query does not need a second join.
  pause_starts_at       timestamptz,
  pause_ends_at         timestamptz,
  pause_days_used_this_year integer not null default 0 check (pause_days_used_this_year >= 0),
  pauses_used_this_year integer not null default 0,
  pause_year_resets_at  timestamptz,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint subscriptions_period_order check (current_period_end > current_period_start),
  constraint subscriptions_pause_order
    check (pause_ends_at is null or pause_starts_at is null or pause_ends_at > pause_starts_at)
);

-- A member holds at most one live base subscription. Add-ons are separate
-- rows flagged via the plan, so this partial index targets base plans only.
create unique index subscriptions_one_active_per_user_idx
  on app.subscriptions (user_id)
  where status in ('trialing', 'active', 'paused', 'past_due');

create index subscriptions_status_idx on app.subscriptions (status);
create index subscriptions_period_end_idx on app.subscriptions (current_period_end)
  where status = 'active';

-- ---------------------------------------------------------------------
-- Pause audit trail
-- ---------------------------------------------------------------------
-- Community access deliberately continues during a pause: a paused member
-- who keeps running with their club on Tuesdays comes back in September.
-- A paused member who disappears entirely does not.
-- ---------------------------------------------------------------------

create table app.subscription_pauses (
  id              uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references app.subscriptions(id) on delete cascade,
  user_id         uuid not null references app.profiles(id) on delete cascade,
  requested_at    timestamptz not null default now(),
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  days            integer generated always as
                  (greatest(1, (ends_at::date - starts_at::date))) stored,
  reason          text,                        -- 'travel' | 'injury' | 'ramadan' | 'other'
  credits_frozen  integer not null default 0,
  cancelled_early_at timestamptz,
  created_at      timestamptz not null default now(),
  constraint pause_order check (ends_at > starts_at)
);

create index subscription_pauses_user_idx on app.subscription_pauses (user_id, starts_at desc);

-- Prevent overlapping pauses on one subscription.
alter table app.subscription_pauses
  add constraint subscription_pauses_no_overlap
  exclude using gist (
    subscription_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (cancelled_early_at is null);

-- ---------------------------------------------------------------------
-- Credit ledger. Append-only, double-entry in spirit.
-- ---------------------------------------------------------------------

create table app.credit_ledger (
  id              bigserial primary key,
  user_id         uuid not null references app.profiles(id) on delete cascade,
  -- Positive = grant, negative = spend. Never update a row; reverse it.
  delta           integer not null check (delta <> 0),
  reason          app.credit_reason not null,
  -- What the credits were spent on or granted for.
  ref_type        text,       -- 'visit' | 'class_booking' | 'court_booking' | 'event_registration'
  ref_id          uuid,
  -- Credits expire at cycle end unless rolled over.
  expires_at      timestamptz,
  consumed_at     timestamptz,
  -- Idempotency guard: a retried check-in must not double-charge.
  idempotency_key text unique,
  notes           text,
  created_by      uuid references app.profiles(id),
  created_at      timestamptz not null default now()
);

create index credit_ledger_user_idx on app.credit_ledger (user_id, created_at desc);
create index credit_ledger_ref_idx  on app.credit_ledger (ref_type, ref_id);
create index credit_ledger_live_idx on app.credit_ledger (user_id)
  where expires_at is null or expires_at > now();

-- Balance is derived. Materialise it later if the ledger grows large, but
-- never replace it with a mutable column.
create or replace function app.credit_balance(p_user_id uuid)
returns integer
language sql stable as $$
  select coalesce(sum(delta), 0)::integer
  from app.credit_ledger
  where user_id = p_user_id
    and (expires_at is null or expires_at > now());
$$;

create or replace view app.credit_balances as
select
  p.id as user_id,
  coalesce(sum(cl.delta) filter (
    where cl.expires_at is null or cl.expires_at > now()
  ), 0)::integer as balance
from app.profiles p
left join app.credit_ledger cl on cl.user_id = p.id
group by p.id;

-- ---------------------------------------------------------------------
-- Entitlement resolution view.
-- ---------------------------------------------------------------------
-- Single source of truth read by the check-in endpoint. One row per member
-- with everything the entitlement engine needs, so the hot path is one
-- indexed read rather than five joins written by hand in a route handler.
-- ---------------------------------------------------------------------

create or replace view app.member_entitlements as
select
  s.user_id,
  s.id                        as subscription_id,
  s.status                    as subscription_status,
  s.current_period_start,
  s.current_period_end,
  s.pause_starts_at,
  s.pause_ends_at,
  pl.id                       as plan_id,
  pl.code                     as plan_code,
  pl.tier                     as tier,
  pl.default_venue_monthly_cap,
  pl.emirates_covered,
  pr.gender                   as member_gender,
  app.age_band(pr.date_of_birth) as age_band,
  pr.is_suspended,
  coalesce(cb.balance, 0)     as credit_balance
from app.subscriptions s
join app.plans    pl on pl.id = s.plan_id
join app.profiles pr on pr.id = s.user_id
left join app.credit_balances cb on cb.user_id = s.user_id
where s.status in ('trialing', 'active', 'paused', 'past_due');
