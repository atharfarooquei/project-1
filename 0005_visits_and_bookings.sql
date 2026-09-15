-- =====================================================================
-- NABD :: 0005 :: Visits, bookings and the entitlement snapshot
-- ---------------------------------------------------------------------
-- Denied attempts are recorded, not discarded. A member who is refused
-- three times at the same venue is either a fraud signal or a product bug,
-- and you cannot tell which without the rows.
-- =====================================================================

create table app.visits (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references app.profiles(id) on delete cascade,
  venue_id            uuid not null references app.venues(id) on delete restrict,

  status              app.visit_status not null,
  denial_reason       app.denial_reason,

  method              app.checkin_method not null default 'dynamic_qr',
  checked_in_at       timestamptz not null default now(),
  checked_out_at      timestamptz,

  -- Where the member was when they scanned. Retained 90 days for fraud
  -- review, then nulled by the retention job (PDPL: storage limitation).
  scan_location       geography(Point, 4326),
  distance_from_venue_m integer,
  device_fingerprint  text,
  ip_address          inet,

  credits_charged     integer not null default 0 check (credits_charged >= 0),
  -- Our cost, frozen at visit time. Partner rates change; historic payouts
  -- must not.
  cost_to_platform_aed numeric(8,2),

  -- The entitlement as it stood at this instant: tier, plan code, caps,
  -- gender policy, blackout state, balances. When a partner disputes a
  -- payout eight weeks later the answer is in this column, not in a
  -- recomputation against rules that have since changed.
  entitlement_snapshot jsonb not null default '{}'::jsonb,

  -- Manual override by reception (dead phone, app failure).
  override_by         uuid references app.profiles(id),
  override_reason     text,

  -- Set when a visit is reversed after the fact (fraud, duplicate, dispute).
  reversed_at         timestamptz,
  reversal_reason     text,

  created_at          timestamptz not null default now(),
  constraint visits_denial_has_reason
    check (status <> 'denied' or denial_reason is not null),
  constraint visits_override_has_reason
    check (method <> 'manual_override' or override_reason is not null)
);

create index visits_user_time_idx   on app.visits (user_id, checked_in_at desc);
create index visits_venue_time_idx  on app.visits (venue_id, checked_in_at desc);
create index visits_granted_idx     on app.visits (venue_id, checked_in_at)
  where status = 'granted';
-- Backs the per-user per-venue monthly cap check on the hot path.
create index visits_cap_lookup_idx  on app.visits (user_id, venue_id, checked_in_at)
  where status in ('granted', 'manual_override');
create index visits_denials_idx     on app.visits (denial_reason, checked_in_at desc)
  where status = 'denied';

comment on column app.visits.entitlement_snapshot is
  'Frozen entitlement at decision time. Never recompute a historic visit; read this.';

-- Granted visits only, which is what caps and payouts count.
create or replace view app.granted_visits as
select * from app.visits
where status in ('granted', 'manual_override')
  and reversed_at is null;

-- ---------------------------------------------------------------------
-- Class bookings
-- ---------------------------------------------------------------------

create table app.class_bookings (
  id              uuid primary key default gen_random_uuid(),
  class_id        uuid not null references app.classes(id) on delete cascade,
  user_id         uuid not null references app.profiles(id) on delete cascade,
  status          app.booking_status not null default 'confirmed',
  waitlist_position integer,
  booked_at       timestamptz not null default now(),
  cancelled_at    timestamptz,
  attended_at     timestamptz,
  credits_charged integer not null default 0,
  -- A no-show costs the partner a seat, so it costs the member credits.
  penalty_credits integer not null default 0,
  entitlement_snapshot jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  unique (class_id, user_id)
);

create index class_bookings_user_idx  on app.class_bookings (user_id, booked_at desc);
create index class_bookings_class_idx on app.class_bookings (class_id, status);

-- ---------------------------------------------------------------------
-- Court bookings
-- ---------------------------------------------------------------------

create table app.court_bookings (
  id              uuid primary key default gen_random_uuid(),
  court_slot_id   uuid not null references app.court_slots(id) on delete cascade,
  -- The member who booked and pays. Other players join via open_match_slots.
  booked_by       uuid not null references app.profiles(id) on delete cascade,
  status          app.booking_status not null default 'confirmed',
  credits_charged integer not null default 0,
  cash_charged_aed numeric(8,2) not null default 0,
  -- Set when this booking was created to host an open match.
  open_match_id   uuid,
  booked_at       timestamptz not null default now(),
  cancelled_at    timestamptz,
  created_at      timestamptz not null default now(),
  unique (court_slot_id)
);

create index court_bookings_user_idx on app.court_bookings (booked_by, booked_at desc);
