-- =====================================================================
-- NABD :: 0012 :: Supplements marketplace, academies, programmes, camps
-- ---------------------------------------------------------------------
-- Phase 2 and 3 supply. Two separate regulatory regimes, both heavier
-- than anything in migrations 0001 to 0011.
--
-- MARKETPLACE (founder decision: agent model, verified sellers).
--   NABD never imports, never holds stock and is never the merchant of
--   record. Licensed UAE retailers list; the platform verifies the
--   seller's trade licence and each product's registration before it can
--   be listed, and displays the registration number publicly.
--
--   That verification IS the "authentic products" claim. A marketing
--   promise of authenticity with nothing enforcing it is a warranty the
--   platform cannot honour, so the gate is a trigger rather than a
--   process. UAE supplements require MOHAP registration (therapeutic
--   claims or pharmaceutical actives) or Dubai Municipality approval
--   (vitamins and minerals, no disease claims), Arabic labelling, a GMP
--   certificate and a certificate of analysis. Several ingredients are
--   outright prohibited and carry criminal exposure, so the banned
--   screen below is checked before listing, not after a seizure.
--
-- PROGRAMMES AND MINORS (founder decision: model now, launch phase 3).
--   Anything involving children changes the trust bar and the legal
--   exposure completely. Children do not get their own login; they exist
--   as guardian-managed profiles. A programme admitting minors cannot
--   publish without a verified academy, in-date coach vetting, a
--   safeguarding policy, current insurance and a declared supervision
--   ratio. Trigger-enforced, same pattern as the event permit gate.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------

create type app.product_category as enum (
  'protein', 'amino_acids', 'pre_workout', 'creatine', 'vitamins',
  'minerals', 'omega_fatty_acids', 'hydration', 'weight_management',
  'joint_support', 'snack_bar', 'equipment', 'apparel', 'recovery_device'
);

create type app.product_registration_authority as enum (
  'mohap', 'dubai_municipality', 'abu_dhabi_agriculture_food', 'moiat', 'not_required'
);

create type app.listing_status as enum (
  'draft', 'pending_verification', 'active', 'out_of_stock',
  'suspended', 'registration_expired', 'delisted'
);

create type app.marketplace_order_status as enum (
  'pending_payment', 'paid', 'accepted', 'shipped',
  'delivered', 'cancelled', 'refunded', 'disputed'
);

create type app.programme_kind as enum (
  'term_course',      -- 12-week football term, karate belt course
  'academy_squad',    -- season-long squad membership
  'holiday_camp',     -- school break camp
  'clinic_series',    -- short skills series
  'club_membership'   -- adult sporting club season membership
);

create type app.enrolment_status as enum (
  'reserved', 'confirmed', 'waitlisted', 'cancelled',
  'refunded', 'completed', 'withdrawn'
);

create type app.vetting_status as enum (
  'not_started', 'submitted', 'in_progress', 'cleared', 'rejected', 'expired'
);

-- =====================================================================
-- PART A :: MARKETPLACE
-- =====================================================================

create table app.sellers (
  id                    uuid primary key default gen_random_uuid(),
  owner_user_id         uuid not null references app.profiles(id) on delete restrict,

  legal_name            text not null,
  trading_name          text not null,
  trading_name_ar       text,

  -- Verification inputs. A seller without a current licence carrying the
  -- right trading activity cannot sell regulated goods here.
  trade_licence_number  text not null,
  licence_authority     text not null,
  licence_activity      text not null,
  licence_expires_at    date not null,
  trn                   text check (trn ~ '^[0-9]{15}$'),
  is_vat_registered     boolean not null default false,

  contact_email         citext not null,
  contact_phone         text not null,
  warehouse_emirate     app.emirate,

  is_verified           boolean not null default false,
  verified_at           timestamptz,
  verified_by           uuid references app.profiles(id),

  -- Agent model: platform takes a commission, the seller remains merchant
  -- of record and carries product liability.
  commission_pct        numeric(5,2) not null default 12.00
                        check (commission_pct between 0 and 100),
  payout_iban           text,

  fulfilment_sla_hours  integer not null default 48,
  return_policy_en      text,
  return_policy_ar      text,

  rating_avg            numeric(3,2),
  rating_count          integer not null default 0,
  is_suspended          boolean not null default false,
  suspension_reason     text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index sellers_verified_idx on app.sellers (is_verified) where not is_suspended;
create index sellers_licence_expiry_idx on app.sellers (licence_expires_at) where is_verified;

comment on table app.sellers is
  'Merchant of record. NABD acts as agent and never imports or holds stock; product liability sits with the seller.';

-- ---------------------------------------------------------------------
-- Products
-- ---------------------------------------------------------------------

create table app.products (
  id                    uuid primary key default gen_random_uuid(),
  slug                  citext not null unique,

  brand                 text not null,
  name_en               text not null,
  name_ar               text not null,        -- required: Arabic labelling
  description_en        text,
  description_ar        text,

  category              app.product_category not null,
  disciplines           app.discipline[] not null default '{}',

  -- Identity
  gtin                  text,                 -- barcode, for authenticity matching
  manufacturer_name     text not null,
  country_of_origin     text not null,

  -- Pack
  net_weight_g          numeric(10,2),
  net_volume_ml         numeric(10,2),
  servings_per_pack     integer,
  serving_size_g        numeric(8,2),
  flavour               text,

  -- "Full nutritional value", structured rather than a PDF, so it can be
  -- compared, filtered and checked. Per serving.
  -- { "energy_kcal": 120, "protein_g": 24, "carbohydrate_g": 3,
  --   "of_which_sugars_g": 1, "fat_g": 1.5, "of_which_saturates_g": 0.8,
  --   "fibre_g": 0, "salt_g": 0.1, "sodium_mg": 40,
  --   "amino_acid_profile": { "leucine_mg": 2700 },
  --   "vitamins": { "b12_ug": 2.4 } }
  nutrition_per_serving jsonb not null default '{}'::jsonb,
  ingredients_en        text not null,
  ingredients_ar        text not null,
  allergens_en          text[],
  allergens_ar          text[],
  directions_en         text,
  directions_ar         text,
  -- Therapeutic claims are prohibited on food supplements here, so the
  -- mandatory disclaimer travels with the product rather than the listing.
  disclaimer_en         text not null default
    'Food supplement. Not a substitute for a varied diet. Not intended to diagnose, treat, cure or prevent any disease.',
  disclaimer_ar         text not null default
    'مكمل غذائي. لا يغني عن نظام غذائي متوازن. غير مخصص لتشخيص أي مرض أو علاجه أو الوقاية منه.',

  images                text[] not null default '{}',
  label_image_url       text,                 -- the physical Arabic label

  is_halal_certified    boolean,
  halal_certifier       text,
  is_vegan              boolean,

  created_by_seller_id  uuid references app.sellers(id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index products_category_idx on app.products (category);
create index products_brand_idx    on app.products (brand);
create index products_gtin_idx     on app.products (gtin) where gtin is not null;
create index products_nutrition_idx on app.products using gin (nutrition_per_serving);

comment on column app.products.nutrition_per_serving is
  'Structured and mandatory. A nutrition panel buried in a PDF cannot be compared or filtered, which is the entire value the member was promised.';

-- ---------------------------------------------------------------------
-- Product registrations. The gate behind the authenticity claim.
-- ---------------------------------------------------------------------

create table app.product_registrations (
  id                    uuid primary key default gen_random_uuid(),
  product_id            uuid not null references app.products(id) on delete cascade,

  authority             app.product_registration_authority not null,
  registration_number   text not null,
  registered_holder     text not null,        -- whose registration it is
  issued_at             date,
  expires_at            date,
  certificate_url       text,

  -- Supporting evidence the regulator expects to exist.
  gmp_certificate_url   text,
  certificate_of_analysis_url text,
  coa_lab_name          text,
  coa_issued_at         date,
  stability_report_url  text,

  -- Prohibited-substance screen. Several ingredients are banned outright
  -- in the UAE and carry criminal exposure, so a product does not go live
  -- until this has been run and passed.
  banned_screen_status  text not null default 'pending'
                        check (banned_screen_status in ('pending', 'passed', 'failed')),
  banned_screen_notes   text,
  banned_screen_at      timestamptz,

  verified_at           timestamptz,
  verified_by           uuid references app.profiles(id),
  created_at            timestamptz not null default now(),
  unique (product_id, authority, registration_number)
);

create index product_registrations_product_idx on app.product_registrations (product_id);
create index product_registrations_expiry_idx  on app.product_registrations (expires_at)
  where verified_at is not null;

comment on table app.product_registrations is
  'MOHAP for therapeutic claims or pharmaceutical actives; Dubai Municipality for vitamins and minerals without disease claims. Verify the current regime before each onboarding; requirements move.';

-- ---------------------------------------------------------------------
-- Listings: one seller offering one product
-- ---------------------------------------------------------------------

create table app.product_listings (
  id                    uuid primary key default gen_random_uuid(),
  seller_id             uuid not null references app.sellers(id) on delete cascade,
  product_id            uuid not null references app.products(id) on delete restrict,

  status                app.listing_status not null default 'draft',

  price_aed             numeric(10,2) not null check (price_aed >= 0),
  compare_at_aed        numeric(10,2),
  vat_rate_pct          numeric(5,2) not null default 5.00,

  -- Coins fund a discount, capped so an order can never be fully
  -- coin-funded. A 100 percent coin-funded order is a free product paid
  -- for out of the marketing budget.
  coins_accepted        boolean not null default true,
  max_coin_discount_pct numeric(5,2) not null default 20.00
                        check (max_coin_discount_pct between 0 and 50),

  stock_quantity        integer not null default 0 check (stock_quantity >= 0),
  low_stock_threshold   integer not null default 5,
  batch_number          text,
  expiry_date           date,

  ships_from_emirate    app.emirate,
  delivery_days_min     integer not null default 1,
  delivery_days_max     integer not null default 3,
  free_delivery_over_aed numeric(10,2),

  listed_at             timestamptz,
  delisted_at           timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (seller_id, product_id)
);

create index product_listings_active_idx on app.product_listings (status, price_aed)
  where status = 'active';
create index product_listings_product_idx on app.product_listings (product_id, price_aed);
create index product_listings_expiry_idx on app.product_listings (expiry_date)
  where status = 'active';

-- ---------------------------------------------------------------------
-- Orders. Agent model: gross passes through, the fee is the revenue.
-- ---------------------------------------------------------------------

create table app.marketplace_orders (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references app.profiles(id) on delete restrict,
  seller_id             uuid not null references app.sellers(id) on delete restrict,
  order_id              uuid references app.orders(id) on delete set null,

  status                app.marketplace_order_status not null default 'pending_payment',

  subtotal_aed          numeric(12,2) not null,
  delivery_fee_aed      numeric(12,2) not null default 0,
  coin_discount_aed     numeric(12,2) not null default 0,
  coins_spent           integer not null default 0,
  vat_amount_aed        numeric(12,2) not null default 0,
  total_aed             numeric(12,2) not null,

  -- Agent: only the commission is NABD revenue. The rest is a pass-through
  -- to the seller, which is why supply_role is pinned rather than defaulted.
  supply_role           app.supply_role not null default 'agent',
  commission_aed        numeric(12,2) not null default 0,

  delivery_name         text not null,
  delivery_phone        text not null,
  delivery_address      text not null,
  delivery_emirate      app.emirate not null,
  delivery_notes        text,

  tracking_reference    text,
  shipped_at            timestamptz,
  delivered_at          timestamptz,
  cancelled_at          timestamptz,
  cancellation_reason   text,

  idempotency_key       text unique,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index marketplace_orders_user_idx   on app.marketplace_orders (user_id, created_at desc);
create index marketplace_orders_seller_idx on app.marketplace_orders (seller_id, status, created_at desc);

create table app.marketplace_order_lines (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references app.marketplace_orders(id) on delete cascade,
  listing_id        uuid not null references app.product_listings(id) on delete restrict,
  product_id        uuid not null references app.products(id) on delete restrict,
  quantity          integer not null check (quantity > 0),
  unit_price_aed    numeric(10,2) not null,
  line_total_aed    numeric(12,2) not null,
  -- Product name, registration number and nutrition frozen at purchase.
  -- A member must be able to see what they were shown, not what the
  -- listing says today.
  product_snapshot  jsonb not null default '{}'::jsonb,
  batch_number      text,
  expiry_date       date,
  created_at        timestamptz not null default now()
);

create index marketplace_order_lines_order_idx on app.marketplace_order_lines (order_id);

create table app.seller_payouts (
  id                uuid primary key default gen_random_uuid(),
  seller_id         uuid not null references app.sellers(id) on delete restrict,
  period_start      date not null,
  period_end        date not null,
  orders_count      integer not null default 0,
  gross_aed         numeric(12,2) not null default 0,
  commission_aed    numeric(12,2) not null default 0,
  refunds_aed       numeric(12,2) not null default 0,
  -- Coin-funded discounts are our marketing spend, not the seller's, so
  -- the seller is made whole for them.
  coin_subsidy_aed  numeric(12,2) not null default 0,
  net_payable_aed   numeric(12,2) not null default 0,
  status            app.payout_status not null default 'accruing',
  paid_at           timestamptz,
  remittance_reference text,
  created_at        timestamptz not null default now(),
  unique (seller_id, period_start, period_end)
);

-- =====================================================================
-- PART B :: ACADEMIES, PROGRAMMES, CAMPS AND MINORS
-- =====================================================================

create table app.academies (
  id                    uuid primary key default gen_random_uuid(),
  owner_user_id         uuid not null references app.profiles(id) on delete restrict,
  partner_id            uuid references app.partners(id) on delete set null,

  name_en               text not null,
  name_ar               text,
  description_en        text,
  description_ar        text,
  disciplines           app.discipline[] not null default '{}',

  emirate               app.emirate not null,
  area                  text,
  location              geography(Point, 4326),

  -- Licensing. A sports academy in Dubai needs a trade licence with the
  -- sports instruction activity plus Dubai Sports Council approval, with
  -- parallel regimes in the other emirates. Where the offer is
  -- educational rather than purely recreational, KHDA or the relevant
  -- education authority may also apply; that judgement is recorded rather
  -- than assumed.
  trade_licence_number  text not null,
  licence_authority     text not null,
  licence_expires_at    date not null,
  sports_council_permit text,
  sports_council_expires_at date,
  education_authority_permit text,
  education_authority_note text,

  -- Safeguarding. Required before any programme admitting minors can be
  -- published.
  safeguarding_policy_url text,
  safeguarding_policy_version text,
  safeguarding_lead_name text,
  safeguarding_lead_phone text,
  safeguarding_reviewed_at date,

  accepts_minors        boolean not null default false,
  is_verified           boolean not null default false,
  verified_at           timestamptz,
  verified_by           uuid references app.profiles(id),
  is_suspended          boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index academies_discipline_idx on app.academies using gin (disciplines);
create index academies_location_idx   on app.academies using gist (location);
create index academies_verified_idx   on app.academies (is_verified, emirate);

-- ---------------------------------------------------------------------
-- Coaches and vetting
-- ---------------------------------------------------------------------
-- A coach working unsupervised with children must have an in-date
-- background check on file. The vetting record is what the publication
-- gate reads, so an expired check silently blocks new programmes rather
-- than being noticed at an inspection.
-- ---------------------------------------------------------------------

create table app.coaches (
  id                    uuid primary key default gen_random_uuid(),
  academy_id            uuid not null references app.academies(id) on delete cascade,
  user_id               uuid references app.profiles(id) on delete set null,

  full_name             text not null,
  disciplines           app.discipline[] not null default '{}',
  bio_en                text,
  bio_ar                text,
  photo_url             text,
  languages             text[] not null default '{}',

  -- Coaching qualifications, structured so expiry can be checked.
  -- [{ "body": "AFC", "level": "C Licence", "expires_at": "2028-05-01" }]
  certifications        jsonb not null default '[]'::jsonb,
  first_aid_expires_at  date,

  -- Background check.
  vetting_status        app.vetting_status not null default 'not_started',
  vetting_provider      text,
  vetting_reference     text,
  vetting_cleared_at    date,
  vetting_expires_at    date,
  works_with_minors     boolean not null default false,

  is_active             boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  -- The single most important constraint in this file.
  constraint coaches_minors_need_vetting
    check (not works_with_minors or vetting_status = 'cleared')
);

create index coaches_academy_idx on app.coaches (academy_id, is_active);
create index coaches_vetting_expiry_idx on app.coaches (vetting_expires_at)
  where works_with_minors;

-- ---------------------------------------------------------------------
-- Child profiles. Guardian-managed, no login of their own.
-- ---------------------------------------------------------------------
-- A seven-year-old does not get an account. The child exists only as a
-- record owned by a guardian's account, which is also what keeps the
-- child's data inside one accountable relationship for PDPL purposes.
-- ---------------------------------------------------------------------

create table app.child_profiles (
  id                    uuid primary key default gen_random_uuid(),
  guardian_user_id      uuid not null references app.profiles(id) on delete cascade,

  first_name            text not null,
  last_name             text not null,
  date_of_birth         date not null,
  gender                app.gender,

  school_name           text,
  -- High sensitivity. Restricted role, visible to programme medical and
  -- safeguarding staff only, never to marketing, never to sellers.
  medical_notes         text,
  allergies             text,
  -- Adults permitted to collect the child. Structured because a verbal
  -- arrangement at the gate is exactly where safeguarding fails.
  -- [{ "name": "...", "relationship": "...", "phone": "...", "id_last4": "1234" }]
  authorised_collectors jsonb not null default '[]'::jsonb,
  photo_consent         boolean not null default false,

  is_active             boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index child_profiles_guardian_idx on app.child_profiles (guardian_user_id)
  where is_active;

comment on table app.child_profiles is
  'PDPL high sensitivity. Children have no login; the guardian account is the accountable data subject relationship. Medical notes and collector details are restricted-role only.';

-- ---------------------------------------------------------------------
-- Programmes. Multi-week fixed cohorts, distinct from drop-in classes
-- and one-off events.
-- ---------------------------------------------------------------------

create table app.programmes (
  id                    uuid primary key default gen_random_uuid(),
  academy_id            uuid not null references app.academies(id) on delete cascade,
  venue_id              uuid references app.venues(id) on delete set null,

  slug                  citext not null unique,
  name_en               text not null,
  name_ar               text,
  description_en        text,
  description_ar        text,

  kind                  app.programme_kind not null,
  discipline            app.discipline not null,
  level                 text,                  -- 'Beginner', 'White to Yellow belt'

  -- Cohort window.
  starts_on             date not null,
  ends_on               date not null,
  -- [{ "dow": 1, "start": "16:00", "end": "17:00" }]
  weekly_schedule       jsonb not null default '[]'::jsonb,
  sessions_total        integer not null check (sessions_total > 0),

  -- Holiday camps run daily across a school break rather than weekly.
  is_full_day           boolean not null default false,
  daily_start_time      time,
  daily_end_time        time,
  includes_meals        boolean not null default false,
  includes_transport    boolean not null default false,

  -- Who it is for.
  min_age               integer,
  max_age               integer,
  admits_minors         boolean not null default false,
  gender_policy         app.gender_policy not null default 'mixed',

  capacity              integer not null check (capacity > 0),
  enrolled_count        integer not null default 0,
  -- Children per supervising adult. A programme for minors cannot publish
  -- without this set.
  supervision_ratio     integer check (supervision_ratio > 0),

  price_aed             numeric(10,2) not null check (price_aed >= 0),
  vat_rate_pct          numeric(5,2) not null default 5.00,
  sibling_discount_pct  numeric(5,2) check (sibling_discount_pct between 0 and 100),
  -- Term fees are large; instalments are the norm in this market.
  allows_instalments    boolean not null default false,
  instalment_count      integer check (instalment_count between 2 and 12),
  coins_accepted        boolean not null default true,
  max_coin_discount_pct numeric(5,2) not null default 10.00,

  trial_session_available boolean not null default false,
  trial_price_aed       numeric(10,2),

  requires_waiver       boolean not null default true,
  waiver_id             uuid references app.waivers(id),

  status                app.event_status not null default 'draft',
  registration_opens_at timestamptz,
  registration_closes_at timestamptz,
  cover_image_url       text,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint programme_window check (ends_on >= starts_on),
  constraint programme_camp_shape
    check (not is_full_day or (daily_start_time is not null and daily_end_time is not null)),
  constraint programme_minors_need_ratio
    check (not admits_minors or supervision_ratio is not null)
);

create index programmes_discovery_idx on app.programmes (status, discipline, starts_on)
  where status = 'published';
create index programmes_academy_idx   on app.programmes (academy_id, starts_on desc);
create index programmes_age_idx       on app.programmes (min_age, max_age)
  where admits_minors;

create table app.programme_coaches (
  programme_id  uuid not null references app.programmes(id) on delete cascade,
  coach_id      uuid not null references app.coaches(id) on delete cascade,
  is_lead       boolean not null default false,
  primary key (programme_id, coach_id)
);

-- ---------------------------------------------------------------------
-- Enrolments. The participant is either an adult member or a child.
-- ---------------------------------------------------------------------

create table app.programme_enrolments (
  id                    uuid primary key default gen_random_uuid(),
  programme_id          uuid not null references app.programmes(id) on delete cascade,

  -- Exactly one of these. An adult enrols themselves; a guardian enrols a
  -- child and remains the paying and accountable party.
  participant_user_id   uuid references app.profiles(id) on delete cascade,
  child_profile_id      uuid references app.child_profiles(id) on delete cascade,
  paying_user_id        uuid not null references app.profiles(id) on delete restrict,

  status                app.enrolment_status not null default 'reserved',

  waiver_signature_id   uuid references app.waiver_signatures(id),
  guardian_consent_id   uuid references app.guardian_consents(id),
  medical_declaration   jsonb,
  photo_consent         boolean not null default false,

  amount_paid_aed       numeric(10,2) not null default 0,
  vat_amount_aed        numeric(10,2) not null default 0,
  coins_spent           integer not null default 0,
  coin_discount_aed     numeric(10,2) not null default 0,
  order_id              uuid references app.orders(id) on delete set null,
  instalment_plan       jsonb,

  sessions_attended     integer not null default 0,
  enrolled_at           timestamptz not null default now(),
  cancelled_at          timestamptz,
  completed_at          timestamptz,
  created_at            timestamptz not null default now(),

  constraint enrolment_one_participant
    check (num_nonnulls(participant_user_id, child_profile_id) = 1)
);

create unique index programme_enrolments_adult_idx
  on app.programme_enrolments (programme_id, participant_user_id)
  where participant_user_id is not null;
create unique index programme_enrolments_child_idx
  on app.programme_enrolments (programme_id, child_profile_id)
  where child_profile_id is not null;
create index programme_enrolments_payer_idx
  on app.programme_enrolments (paying_user_id, enrolled_at desc);

-- Per-session attendance. For a camp this is also the register that says
-- who was collected and by whom.
create table app.programme_sessions (
  id                uuid primary key default gen_random_uuid(),
  programme_id      uuid not null references app.programmes(id) on delete cascade,
  session_number    integer not null,
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  venue_id          uuid references app.venues(id) on delete set null,
  is_cancelled      boolean not null default false,
  cancellation_reason text,
  weather_snapshot  jsonb,
  heat_flag         text check (heat_flag in ('green', 'amber', 'red')),
  created_at        timestamptz not null default now(),
  unique (programme_id, session_number)
);

create table app.programme_attendance (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references app.programme_sessions(id) on delete cascade,
  enrolment_id      uuid not null references app.programme_enrolments(id) on delete cascade,
  status            app.attendance_status not null default 'going',
  checked_in_at     timestamptz,
  checked_in_by     uuid references app.profiles(id),
  -- Safeguarding: who took the child home, recorded at the gate.
  collected_at      timestamptz,
  collected_by_name text,
  collected_by_verified boolean not null default false,
  incident_note     text,
  unique (session_id, enrolment_id)
);

create index programme_attendance_session_idx on app.programme_attendance (session_id);

-- =====================================================================
-- PART C :: GATES
-- =====================================================================

-- A listing cannot go active without a verified, in-date registration
-- that passed the banned-ingredient screen, from a verified seller whose
-- own licence is current. This trigger is the authenticity claim.
create or replace function app.enforce_listing_gates()
returns trigger language plpgsql set search_path = app, public as $$
declare
  v_seller record;
  v_has_registration boolean;
  v_category app.product_category;
begin
  if new.status <> 'active' or coalesce(old.status, 'draft') = 'active' then
    return new;
  end if;

  select is_verified, is_suspended, licence_expires_at
    into v_seller
  from app.sellers where id = new.seller_id;

  if not coalesce(v_seller.is_verified, false) or v_seller.is_suspended then
    raise exception 'Listing % cannot go active: seller is not verified or is suspended', new.id
      using errcode = 'check_violation';
  end if;

  if v_seller.licence_expires_at < current_date then
    raise exception 'Listing % cannot go active: seller trade licence expired on %',
      new.id, v_seller.licence_expires_at
      using errcode = 'check_violation';
  end if;

  select category into v_category from app.products where id = new.product_id;

  -- Apparel and equipment are not regulated the way ingestibles are.
  if v_category in ('equipment', 'apparel', 'recovery_device') then
    return new;
  end if;

  select exists (
    select 1 from app.product_registrations pr
    where pr.product_id = new.product_id
      and pr.verified_at is not null
      and pr.banned_screen_status = 'passed'
      and (pr.expires_at is null or pr.expires_at >= current_date)
      and pr.authority <> 'not_required'
  ) into v_has_registration;

  if not v_has_registration then
    raise exception
      'Listing % cannot go active: product has no verified, in-date registration that passed the prohibited-substance screen',
      new.id
      using errcode = 'check_violation';
  end if;

  if new.expiry_date is not null and new.expiry_date <= current_date then
    raise exception 'Listing % cannot go active: stock expiry date has passed', new.id
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

create trigger product_listings_gate
  before insert or update on app.product_listings
  for each row execute function app.enforce_listing_gates();

-- A programme admitting minors cannot publish without the full
-- safeguarding spine in place.
create or replace function app.enforce_programme_publication_gates()
returns trigger language plpgsql set search_path = app, public as $$
declare
  v_academy record;
  v_has_insurance boolean;
  v_unvetted_coach text;
  v_coach_count integer;
begin
  if new.status <> 'published' or old.status = 'published' then
    return new;
  end if;

  select * into v_academy from app.academies where id = new.academy_id;

  if not v_academy.is_verified or v_academy.is_suspended then
    raise exception 'Programme % cannot be published: academy is not verified', new.id
      using errcode = 'check_violation';
  end if;

  if v_academy.licence_expires_at < new.ends_on then
    raise exception 'Programme % cannot be published: academy licence expires before the programme ends', new.id
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from app.insurance_certificates ic
    where ic.holder_type = 'organiser'
      and ic.holder_id = new.academy_id
      and ic.cover_type = 'public_liability'
      and ic.valid_to >= new.ends_on
      and ic.verified_at is not null
  ) into v_has_insurance;

  if not v_has_insurance then
    raise exception 'Programme % cannot be published: no verified public liability cover valid through the end date', new.id
      using errcode = 'check_violation';
  end if;

  select count(*) into v_coach_count
  from app.programme_coaches where programme_id = new.id;

  if v_coach_count = 0 then
    raise exception 'Programme % cannot be published: no coach assigned', new.id
      using errcode = 'check_violation';
  end if;

  if new.admits_minors then
    if not v_academy.accepts_minors then
      raise exception 'Programme % cannot be published: academy is not approved to work with minors', new.id
        using errcode = 'check_violation';
    end if;

    if v_academy.safeguarding_policy_url is null
       or v_academy.safeguarding_lead_name is null then
      raise exception 'Programme % cannot be published: academy has no safeguarding policy or named safeguarding lead on file', new.id
        using errcode = 'check_violation';
    end if;

    if new.supervision_ratio is null then
      raise exception 'Programme % cannot be published: supervision ratio not set', new.id
        using errcode = 'check_violation';
    end if;

    -- Every assigned coach must hold a cleared, in-date background check
    -- covering the whole programme.
    select c.full_name into v_unvetted_coach
    from app.programme_coaches pc
    join app.coaches c on c.id = pc.coach_id
    where pc.programme_id = new.id
      and (
        c.vetting_status <> 'cleared'
        or c.works_with_minors = false
        or c.vetting_expires_at is null
        or c.vetting_expires_at < new.ends_on
      )
    limit 1;

    if v_unvetted_coach is not null then
      raise exception
        'Programme % cannot be published: coach % has no cleared background check in date through the end of the programme',
        new.id, v_unvetted_coach
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end $$;

create trigger programmes_publication_gate
  before update on app.programmes
  for each row execute function app.enforce_programme_publication_gates();

-- A child enrolment needs verified guardian consent from the paying
-- account, and the child must be inside the age band.
create or replace function app.enforce_child_enrolment()
returns trigger language plpgsql set search_path = app, public as $$
declare
  v_child record;
  v_programme record;
  v_age numeric;
  v_has_consent boolean;
begin
  if new.child_profile_id is null then
    return new;
  end if;

  select * into v_child from app.child_profiles where id = new.child_profile_id;
  select * into v_programme from app.programmes where id = new.programme_id;

  if v_child.guardian_user_id <> new.paying_user_id then
    raise exception 'Enrolment refused: the paying account is not this child''s guardian'
      using errcode = 'check_violation';
  end if;

  v_age := extract(year from age(v_programme.starts_on, v_child.date_of_birth));

  if v_programme.min_age is not null and v_age < v_programme.min_age then
    raise exception 'Enrolment refused: child is below the minimum age of % for this programme',
      v_programme.min_age using errcode = 'check_violation';
  end if;
  if v_programme.max_age is not null and v_age > v_programme.max_age then
    raise exception 'Enrolment refused: child is above the maximum age of % for this programme',
      v_programme.max_age using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from app.guardian_consents gc
    where gc.guardian_user_id = new.paying_user_id
      and gc.revoked_at is null
      and gc.verified_at is not null
      and (gc.expires_at is null or gc.expires_at > now())
  ) into v_has_consent;

  if not v_has_consent and new.guardian_consent_id is null then
    raise exception 'Enrolment refused: no verified guardian consent on file'
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

create trigger programme_enrolments_child_gate
  before insert on app.programme_enrolments
  for each row execute function app.enforce_child_enrolment();

-- Daily: suspend listings whose registration or stock has expired.
create or replace function app.sweep_expired_listings()
returns integer language plpgsql set search_path = app, public as $$
declare v_count integer;
begin
  update app.product_listings l
  set status = 'registration_expired'
  where l.status = 'active'
    and (
      (l.expiry_date is not null and l.expiry_date <= current_date)
      or exists (
        select 1 from app.sellers s
        where s.id = l.seller_id and s.licence_expires_at < current_date
      )
      or not exists (
        select 1 from app.product_registrations pr
        where pr.product_id = l.product_id
          and pr.verified_at is not null
          and pr.banned_screen_status = 'passed'
          and (pr.expires_at is null or pr.expires_at >= current_date)
      )
    );
  get diagnostics v_count = row_count;

  insert into app.audit_log (action, subject_type, after_state)
  values ('marketplace.listing_expiry_sweep', 'system',
          jsonb_build_object('suspended_count', v_count));
  return v_count;
end $$;

-- =====================================================================
-- PART D :: RLS
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'sellers','products','product_registrations','product_listings',
    'marketplace_orders','marketplace_order_lines','seller_payouts',
    'academies','coaches','child_profiles','programmes','programme_coaches',
    'programme_enrolments','programme_sessions','programme_attendance'
  ] loop
    execute format('alter table app.%I enable row level security', t);
  end loop;
end $$;

create policy sellers_public_read on app.sellers
  for select using (is_verified and not is_suspended);
create policy sellers_owner on app.sellers
  for all using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());

create policy products_public_read on app.products for select using (true);

-- Registration numbers are shown publicly. That visibility is the point:
-- a member can check the number against the regulator rather than take
-- the platform's word for it. Certificate URLs stay internal.
create or replace view app.product_registrations_public
with (security_invoker = true) as
select product_id, authority, registration_number, issued_at, expires_at, verified_at
from app.product_registrations
where verified_at is not null and banned_screen_status = 'passed';

grant select on app.product_registrations_public to authenticated, anon;

create policy product_registrations_internal on app.product_registrations
  for select using (
    app.is_platform_admin()
    or exists (
      select 1 from app.products p
      join app.sellers s on s.id = p.created_by_seller_id
      where p.id = product_id and s.owner_user_id = auth.uid()
    )
  );

create policy product_listings_public_read on app.product_listings
  for select using (status = 'active' or exists (
    select 1 from app.sellers s where s.id = seller_id and s.owner_user_id = auth.uid()
  ));
create policy product_listings_seller_write on app.product_listings
  for all using (
    exists (select 1 from app.sellers s where s.id = seller_id and s.owner_user_id = auth.uid())
  ) with check (
    exists (select 1 from app.sellers s where s.id = seller_id and s.owner_user_id = auth.uid())
  );

-- Orders carry delivery addresses. Buyer and seller only.
create policy marketplace_orders_parties on app.marketplace_orders
  for select using (
    user_id = auth.uid()
    or exists (select 1 from app.sellers s where s.id = seller_id and s.owner_user_id = auth.uid())
    or app.is_platform_admin()
  );

create policy marketplace_order_lines_parties on app.marketplace_order_lines
  for select using (
    exists (
      select 1 from app.marketplace_orders o
      where o.id = order_id
        and (o.user_id = auth.uid()
             or exists (select 1 from app.sellers s
                        where s.id = o.seller_id and s.owner_user_id = auth.uid()))
    )
  );

create policy seller_payouts_owner on app.seller_payouts
  for select using (
    exists (select 1 from app.sellers s where s.id = seller_id and s.owner_user_id = auth.uid())
    or app.is_platform_admin()
  );

create policy academies_public_read on app.academies
  for select using (is_verified and not is_suspended);
create policy academies_owner on app.academies
  for all using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());

-- Coach vetting status is not public. The public view exposes the fact of
-- clearance, never the provider, reference or dates.
create or replace view app.coaches_public
with (security_invoker = true) as
select
  id, academy_id, full_name, disciplines, bio_en, bio_ar, photo_url, languages,
  (vetting_status = 'cleared') as is_background_checked
from app.coaches
where is_active;

grant select on app.coaches_public to authenticated, anon;

create policy coaches_internal on app.coaches
  for select using (
    app.is_platform_admin()
    or user_id = auth.uid()
    or exists (select 1 from app.academies a
               where a.id = academy_id and a.owner_user_id = auth.uid())
  );

-- Child records are visible to the guardian alone. No academy-wide read:
-- staff see the session register through a restricted server route, not
-- through a policy that would let them enumerate every child.
create policy child_profiles_guardian on app.child_profiles
  for all using (guardian_user_id = auth.uid())
  with check (guardian_user_id = auth.uid());

create policy programmes_public_read on app.programmes
  for select using (
    status in ('published', 'sold_out', 'in_progress', 'completed')
    or exists (select 1 from app.academies a
               where a.id = academy_id and a.owner_user_id = auth.uid())
  );
create policy programmes_academy_write on app.programmes
  for all using (
    exists (select 1 from app.academies a
            where a.id = academy_id and a.owner_user_id = auth.uid())
  ) with check (
    exists (select 1 from app.academies a
            where a.id = academy_id and a.owner_user_id = auth.uid())
  );

create policy programme_coaches_read on app.programme_coaches for select using (true);
create policy programme_sessions_read on app.programme_sessions for select using (true);

create policy programme_enrolments_payer on app.programme_enrolments
  for select using (
    paying_user_id = auth.uid()
    or participant_user_id = auth.uid()
    or app.is_platform_admin()
  );

create policy programme_attendance_payer on app.programme_attendance
  for select using (
    exists (select 1 from app.programme_enrolments e
            where e.id = enrolment_id and e.paying_user_id = auth.uid())
    or app.is_platform_admin()
  );

grant select on app.products, app.product_listings, app.sellers,
                app.academies, app.programmes to authenticated, anon;
grant insert, update on app.child_profiles to authenticated;
