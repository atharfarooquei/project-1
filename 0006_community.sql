-- =====================================================================
-- NABD :: 0006 :: Clubs, meets, open matches, ratings, challenges
-- ---------------------------------------------------------------------
-- This is the wedge. The real incumbent here is a WhatsApp group, and the
-- only way to beat one is to do the things it cannot: discovery, pace
-- matching, waivers, heat safety, results and memory.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Clubs
-- ---------------------------------------------------------------------

create table app.clubs (
  id              uuid primary key default gen_random_uuid(),
  slug            citext not null unique,
  name_en         text not null,
  name_ar         text,
  description_en  text,
  description_ar  text,

  primary_discipline app.discipline not null,
  disciplines     app.discipline[] not null default '{}',

  emirate         app.emirate not null,
  area            text,
  -- Typical meeting area, for discovery. Individual meets carry their own point.
  base_location   geography(Point, 4326),

  owner_id        uuid not null references app.profiles(id) on delete restrict,
  visibility      app.club_visibility not null default 'public',
  gender_policy   app.gender_policy not null default 'mixed',
  min_age         integer,

  cover_image_url text,
  logo_url        text,
  instagram       text,
  whatsapp_invite text,

  -- Verified clubs are established groups we have confirmed exist and have
  -- a responsible organiser. Verification is what allows ticketed events.
  is_verified     boolean not null default false,
  verified_at     timestamptz,

  member_count    integer not null default 0,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index clubs_discipline_idx on app.clubs (primary_discipline, emirate);
create index clubs_location_idx   on app.clubs using gist (base_location);
create index clubs_active_idx     on app.clubs (is_active, emirate);

create table app.club_members (
  club_id     uuid not null references app.clubs(id) on delete cascade,
  user_id     uuid not null references app.profiles(id) on delete cascade,
  role        app.club_role not null default 'member',
  joined_at   timestamptz not null default now(),
  -- Pending state for request_to_join clubs.
  approved_at timestamptz,
  left_at     timestamptz,
  primary key (club_id, user_id)
);

create index club_members_user_idx on app.club_members (user_id) where left_at is null;

-- ---------------------------------------------------------------------
-- Meets. Recurring by rule, not by duplicated rows.
-- ---------------------------------------------------------------------
-- A Tuesday 6am run at Kite Beach is one meet with occurrences, not 52
-- event records. Attendance attaches to (meet_id, occurrence_date).
-- ---------------------------------------------------------------------

create table app.meets (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid references app.clubs(id) on delete cascade,
  -- Meets can also be standalone, hosted by an individual.
  host_id         uuid not null references app.profiles(id) on delete cascade,

  title_en        text not null,
  title_ar        text,
  description_en  text,
  description_ar  text,
  discipline      app.discipline not null,

  -- Schedule. rrule is an iCalendar RRULE string; null means one-off.
  first_starts_at timestamptz not null,
  duration_minutes integer not null default 60,
  rrule           text,
  timezone        text not null default 'Asia/Dubai',
  series_ends_on  date,

  -- Meeting point. The landmark matters more than the coordinates at 5am
  -- in an unlit car park.
  meeting_point   geography(Point, 4326) not null,
  meeting_landmark_en text not null,
  meeting_landmark_ar text,
  emirate         app.emirate not null,

  -- Running: structured pace groups so a beginner can see they will not be
  -- abandoned. [{ label: '5:30/km', pace_sec_per_km: 330, leader_id, capacity }]
  pace_groups     jsonb not null default '[]'::jsonb,
  -- Cycling: speed bands and drop policy.
  avg_speed_kmh_min numeric(4,1),
  avg_speed_kmh_max numeric(4,1),
  ride_style      app.ride_style,
  has_mechanical_support boolean not null default false,

  distance_km     numeric(6,2),
  elevation_gain_m integer,
  route_gpx_url   text,
  -- UAE loop taxonomy: 'al_qudra', 'nad_al_sheba', 'hudayriyat', 'al_wathba'.
  route_name      text,

  capacity        integer check (capacity > 0),
  gender_policy   app.gender_policy not null default 'mixed',
  min_age         integer,
  is_free         boolean not null default true,
  credit_cost     integer not null default 0,

  is_outdoor      boolean not null default true,
  -- Heat policy for outdoor meets, May to September. Above the threshold the
  -- meet is flagged, attendees are notified and indoor alternatives surface.
  -- 'advise' warns, 'auto_cancel' cancels the occurrence.
  heat_policy     text not null default 'advise'
                  check (heat_policy in ('none', 'advise', 'auto_cancel')),
  heat_threshold_c numeric(4,1) not null default 40.0,

  requires_waiver boolean not null default false,
  waiver_id       uuid references app.waivers(id),

  is_cancelled    boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index meets_club_idx       on app.meets (club_id, first_starts_at);
create index meets_point_idx      on app.meets using gist (meeting_point);
create index meets_discipline_idx on app.meets (discipline, emirate, first_starts_at);
create index meets_upcoming_idx   on app.meets (first_starts_at) where not is_cancelled;

-- Materialised occurrences of a recurring meet. Generated ahead by a
-- scheduled job so attendance, capacity and cancellation attach per date.
create table app.meet_occurrences (
  id              uuid primary key default gen_random_uuid(),
  meet_id         uuid not null references app.meets(id) on delete cascade,
  starts_at       timestamptz not null,
  is_cancelled    boolean not null default false,
  cancellation_reason text,
  -- Weather snapshot at decision time. Evidence that the safety call was
  -- made on data, which matters if an incident is ever litigated.
  weather_snapshot jsonb,
  heat_flag       text check (heat_flag in ('green', 'amber', 'red')),
  attendee_count  integer not null default 0,
  created_at      timestamptz not null default now(),
  unique (meet_id, starts_at)
);

create index meet_occurrences_time_idx on app.meet_occurrences (starts_at)
  where not is_cancelled;

create table app.meet_attendance (
  id              uuid primary key default gen_random_uuid(),
  occurrence_id   uuid not null references app.meet_occurrences(id) on delete cascade,
  user_id         uuid not null references app.profiles(id) on delete cascade,
  status          app.attendance_status not null default 'going',
  -- Which pace group or speed band they picked.
  pace_group_label text,
  waitlist_position integer,
  registered_at   timestamptz not null default now(),
  checked_in_at   timestamptz,
  cancelled_at    timestamptz,
  waiver_signature_id uuid references app.waiver_signatures(id),
  unique (occurrence_id, user_id)
);

create index meet_attendance_user_idx on app.meet_attendance (user_id, registered_at desc);

-- ---------------------------------------------------------------------
-- Open matches. The highest-frequency object in the product.
-- ---------------------------------------------------------------------
-- "Three confirmed, need a fourth, Saturday 8am, level 3.5." This is the
-- reason someone opens the app daily, and it is the object Playtomic owns
-- today for padel and nobody owns for anything else.
-- ---------------------------------------------------------------------

create table app.open_matches (
  id              uuid primary key default gen_random_uuid(),
  created_by      uuid not null references app.profiles(id) on delete cascade,
  discipline      app.discipline not null default 'padel',

  venue_id        uuid references app.venues(id) on delete set null,
  court_slot_id   uuid references app.court_slots(id) on delete set null,
  -- For matches at venues we do not aggregate.
  external_venue_name text,
  location        geography(Point, 4326),
  emirate         app.emirate not null,

  starts_at       timestamptz not null,
  duration_minutes integer not null default 90,

  total_slots     integer not null check (total_slots between 2 and 22),
  filled_slots    integer not null default 1 check (filled_slots >= 0),

  -- Rating gate. A 3.0 player dropped into a 4.5 game does not come back,
  -- so the band is enforced on join, not merely displayed.
  min_rating      numeric(4,2),
  max_rating      numeric(4,2),
  gender_policy   app.gender_policy not null default 'mixed',

  credit_cost_per_player integer not null default 0,
  cash_cost_per_player_aed numeric(8,2),

  -- If unfilled by this time, auto-cancel and refund every joined player.
  fill_deadline   timestamptz,
  status          text not null default 'open'
                  check (status in ('open', 'full', 'confirmed', 'cancelled', 'completed')),
  notes           text,
  created_at      timestamptz not null default now(),
  constraint open_matches_slots check (filled_slots <= total_slots)
);

create index open_matches_discovery_idx on app.open_matches (discipline, emirate, starts_at)
  where status = 'open';
create index open_matches_location_idx  on app.open_matches using gist (location);

create table app.open_match_players (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references app.open_matches(id) on delete cascade,
  user_id       uuid not null references app.profiles(id) on delete cascade,
  team          smallint check (team in (1, 2)),
  status        text not null default 'joined'
                check (status in ('joined', 'cancelled', 'no_show', 'played')),
  rating_at_join numeric(4,2),
  credits_charged integer not null default 0,
  joined_at     timestamptz not null default now(),
  unique (match_id, user_id)
);

alter table app.court_bookings
  add constraint court_bookings_open_match_fk
  foreign key (open_match_id) references app.open_matches(id) on delete set null;

-- ---------------------------------------------------------------------
-- Player ratings. Elo-style, per discipline.
-- ---------------------------------------------------------------------
-- Ratings are what make open matches work at all. Seeded by self-assessment,
-- corrected by results, and used to seed tournaments and ladders.
-- ---------------------------------------------------------------------

create table app.player_ratings (
  user_id         uuid not null references app.profiles(id) on delete cascade,
  discipline      app.discipline not null,
  -- Padel convention is a 1.0 to 7.0 scale; stored as an Elo-like number and
  -- presented on the familiar scale.
  rating          numeric(6,2) not null default 1500,
  display_level   numeric(3,1),
  -- High volatility = new or inconsistent player; widens the K factor.
  volatility      numeric(5,2) not null default 350,
  matches_played  integer not null default 0,
  wins            integer not null default 0,
  losses          integer not null default 0,
  is_provisional  boolean not null default true,
  self_assessed_level numeric(3,1),
  last_match_at   timestamptz,
  updated_at      timestamptz not null default now(),
  primary key (user_id, discipline)
);

create index player_ratings_discipline_idx on app.player_ratings (discipline, rating desc);

create table app.rating_history (
  id            bigserial primary key,
  user_id       uuid not null references app.profiles(id) on delete cascade,
  discipline    app.discipline not null,
  rating_before numeric(6,2) not null,
  rating_after  numeric(6,2) not null,
  match_ref_type text,           -- 'tournament_match' | 'open_match' | 'ladder_challenge'
  match_ref_id  uuid,
  occurred_at   timestamptz not null default now()
);

create index rating_history_user_idx on app.rating_history (user_id, discipline, occurred_at desc);

-- ---------------------------------------------------------------------
-- Ladders and seasonal leagues
-- ---------------------------------------------------------------------

create table app.ladders (
  id            uuid primary key default gen_random_uuid(),
  name_en       text not null,
  name_ar       text,
  discipline    app.discipline not null,
  emirate       app.emirate not null,
  season_label  text not null,          -- '2026 Autumn'
  starts_on     date not null,
  ends_on       date not null,
  -- How far up you may challenge.
  challenge_range integer not null default 2,
  -- Days to accept or forfeit.
  response_days integer not null default 7,
  gender_policy app.gender_policy not null default 'mixed',
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

create table app.ladder_standings (
  ladder_id     uuid not null references app.ladders(id) on delete cascade,
  user_id       uuid not null references app.profiles(id) on delete cascade,
  position      integer not null,
  points        integer not null default 0,
  matches_played integer not null default 0,
  wins          integer not null default 0,
  losses        integer not null default 0,
  joined_at     timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (ladder_id, user_id)
);

create unique index ladder_standings_position_idx on app.ladder_standings (ladder_id, position);

-- ---------------------------------------------------------------------
-- Challenges. Built to plug into Dubai Fitness Challenge (November) and a
-- Ramadan night-movement challenge, the two moments a year when the whole
-- country is already primed.
-- ---------------------------------------------------------------------

create table app.challenges (
  id              uuid primary key default gen_random_uuid(),
  slug            citext not null unique,
  title_en        text not null,
  title_ar        text not null,
  description_en  text,
  description_ar  text,

  metric          app.challenge_metric not null,
  target_value    numeric(12,2),
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,

  scope           text not null default 'global'
                  check (scope in ('global', 'emirate', 'club', 'corporate', 'venue')),
  scope_ref_id    uuid,
  emirate         app.emirate,

  allows_teams    boolean not null default false,
  team_size_max   integer,

  sponsor_name    text,
  sponsor_logo_url text,
  prize_description_en text,
  prize_description_ar text,

  -- Activity sources accepted as evidence.
  accepts_strava  boolean not null default true,
  accepts_checkins boolean not null default true,
  accepts_manual  boolean not null default false,

  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  constraint challenges_window check (ends_at > starts_at)
);

create index challenges_active_idx on app.challenges (is_active, starts_at, ends_at);

create table app.challenge_teams (
  id            uuid primary key default gen_random_uuid(),
  challenge_id  uuid not null references app.challenges(id) on delete cascade,
  name          text not null,
  captain_id    uuid not null references app.profiles(id) on delete cascade,
  club_id       uuid references app.clubs(id) on delete set null,
  company_name  text,
  total_value   numeric(14,2) not null default 0,
  created_at    timestamptz not null default now(),
  unique (challenge_id, name)
);

create table app.challenge_participants (
  challenge_id  uuid not null references app.challenges(id) on delete cascade,
  user_id       uuid not null references app.profiles(id) on delete cascade,
  team_id       uuid references app.challenge_teams(id) on delete set null,
  total_value   numeric(14,2) not null default 0,
  rank          integer,
  joined_at     timestamptz not null default now(),
  last_activity_at timestamptz,
  primary key (challenge_id, user_id)
);

create index challenge_participants_leaderboard_idx
  on app.challenge_participants (challenge_id, total_value desc);

create table app.challenge_activities (
  id            bigserial primary key,
  challenge_id  uuid not null references app.challenges(id) on delete cascade,
  user_id       uuid not null references app.profiles(id) on delete cascade,
  value         numeric(12,2) not null,
  source        text not null check (source in ('strava', 'checkin', 'meet', 'event', 'manual')),
  source_ref_id uuid,
  -- Strava activity id, to stop the same run being counted twice.
  external_id   text,
  occurred_at   timestamptz not null,
  created_at    timestamptz not null default now()
);

create unique index challenge_activities_dedupe_idx
  on app.challenge_activities (challenge_id, user_id, external_id)
  where external_id is not null;

-- ---------------------------------------------------------------------
-- Light social graph. Deliberately thin: this is proof your friends showed
-- up, not a social network.
-- ---------------------------------------------------------------------

create table app.follows (
  follower_id   uuid not null references app.profiles(id) on delete cascade,
  followee_id   uuid not null references app.profiles(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint follows_not_self check (follower_id <> followee_id)
);

create index follows_followee_idx on app.follows (followee_id);

create table app.activity_feed (
  id            bigserial primary key,
  user_id       uuid not null references app.profiles(id) on delete cascade,
  kind          text not null,   -- 'checkin' | 'meet_attended' | 'match_played' | 'event_finished' | 'badge'
  ref_type      text,
  ref_id        uuid,
  payload       jsonb not null default '{}'::jsonb,
  visibility    text not null default 'followers'
                check (visibility in ('public', 'followers', 'private')),
  occurred_at   timestamptz not null default now()
);

create index activity_feed_user_idx on app.activity_feed (user_id, occurred_at desc);
