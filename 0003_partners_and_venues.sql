-- =====================================================================
-- NABD :: 0003 :: Partners, venues and supply-protection controls
-- ---------------------------------------------------------------------
-- The caps, blackouts and kill switch in this file are the reason a gym
-- owner signs and stays. An aggregator that floods a partner's 7pm slot
-- loses the partner, and losing partners is how the product dies.
-- =====================================================================

create table app.partners (
  id                    uuid primary key default gen_random_uuid(),
  legal_name            text not null,
  trading_name          text not null,
  trading_name_ar       text,

  -- UAE commercial identifiers.
  trade_licence_number  text,
  licence_authority     text,                 -- 'DED Dubai', 'DMCC', 'ADGM', ...
  licence_expires_at    date,
  trn                   text check (trn ~ '^[0-9]{15}$'),   -- 15-digit UAE VAT TRN
  is_vat_registered     boolean not null default false,

  primary_contact_name  text,
  primary_contact_email citext,
  primary_contact_phone text,

  -- Commercials. Either a per-visit rate or a revenue share, not both.
  revenue_share_pct     numeric(5,2) check (revenue_share_pct between 0 and 100),
  per_visit_rate_aed    numeric(8,2) check (per_visit_rate_aed >= 0),
  per_class_rate_aed    numeric(8,2) check (per_class_rate_aed >= 0),
  payout_currency       char(3) not null default 'AED',
  payout_iban           text,
  payout_bank_name      text,
  payout_frequency      text not null default 'monthly'
                        check (payout_frequency in ('weekly', 'biweekly', 'monthly')),

  contract_signed_at    date,
  contract_ends_at      date,

  is_active             boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint partners_one_pricing_model
    check (num_nonnulls(revenue_share_pct, per_visit_rate_aed) >= 1)
);

create index partners_active_idx on app.partners (is_active);
create index partners_licence_expiry_idx on app.partners (licence_expires_at)
  where is_active;

-- ---------------------------------------------------------------------
-- Venues
-- ---------------------------------------------------------------------

create table app.venues (
  id                  uuid primary key default gen_random_uuid(),
  partner_id          uuid not null references app.partners(id) on delete restrict,

  slug                citext not null unique,
  name_en             text not null,
  name_ar             text,
  description_en      text,
  description_ar      text,

  venue_type          app.venue_type not null,
  disciplines         app.discipline[] not null default '{}',
  status              app.venue_status not null default 'draft',

  -- Location
  emirate             app.emirate not null,
  area                text not null,            -- 'Dubai Marina', 'Al Reem Island'
  address_line        text,
  google_place_id     text,
  location            geography(Point, 4326) not null,
  -- Check-in geofence. 150m default covers a mall-based gym where GPS is poor.
  geofence_radius_m   integer not null default 150 check (geofence_radius_m between 25 and 1000),

  -- Access policy
  gender_policy       app.gender_policy not null default 'mixed',
  min_age             integer check (min_age between 0 and 99),
  tier_required       app.tier_code not null default 'core',
  -- Credit cost of a single check-in. Zero for standard Core supply; used to
  -- price expensive supply (hotel gyms, peak boutique) without breaking the
  -- flat bundle. This is the margin-protection lever.
  checkin_credit_cost integer not null default 0 check (checkin_credit_cost >= 0),
  -- Internal cost per visit, used for unit-economics reporting. Never exposed.
  cost_per_visit_aed  numeric(8,2),

  amenities           jsonb not null default '{}'::jsonb,
  -- { showers, lockers, parking, prayer_room, women_only_floor, pool,
  --   sauna, towel_service, creche, wheelchair_access, padel_courts: 4 }

  photos              text[] not null default '{}',
  phone_e164          text,
  -- [{ dow: 0..6, open: '06:00', close: '23:00' }]
  opening_hours       jsonb not null default '[]'::jsonb,

  -- Sports establishment licensing. Expiry suspends new bookings.
  sports_permit_number text,
  sports_permit_expires_at date,

  -- The partner's own kill switch. Flipping this stops all aggregator
  -- check-ins immediately, without contacting us. Trust mechanism.
  aggregator_access_paused boolean not null default false,
  paused_reason       text,
  paused_at           timestamptz,

  rating_avg          numeric(3,2) check (rating_avg between 0 and 5),
  rating_count        integer not null default 0,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index venues_location_idx     on app.venues using gist (location);
create index venues_emirate_idx      on app.venues (emirate, status);
create index venues_type_idx         on app.venues (venue_type);
create index venues_tier_idx         on app.venues (tier_required);
create index venues_disciplines_idx  on app.venues using gin (disciplines);
create index venues_amenities_idx    on app.venues using gin (amenities);
create index venues_partner_idx      on app.venues (partner_id);
-- Covers the primary discovery query: active venues near me in my emirate.
create index venues_discovery_idx    on app.venues (status, emirate, tier_required)
  where status = 'active';

comment on column app.venues.checkin_credit_cost is
  'Prices expensive supply inside a flat subscription. Unlimited access to premium venues is the fastest route to negative contribution margin.';

-- ---------------------------------------------------------------------
-- Ladies-hours windows, for venues with gender_policy = 'ladies_hours'
-- ---------------------------------------------------------------------

create table app.venue_gender_windows (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references app.venues(id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),  -- 0 = Sunday (UAE week)
  start_time  time not null,
  end_time    time not null,
  policy      app.gender_policy not null,
  created_at  timestamptz not null default now(),
  check (end_time > start_time)
);

create index venue_gender_windows_lookup_idx
  on app.venue_gender_windows (venue_id, day_of_week);

-- ---------------------------------------------------------------------
-- Supply protection: caps
-- ---------------------------------------------------------------------

create table app.venue_caps (
  venue_id                    uuid primary key references app.venues(id) on delete cascade,
  -- Total aggregator check-ins accepted per calendar day.
  max_daily_checkins          integer check (max_daily_checkins > 0),
  -- Aggregator members simultaneously inside (requires check-out or TTL).
  max_concurrent              integer check (max_concurrent > 0),
  -- The cap that makes gyms comfortable: stops us substituting for a direct
  -- membership. Overrides the tier default.
  max_visits_per_user_monthly integer check (max_visits_per_user_monthly > 0),
  -- Minimum gap between two check-ins by the same member at this venue.
  cooldown_minutes            integer not null default 240 check (cooldown_minutes >= 0),
  updated_at                  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Supply protection: blackout windows (peak-hour exclusion)
-- ---------------------------------------------------------------------

create table app.venue_blackouts (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references app.venues(id) on delete cascade,
  -- Null day_of_week = a one-off date range (public holiday, refurbishment).
  day_of_week smallint check (day_of_week between 0 and 6),
  start_time  time,
  end_time    time,
  starts_on   date,
  ends_on     date,
  reason      text,
  created_at  timestamptz not null default now(),
  constraint blackout_shape check (
    (day_of_week is not null and start_time is not null and end_time is not null)
    or (starts_on is not null and ends_on is not null)
  )
);

create index venue_blackouts_lookup_idx on app.venue_blackouts (venue_id, day_of_week);

-- ---------------------------------------------------------------------
-- Per-venue HMAC secret backing the rotating check-in QR.
-- ---------------------------------------------------------------------
-- Never leaves the server except to an authenticated reception session.
-- Rotated on demand and on staff offboarding.
-- ---------------------------------------------------------------------

create table app.venue_signing_keys (
  venue_id      uuid primary key references app.venues(id) on delete cascade,
  secret        bytea not null default gen_random_bytes(32),
  -- Previous secret retained briefly so an in-flight tablet does not break
  -- mid-rotation.
  previous_secret bytea,
  rotated_at    timestamptz not null default now(),
  window_seconds integer not null default 30 check (window_seconds between 15 and 300)
);

-- ---------------------------------------------------------------------
-- Staff accounts for the reception app
-- ---------------------------------------------------------------------

create table app.venue_staff (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references app.venues(id) on delete cascade,
  user_id     uuid not null references app.profiles(id) on delete cascade,
  role        text not null default 'reception'
              check (role in ('reception', 'manager', 'owner')),
  can_override boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (venue_id, user_id)
);

-- ---------------------------------------------------------------------
-- Scheduled classes (real inventory, real capacity)
-- ---------------------------------------------------------------------

create table app.classes (
  id               uuid primary key default gen_random_uuid(),
  venue_id         uuid not null references app.venues(id) on delete cascade,
  title_en         text not null,
  title_ar         text,
  discipline       app.discipline not null,
  instructor_name  text,
  description_en   text,
  description_ar   text,

  starts_at        timestamptz not null,
  duration_minutes integer not null check (duration_minutes between 10 and 300),

  capacity         integer not null check (capacity > 0),
  booked_count     integer not null default 0 check (booked_count >= 0),
  waitlist_count   integer not null default 0 check (waitlist_count >= 0),

  gender_policy    app.gender_policy not null default 'mixed',
  min_age          integer,
  tier_required    app.tier_code not null default 'core',
  credit_cost      integer not null default 0 check (credit_cost >= 0),
  -- Cancelling inside this window burns the credits and counts as a late cancel.
  cancellation_cutoff_minutes integer not null default 720,
  is_cancelled     boolean not null default false,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint classes_capacity_not_exceeded check (booked_count <= capacity)
);

create index classes_venue_time_idx  on app.classes (venue_id, starts_at);
create index classes_upcoming_idx    on app.classes (starts_at)
  where not is_cancelled;
create index classes_discipline_idx  on app.classes (discipline, starts_at);

-- ---------------------------------------------------------------------
-- Bookable court slots (padel, tennis). Distinct from classes: an
-- instructor-led class sells seats, a court sells the whole surface.
-- ---------------------------------------------------------------------

create table app.court_slots (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references app.venues(id) on delete cascade,
  court_label   text not null,                -- 'Court 3'
  discipline    app.discipline not null default 'padel',
  is_indoor     boolean not null default false,
  starts_at     timestamptz not null,
  duration_minutes integer not null default 60,
  -- Credit price rather than cash: peak Dubai padel at roughly AED 247/hour
  -- must cost meaningfully more credits than an off-peak slot.
  credit_cost   integer not null check (credit_cost >= 0),
  cash_price_aed numeric(8,2),
  is_peak       boolean not null default false,
  status        text not null default 'available'
                check (status in ('available', 'held', 'booked', 'blocked')),
  held_until    timestamptz,
  created_at    timestamptz not null default now(),
  unique (venue_id, court_label, starts_at)
);

create index court_slots_lookup_idx on app.court_slots (venue_id, starts_at, status);
create index court_slots_open_idx   on app.court_slots (discipline, starts_at)
  where status = 'available';
