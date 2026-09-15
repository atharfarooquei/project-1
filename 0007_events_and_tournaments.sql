-- =====================================================================
-- NABD :: 0007 :: Ticketed events, organisers, tournaments and results
-- ---------------------------------------------------------------------
-- The moment you put sixty people on a road at 5am, you are an event
-- organiser with regulatory obligations. The permit, waiver and insurance
-- gates below are enforced by trigger in 0010, not by convention.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Organisers. Anyone may run a free club. Ticketing requires verification.
-- ---------------------------------------------------------------------

create table app.organisers (
  id                  uuid primary key default gen_random_uuid(),
  owner_user_id       uuid not null references app.profiles(id) on delete restrict,
  club_id             uuid references app.clubs(id) on delete set null,

  display_name        text not null,
  display_name_ar     text,
  legal_name          text,
  trade_licence_number text,
  licence_expires_at  date,
  trn                 text check (trn ~ '^[0-9]{15}$'),

  contact_email       citext not null,
  contact_phone       text not null,

  -- Verification gates ticketing. Requires licence plus a current public
  -- liability certificate.
  is_verified         boolean not null default false,
  verified_at         timestamptz,
  verified_by         uuid references app.profiles(id),

  -- Platform fee on ticket sales, per organiser contract.
  platform_fee_pct    numeric(5,2) not null default 10.00,
  payout_iban         text,

  is_suspended        boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index organisers_verified_idx on app.organisers (is_verified) where not is_suspended;

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

create table app.events (
  id                  uuid primary key default gen_random_uuid(),
  organiser_id        uuid not null references app.organisers(id) on delete restrict,
  club_id             uuid references app.clubs(id) on delete set null,

  slug                citext not null unique,
  title_en            text not null,
  title_ar            text,
  description_en      text,
  description_ar      text,

  event_type          app.event_type not null,
  discipline          app.discipline not null,
  status              app.event_status not null default 'draft',

  starts_at           timestamptz not null,
  ends_at             timestamptz not null,
  registration_opens_at timestamptz,
  registration_closes_at timestamptz,

  -- Either at a partner venue or at a free-text location (a desert route,
  -- a corniche, a park).
  venue_id            uuid references app.venues(id) on delete set null,
  location_name_en    text,
  location_name_ar    text,
  location            geography(Point, 4326),
  emirate             app.emirate not null,

  capacity            integer check (capacity > 0),
  registered_count    integer not null default 0,

  gender_policy       app.gender_policy not null default 'mixed',
  min_age             integer,
  max_age             integer,

  cover_image_url     text,
  is_outdoor          boolean not null default true,
  heat_policy         text not null default 'advise'
                      check (heat_policy in ('none', 'advise', 'auto_cancel')),

  -- Compliance gates. Checked by trigger before status may become 'published'.
  requires_permit     boolean not null default true,
  requires_waiver     boolean not null default true,
  waiver_id           uuid references app.waivers(id),
  requires_medical_declaration boolean not null default false,

  refund_policy_en    text,
  refund_policy_ar    text,
  -- Agent vs principal changes VAT treatment and revenue recognition on
  -- every ticket. Recorded per event, never assumed.
  supply_role         app.supply_role not null default 'agent',

  cancelled_at        timestamptz,
  cancellation_reason text,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint events_window check (ends_at >= starts_at)
);

create index events_discovery_idx  on app.events (status, emirate, starts_at)
  where status in ('published', 'sold_out');
create index events_discipline_idx on app.events (discipline, starts_at);
create index events_organiser_idx  on app.events (organiser_id, starts_at desc);
create index events_location_idx   on app.events using gist (location);

-- ---------------------------------------------------------------------
-- Ticket types
-- ---------------------------------------------------------------------

create table app.event_ticket_types (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references app.events(id) on delete cascade,
  name_en         text not null,          -- '10K', 'Early Bird', 'Team of 4'
  name_ar         text,
  description_en  text,

  price_aed       numeric(10,2) not null check (price_aed >= 0),
  vat_rate_pct    numeric(5,2) not null default 5.00,
  -- Members may pay in credits instead of cash. Null = cash only.
  credit_price    integer check (credit_price >= 0),
  -- Tier-gated pricing: Elite members may see a discounted or free type.
  tier_required   app.tier_code,

  quantity_total  integer check (quantity_total > 0),
  quantity_sold   integer not null default 0,
  max_per_user    integer not null default 1,

  sales_start_at  timestamptz,
  sales_end_at    timestamptz,

  -- Race logistics.
  wave_label      text,
  distance_km     numeric(6,2),
  -- Team ticket: how many participants one purchase covers.
  team_size       integer not null default 1 check (team_size >= 1),

  min_age         integer,
  gender_policy   app.gender_policy,
  sort_order      integer not null default 0,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  constraint ticket_quantity_not_exceeded
    check (quantity_total is null or quantity_sold <= quantity_total)
);

create index event_ticket_types_event_idx on app.event_ticket_types (event_id, sort_order);

-- ---------------------------------------------------------------------
-- Registrations
-- ---------------------------------------------------------------------

create table app.event_registrations (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references app.events(id) on delete cascade,
  ticket_type_id  uuid not null references app.event_ticket_types(id) on delete restrict,
  user_id         uuid not null references app.profiles(id) on delete cascade,

  status          app.registration_status not null default 'reserved',

  -- Compliance evidence. A participant with a null waiver signature on an
  -- event that requires one cannot be checked in.
  waiver_signature_id uuid references app.waiver_signatures(id),
  guardian_consent_id uuid references app.guardian_consents(id),
  medical_declaration jsonb,

  bib_number      text,
  wave_label      text,
  team_name       text,
  category        text,               -- 'M35-39', 'F Open'

  amount_paid_aed numeric(10,2) not null default 0,
  vat_amount_aed  numeric(10,2) not null default 0,
  credits_charged integer not null default 0,
  order_id        uuid,

  registered_at   timestamptz not null default now(),
  cancelled_at    timestamptz,
  checked_in_at   timestamptz,
  -- Transfers are common in this market; entries get resold informally.
  transferred_to  uuid references app.profiles(id),
  transferred_at  timestamptz,

  created_at      timestamptz not null default now(),
  unique (event_id, user_id, ticket_type_id)
);

create index event_registrations_event_idx on app.event_registrations (event_id, status);
create index event_registrations_user_idx  on app.event_registrations (user_id, registered_at desc);
create unique index event_registrations_bib_idx
  on app.event_registrations (event_id, bib_number) where bib_number is not null;

-- ---------------------------------------------------------------------
-- Results
-- ---------------------------------------------------------------------

create table app.event_results (
  id                uuid primary key default gen_random_uuid(),
  registration_id   uuid not null references app.event_registrations(id) on delete cascade,
  event_id          uuid not null references app.events(id) on delete cascade,
  user_id           uuid not null references app.profiles(id) on delete cascade,
  gun_time_seconds  integer,
  chip_time_seconds integer,
  overall_position  integer,
  gender_position   integer,
  category_position integer,
  splits            jsonb not null default '[]'::jsonb,
  status            text not null default 'finished'
                    check (status in ('finished', 'dnf', 'dns', 'dq')),
  published_at      timestamptz,
  created_at        timestamptz not null default now(),
  unique (registration_id)
);

create index event_results_event_idx on app.event_results (event_id, overall_position);
create index event_results_user_idx  on app.event_results (user_id, created_at desc);

-- ---------------------------------------------------------------------
-- Tournaments
-- ---------------------------------------------------------------------
-- Americano and Mexicano are included because they, not knockout brackets,
-- are what UAE padel clubs actually run socially. A tournament that runs
-- itself is the strongest venue-acquisition tool available: the venue gets
-- court revenue and footfall, we get the relationship.
-- ---------------------------------------------------------------------

create table app.tournaments (
  id                uuid primary key default gen_random_uuid(),
  event_id          uuid not null references app.events(id) on delete cascade,
  format            app.tournament_format not null,
  discipline        app.discipline not null default 'padel',

  team_size         integer not null default 2 check (team_size between 1 and 11),
  max_teams         integer check (max_teams > 0),

  -- Americano/Mexicano: number of rounds and points played to per round.
  rounds_total      integer,
  points_per_round  integer,
  -- Knockout: seeding source.
  seeding_method    text not null default 'rating'
                    check (seeding_method in ('rating', 'random', 'manual', 'group_finish')),

  courts_available  integer not null default 1 check (courts_available > 0),
  court_labels      text[] not null default '{}',
  match_duration_minutes integer not null default 45,

  -- Rating band for entry.
  min_rating        numeric(4,2),
  max_rating        numeric(4,2),
  gender_policy     app.gender_policy not null default 'mixed',

  status            text not null default 'draft'
                    check (status in ('draft', 'registration_open', 'seeded',
                                      'in_progress', 'completed', 'cancelled')),
  bracket_generated_at timestamptz,
  created_at        timestamptz not null default now(),
  unique (event_id)
);

create table app.tournament_teams (
  id              uuid primary key default gen_random_uuid(),
  tournament_id   uuid not null references app.tournaments(id) on delete cascade,
  name            text not null,
  captain_id      uuid not null references app.profiles(id) on delete cascade,
  seed            integer,
  -- Average rating of members at seeding time, frozen.
  rating_avg      numeric(6,2),
  group_label     text,
  -- Round robin / group standings.
  played          integer not null default 0,
  won             integer not null default 0,
  lost            integer not null default 0,
  points_for      integer not null default 0,
  points_against  integer not null default 0,
  standing_points integer not null default 0,
  final_position  integer,
  created_at      timestamptz not null default now(),
  unique (tournament_id, name)
);

create index tournament_teams_standings_idx
  on app.tournament_teams (tournament_id, standing_points desc, points_for desc);

create table app.tournament_team_members (
  team_id       uuid not null references app.tournament_teams(id) on delete cascade,
  user_id       uuid not null references app.profiles(id) on delete cascade,
  registration_id uuid references app.event_registrations(id) on delete set null,
  is_captain    boolean not null default false,
  -- Americano/Mexicano score individually despite playing in rotating pairs.
  individual_points integer not null default 0,
  joined_at     timestamptz not null default now(),
  primary key (team_id, user_id)
);

create table app.tournament_matches (
  id              uuid primary key default gen_random_uuid(),
  tournament_id   uuid not null references app.tournaments(id) on delete cascade,

  round_number    integer not null,
  round_label     text,                  -- 'Group A R1', 'Quarter-final', 'Round 3'
  bracket_position integer,
  group_label     text,

  team_a_id       uuid references app.tournament_teams(id) on delete set null,
  team_b_id       uuid references app.tournament_teams(id) on delete set null,
  -- Americano/Mexicano rotate partners each round, so pairings are recorded
  -- per match rather than as fixed teams.
  team_a_players  uuid[] not null default '{}',
  team_b_players  uuid[] not null default '{}',

  court_label     text,
  scheduled_at    timestamptz,
  started_at      timestamptz,
  completed_at    timestamptz,

  -- [{ set: 1, a: 6, b: 4 }] for set-based; [{ a: 21, b: 17 }] for Americano.
  score           jsonb not null default '[]'::jsonb,
  score_a_total   integer,
  score_b_total   integer,
  winner_team_id  uuid references app.tournament_teams(id) on delete set null,

  status          app.match_status not null default 'scheduled',
  -- Whichever captain reported; the other may dispute.
  reported_by     uuid references app.profiles(id),
  confirmed_by    uuid references app.profiles(id),
  disputed        boolean not null default false,

  -- Knockout progression pointers.
  next_match_id   uuid references app.tournament_matches(id) on delete set null,
  next_match_slot smallint check (next_match_slot in (1, 2)),

  created_at      timestamptz not null default now()
);

create index tournament_matches_tournament_idx
  on app.tournament_matches (tournament_id, round_number, bracket_position);
create index tournament_matches_schedule_idx
  on app.tournament_matches (tournament_id, court_label, scheduled_at);

-- Court scheduling conflict guard: one match per court at a time.
alter table app.tournament_matches
  add constraint tournament_matches_no_court_clash
  exclude using gist (
    tournament_id with =,
    court_label with =,
    tstzrange(scheduled_at, scheduled_at + interval '45 minutes') with &&
  ) where (scheduled_at is not null and court_label is not null
           and status <> 'cancelled');
