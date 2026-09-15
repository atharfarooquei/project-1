-- =====================================================================
-- NABD :: 0010 :: Functions, compliance gates and scheduled maintenance
-- ---------------------------------------------------------------------
-- The compliance gates are triggers, not application checks. An event that
-- can be published without a permit by hitting a different code path is not
-- gated at all.
-- =====================================================================

-- ---------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------

create or replace function app.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','partners','venues','venue_caps','classes','plans',
    'subscriptions','clubs','meets','organisers','events','orders','payouts'
  ] loop
    execute format(
      'create trigger %I_touch before update on app.%I
       for each row execute function app.touch_updated_at()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Distance helper. Discovery distance is computed in the database with
-- PostGIS, never client-side from a list, because a client that computes
-- distance cannot sort or page correctly.
-- ---------------------------------------------------------------------

create or replace function app.venues_near(
  p_lat            double precision,
  p_lng            double precision,
  p_radius_km      double precision default 15,
  p_emirate        app.emirate default null,
  p_gender_policy  app.gender_policy[] default null,
  p_venue_types    app.venue_type[] default null,
  p_disciplines    app.discipline[] default null,
  p_max_tier       app.tier_code default 'elite',
  p_open_now       boolean default false,
  p_limit          integer default 50,
  p_offset         integer default 0
)
returns table (
  id uuid, slug citext, name_en text, name_ar text,
  venue_type app.venue_type, disciplines app.discipline[],
  emirate app.emirate, area text,
  gender_policy app.gender_policy, tier_required app.tier_code,
  checkin_credit_cost integer, amenities jsonb, photos text[],
  rating_avg numeric, rating_count integer,
  lat double precision, lng double precision,
  distance_km numeric, is_paused boolean
)
language sql stable
set search_path = app, public
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  )
  select
    v.id, v.slug, v.name_en, v.name_ar,
    v.venue_type, v.disciplines, v.emirate, v.area,
    v.gender_policy, v.tier_required, v.checkin_credit_cost,
    v.amenities, v.photos, v.rating_avg, v.rating_count,
    st_y(v.location::geometry) as lat,
    st_x(v.location::geometry) as lng,
    round((st_distance(v.location, o.g) / 1000.0)::numeric, 2) as distance_km,
    v.aggregator_access_paused as is_paused
  from app.venues v, origin o
  where v.status = 'active'
    and st_dwithin(v.location, o.g, p_radius_km * 1000)
    and (p_emirate is null or v.emirate = p_emirate)
    and (p_gender_policy is null or v.gender_policy = any(p_gender_policy))
    and (p_venue_types is null or v.venue_type = any(p_venue_types))
    and (p_disciplines is null or v.disciplines && p_disciplines)
    and (
      p_max_tier = 'elite'
      or (p_max_tier = 'core' and v.tier_required in ('community', 'core'))
      or (p_max_tier = 'community' and v.tier_required = 'community')
    )
    and (not p_open_now or app.venue_is_open(v.id, now()))
  order by st_distance(v.location, o.g)
  limit p_limit offset p_offset;
$$;

-- ---------------------------------------------------------------------
-- Opening hours / blackout / gender window evaluation
-- ---------------------------------------------------------------------

create or replace function app.venue_is_open(p_venue_id uuid, p_at timestamptz)
returns boolean language sql stable set search_path = app, public as $$
  with local_time as (
    select
      extract(dow from p_at at time zone 'Asia/Dubai')::int as dow,
      (p_at at time zone 'Asia/Dubai')::time as t
  )
  select coalesce(bool_or(
    (h ->> 'dow')::int = lt.dow
    and lt.t >= (h ->> 'open')::time
    and lt.t <  (h ->> 'close')::time
  ), true)
  from app.venues v, local_time lt,
       lateral jsonb_array_elements(v.opening_hours) h
  where v.id = p_venue_id;
$$;

create or replace function app.venue_in_blackout(p_venue_id uuid, p_at timestamptz)
returns boolean language sql stable set search_path = app, public as $$
  with local_time as (
    select
      extract(dow from p_at at time zone 'Asia/Dubai')::int as dow,
      (p_at at time zone 'Asia/Dubai')::time as t,
      (p_at at time zone 'Asia/Dubai')::date as d
  )
  select exists (
    select 1 from app.venue_blackouts b, local_time lt
    where b.venue_id = p_venue_id
      and (
        (b.day_of_week = lt.dow and lt.t >= b.start_time and lt.t < b.end_time)
        or (b.starts_on is not null and lt.d between b.starts_on and b.ends_on)
      )
  );
$$;

-- Returns the gender policy effective at a given instant, resolving
-- ladies_hours windows into a concrete policy.
create or replace function app.effective_gender_policy(p_venue_id uuid, p_at timestamptz)
returns app.gender_policy language plpgsql stable set search_path = app, public as $$
declare
  v_base app.gender_policy;
  v_window app.gender_policy;
begin
  select gender_policy into v_base from app.venues where id = p_venue_id;
  if v_base <> 'ladies_hours' then
    return v_base;
  end if;

  select w.policy into v_window
  from app.venue_gender_windows w
  where w.venue_id = p_venue_id
    and w.day_of_week = extract(dow from p_at at time zone 'Asia/Dubai')::int
    and (p_at at time zone 'Asia/Dubai')::time >= w.start_time
    and (p_at at time zone 'Asia/Dubai')::time <  w.end_time
  limit 1;

  return coalesce(v_window, 'mixed');
end $$;

-- ---------------------------------------------------------------------
-- Cap counters used by the entitlement engine
-- ---------------------------------------------------------------------

create or replace function app.venue_checkins_today(p_venue_id uuid)
returns integer language sql stable set search_path = app, public as $$
  select count(*)::integer
  from app.visits
  where venue_id = p_venue_id
    and status in ('granted', 'manual_override')
    and reversed_at is null
    and checked_in_at >= date_trunc('day', now() at time zone 'Asia/Dubai')
                         at time zone 'Asia/Dubai';
$$;

create or replace function app.user_venue_visits_this_month(p_user_id uuid, p_venue_id uuid)
returns integer language sql stable set search_path = app, public as $$
  select count(*)::integer
  from app.visits
  where user_id = p_user_id
    and venue_id = p_venue_id
    and status in ('granted', 'manual_override')
    and reversed_at is null
    and checked_in_at >= date_trunc('month', now() at time zone 'Asia/Dubai')
                          at time zone 'Asia/Dubai';
$$;

-- ---------------------------------------------------------------------
-- Rotating check-in code verification.
-- ---------------------------------------------------------------------
-- The venue tablet displays the code; the member scans it. The reverse of
-- the usual design and the correct one: a member-displayed code is a
-- screenshot away from being shared, a venue-displayed rotating code is not.
-- ---------------------------------------------------------------------

create or replace function app.expected_checkin_code(
  p_venue_id uuid, p_window bigint, p_use_previous boolean default false
)
returns text language sql stable security definer set search_path = app, public as $$
  select encode(
    hmac(
      p_venue_id::text || '.' || p_window::text,
      case when p_use_previous then coalesce(k.previous_secret, k.secret) else k.secret end,
      'sha256'
    ), 'hex'
  )
  from app.venue_signing_keys k
  where k.venue_id = p_venue_id;
$$;

create or replace function app.verify_checkin_code(
  p_venue_id uuid, p_window bigint, p_code text
)
returns boolean language plpgsql stable security definer set search_path = app, public as $$
declare
  v_window_seconds integer;
  v_now_window bigint;
begin
  select window_seconds into v_window_seconds
  from app.venue_signing_keys where venue_id = p_venue_id;

  if v_window_seconds is null then
    return false;
  end if;

  v_now_window := floor(extract(epoch from now()) / v_window_seconds)::bigint;

  -- Accept the current window and one either side, for clock skew on the
  -- tablet and on the member's handset.
  if abs(v_now_window - p_window) > 1 then
    return false;
  end if;

  return
    app.expected_checkin_code(p_venue_id, p_window, false) = p_code
    or app.expected_checkin_code(p_venue_id, p_window, true) = p_code;
end $$;

-- ---------------------------------------------------------------------
-- Compliance gate: an event may not be published without a permit.
-- ---------------------------------------------------------------------

create or replace function app.enforce_event_publication_gates()
returns trigger language plpgsql set search_path = app, public as $$
declare
  v_has_permit boolean;
  v_has_insurance boolean;
  v_organiser_verified boolean;
  v_needs_permit boolean;
begin
  if new.status <> 'published' or old.status = 'published' then
    return new;
  end if;

  select o.is_verified into v_organiser_verified
  from app.organisers o where o.id = new.organiser_id;

  if not coalesce(v_organiser_verified, false) then
    raise exception 'Event % cannot be published: organiser is not verified', new.id
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from app.insurance_certificates ic
    where ic.holder_type = 'organiser'
      and ic.holder_id = new.organiser_id
      and ic.cover_type = 'public_liability'
      and ic.valid_to >= new.ends_at::date
      and ic.verified_at is not null
  ) into v_has_insurance;

  if not v_has_insurance then
    raise exception 'Event % cannot be published: no verified public liability cover valid through the event date', new.id
      using errcode = 'check_violation';
  end if;

  -- Races and tournaments engage the sports council regime regardless of
  -- the organiser's own view of whether a permit is needed.
  v_needs_permit := new.requires_permit or new.event_type in ('race', 'tournament');

  if v_needs_permit then
    select exists (
      select 1 from app.permits p
      where p.subject_type = 'event'
        and p.subject_id = new.id
        and (
          (p.status = 'approved' and (p.expires_at is null or p.expires_at >= new.ends_at::date))
          or p.is_override
        )
    ) into v_has_permit;

    if not v_has_permit then
      raise exception 'Event % cannot be published: no approved permit or recorded admin override', new.id
        using errcode = 'check_violation';
    end if;
  end if;

  if new.requires_waiver and new.waiver_id is null then
    raise exception 'Event % cannot be published: requires a waiver but none is attached', new.id
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

create trigger events_publication_gate
  before update on app.events
  for each row execute function app.enforce_event_publication_gates();

-- ---------------------------------------------------------------------
-- Compliance gate: an under-18 registration needs guardian consent.
-- ---------------------------------------------------------------------

create or replace function app.enforce_minor_registration()
returns trigger language plpgsql set search_path = app, public as $$
declare
  v_dob date;
  v_min_age integer;
  v_has_consent boolean;
begin
  select date_of_birth into v_dob from app.profiles where id = new.user_id;
  select min_age into v_min_age from app.events where id = new.event_id;

  if v_dob is null then
    return new;   -- age unknown; the client flow collects DOB before payment
  end if;

  if v_min_age is not null
     and v_dob > (current_date - (v_min_age || ' years')::interval) then
    raise exception 'Registration refused: participant is below the minimum age of % for this event', v_min_age
      using errcode = 'check_violation';
  end if;

  if v_dob > current_date - interval '18 years' then
    select exists (
      select 1 from app.guardian_consents gc
      where gc.minor_user_id = new.user_id
        and gc.revoked_at is null
        and gc.verified_at is not null
        and (gc.expires_at is null or gc.expires_at > now())
        and (gc.scope = 'general'
             or (gc.scope = 'event' and gc.scope_ref_id = new.event_id))
    ) into v_has_consent;

    if not v_has_consent then
      raise exception 'Registration refused: participant is under 18 and has no verified guardian consent'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end $$;

create trigger event_registrations_minor_gate
  before insert on app.event_registrations
  for each row execute function app.enforce_minor_registration();

-- ---------------------------------------------------------------------
-- Venue licence expiry suspends supply automatically.
-- ---------------------------------------------------------------------

create or replace function app.suspend_expired_venue_licences()
returns integer language plpgsql set search_path = app, public as $$
declare v_count integer;
begin
  update app.venues v
  set status = 'licence_expired'
  where v.status = 'active'
    and (
      (v.sports_permit_expires_at is not null and v.sports_permit_expires_at < current_date)
      or exists (
        select 1 from app.partners p
        where p.id = v.partner_id
          and p.licence_expires_at is not null
          and p.licence_expires_at < current_date
      )
    );
  get diagnostics v_count = row_count;

  insert into app.audit_log (action, subject_type, after_state)
  values ('venues.licence_expiry_sweep', 'system',
          jsonb_build_object('suspended_count', v_count));

  return v_count;
end $$;

-- ---------------------------------------------------------------------
-- Counter maintenance
-- ---------------------------------------------------------------------

create or replace function app.sync_club_member_count()
returns trigger language plpgsql set search_path = app, public as $$
begin
  update app.clubs c
  set member_count = (
    select count(*) from app.club_members m
    where m.club_id = c.id and m.left_at is null and m.approved_at is not null
  )
  where c.id = coalesce(new.club_id, old.club_id);
  return null;
end $$;

create trigger club_members_count_sync
  after insert or update or delete on app.club_members
  for each row execute function app.sync_club_member_count();

create or replace function app.sync_open_match_fill()
returns trigger language plpgsql set search_path = app, public as $$
declare v_filled integer; v_total integer;
begin
  select count(*) into v_filled
  from app.open_match_players
  where match_id = coalesce(new.match_id, old.match_id) and status = 'joined';

  update app.open_matches
  set filled_slots = v_filled,
      status = case
        when status in ('cancelled', 'completed') then status
        when v_filled >= total_slots then 'full'
        else 'open'
      end
  where id = coalesce(new.match_id, old.match_id)
  returning total_slots into v_total;

  return null;
end $$;

create trigger open_match_players_fill_sync
  after insert or update or delete on app.open_match_players
  for each row execute function app.sync_open_match_fill();

-- ---------------------------------------------------------------------
-- PDPL retention sweep. Precise scan coordinates are kept for 90 days for
-- fraud review, then nulled. Storage limitation is a legal obligation, not
-- a housekeeping preference.
-- ---------------------------------------------------------------------

create or replace function app.retention_sweep()
returns void language plpgsql set search_path = app, public as $$
begin
  update app.visits
  set scan_location = null, ip_address = null, device_fingerprint = null
  where checked_in_at < now() - interval '90 days'
    and scan_location is not null;

  delete from app.challenge_activities
  where occurred_at < now() - interval '3 years';

  update app.emergency_contacts ec
  set medical_notes = null
  where not exists (
    select 1 from app.event_registrations r
    where r.user_id = ec.user_id
      and r.registered_at > now() - interval '90 days'
  ) and medical_notes is not null;

  insert into app.audit_log (action, subject_type)
  values ('pdpl.retention_sweep', 'system');
end $$;

comment on function app.retention_sweep is
  'Schedule daily via pg_cron. PDPL storage limitation: precise location and device data are not retained beyond the fraud-review window.';
