-- =====================================================================
-- NABD :: 0002 :: Identity, consent and the compliance primitives
-- ---------------------------------------------------------------------
-- The compliance tables sit this early deliberately. Waivers, permits and
-- consents are referenced by events, venues and check-ins downstream, and
-- retrofitting them into a live system means retrofitting them into a live
-- liability.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Profiles. Extends auth.users 1:1.
-- ---------------------------------------------------------------------

create table app.profiles (
  id                  uuid primary key references auth.users(id) on delete cascade,
  display_name        text not null check (char_length(display_name) between 2 and 60),
  handle              citext unique check (handle ~ '^[a-z0-9_]{3,24}$'),
  avatar_url          text,
  bio                 text check (char_length(bio) <= 400),

  -- Date of birth drives age gates and guardian-consent requirements.
  -- Stored, never displayed; only the derived age band is exposed.
  date_of_birth       date,
  gender              app.gender,

  language_preference app.language_code not null default 'en',
  home_emirate        app.emirate,
  home_area           text,

  -- Coarse home location for discovery defaults. Precise live location is
  -- never persisted; it is passed per request and discarded (PDPL: data
  -- minimisation, purpose limitation).
  home_location       geography(Point, 4326),

  phone_e164          text check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  phone_verified_at   timestamptz,

  strava_athlete_id   text unique,

  is_suspended        boolean not null default false,
  suspended_reason    text,

  onboarded_at        timestamptz,
  last_active_at      timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index profiles_home_location_idx on app.profiles using gist (home_location);
create index profiles_home_emirate_idx  on app.profiles (home_emirate);

comment on column app.profiles.date_of_birth is
  'Sensitive. Used only to derive age band for event age gates and guardian consent. Never exposed to partners.';

-- Derived, non-reversible age band. Use this everywhere instead of DOB.
create or replace function app.age_band(dob date)
returns text language sql immutable as $$
  select case
    when dob is null then 'unknown'
    when dob > current_date - interval '16 years' then 'under_16'
    when dob > current_date - interval '18 years' then 'under_18'
    when dob > current_date - interval '25 years' then '18_24'
    when dob > current_date - interval '35 years' then '25_34'
    when dob > current_date - interval '45 years' then '35_44'
    when dob > current_date - interval '55 years' then '45_54'
    else '55_plus'
  end;
$$;

-- ---------------------------------------------------------------------
-- Emergency contacts and medical notes.
-- ---------------------------------------------------------------------
-- High-sensitivity. Read only by event medical staff at event time, via a
-- dedicated role. Never used for personalisation, never shared with venue
-- partners, never joined into analytics.
-- ---------------------------------------------------------------------

create table app.emergency_contacts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references app.profiles(id) on delete cascade,
  name          text not null,
  relationship  text,
  phone_e164    text not null check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  -- Free text supplied by the member (allergies, conditions the medics
  -- should know about). Encrypted at rest at the storage layer.
  medical_notes text,
  is_primary    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index emergency_contacts_one_primary_idx
  on app.emergency_contacts (user_id) where is_primary;

comment on table app.emergency_contacts is
  'PDPL high-sensitivity. Restricted role access only. Retention: 90 days after last event participation.';

-- ---------------------------------------------------------------------
-- Consent records (UAE PDPL, Federal Decree-Law 45/2021).
-- ---------------------------------------------------------------------
-- Append-only. Revocation is a new row with revoked_at set, never an update
-- of the original, so the consent history is reconstructible for a DSAR.
-- ---------------------------------------------------------------------

create table app.consents (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references app.profiles(id) on delete cascade,
  purpose         app.consent_purpose not null,
  document_version text not null,
  granted         boolean not null,
  granted_at      timestamptz not null default now(),
  revoked_at      timestamptz,
  -- Evidence of collection. Required to demonstrate valid consent.
  ip_address      inet,
  user_agent      text,
  collection_context text,           -- 'signup' | 'settings' | 'event_registration'
  created_at      timestamptz not null default now()
);

create index consents_user_purpose_idx on app.consents (user_id, purpose, granted_at desc);

-- Current effective consent per purpose.
create or replace view app.current_consents as
select distinct on (user_id, purpose)
  user_id, purpose, document_version, granted, granted_at, revoked_at
from app.consents
order by user_id, purpose, granted_at desc;

-- ---------------------------------------------------------------------
-- Waivers. Versioned and bilingual.
-- ---------------------------------------------------------------------

create table app.waivers (
  id              uuid primary key default gen_random_uuid(),
  code            text not null,                -- 'general_participation', 'trail_race', 'minors'
  version         integer not null,
  title_en        text not null,
  title_ar        text not null,
  body_en         text not null,
  body_ar         text not null,
  requires_guardian_for_minors boolean not null default true,
  effective_from  timestamptz not null,
  effective_to    timestamptz,
  created_at      timestamptz not null default now(),
  unique (code, version)
);

comment on table app.waivers is
  'UAE waiver enforceability is not absolute, particularly for gross negligence. Waivers reduce risk; they do not replace public liability insurance.';

create table app.waiver_signatures (
  id            uuid primary key default gen_random_uuid(),
  waiver_id     uuid not null references app.waivers(id),
  user_id       uuid not null references app.profiles(id) on delete cascade,
  -- Optional scope: a signature may be global or tied to one event.
  event_id      uuid,
  signed_at     timestamptz not null default now(),
  ip_address    inet,
  user_agent    text,
  -- sha256 over (user_id || waiver_id || version || signed_at || nonce).
  -- Detects tampering with the signature record itself.
  signature_hash text not null,
  -- Set when the signatory was a minor at signing time.
  guardian_consent_id uuid,
  created_at    timestamptz not null default now()
);

create index waiver_signatures_user_idx  on app.waiver_signatures (user_id, waiver_id);
create index waiver_signatures_event_idx on app.waiver_signatures (event_id);

-- ---------------------------------------------------------------------
-- Guardian consent for participants under 18.
-- ---------------------------------------------------------------------

create table app.guardian_consents (
  id                uuid primary key default gen_random_uuid(),
  minor_user_id     uuid not null references app.profiles(id) on delete cascade,
  guardian_name     text not null,
  guardian_relationship text not null,
  guardian_phone_e164 text not null,
  guardian_email    citext not null,
  -- Guardian may or may not be a platform user.
  guardian_user_id  uuid references app.profiles(id),
  emirates_id_last4 text check (emirates_id_last4 ~ '^[0-9]{4}$'),
  scope             text not null default 'general',  -- 'general' | 'event' | 'club'
  scope_ref_id      uuid,
  verified_at       timestamptz,
  verification_method text,           -- 'email_link' | 'sms_otp' | 'in_person'
  expires_at        timestamptz,
  revoked_at        timestamptz,
  created_at        timestamptz not null default now()
);

create index guardian_consents_minor_idx on app.guardian_consents (minor_user_id);

alter table app.waiver_signatures
  add constraint waiver_signatures_guardian_fk
  foreign key (guardian_consent_id) references app.guardian_consents(id);

-- ---------------------------------------------------------------------
-- Permits. Keyed polymorphically to an event or a venue.
-- ---------------------------------------------------------------------
-- An event of type race / tournament, or any event open to the public,
-- cannot reach 'published' without an approved permit row or an explicitly
-- recorded admin override. Enforced by trigger in 0010.
-- ---------------------------------------------------------------------

create table app.permits (
  id              uuid primary key default gen_random_uuid(),
  subject_type    text not null check (subject_type in ('event', 'venue', 'organiser')),
  subject_id      uuid not null,
  authority       app.permit_authority not null,
  permit_number   text,
  status          app.permit_status not null default 'pending',
  applied_at      date,
  issued_at       date,
  expires_at      date,
  document_url    text,
  notes           text,
  -- Set when an admin publishes without a permit. Requires a reason.
  is_override     boolean not null default false,
  override_reason text,
  override_by     uuid references app.profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint permits_override_needs_reason
    check (not is_override or override_reason is not null)
);

create index permits_subject_idx on app.permits (subject_type, subject_id);
create index permits_expiry_idx  on app.permits (expires_at) where status = 'approved';

comment on table app.permits is
  'Dubai: Executive Council Resolution 1/2020 governs sports establishments and events (DSC). Road events additionally engage RTA and Police. Parallel regimes in other emirates. Verify current requirements with counsel before each event.';

-- ---------------------------------------------------------------------
-- Insurance certificates. Expiry blocks new event publication.
-- ---------------------------------------------------------------------

create table app.insurance_certificates (
  id              uuid primary key default gen_random_uuid(),
  holder_type     text not null check (holder_type in ('organiser', 'partner', 'platform')),
  holder_id       uuid not null,
  insurer_name    text not null,
  policy_number   text not null,
  cover_type      text not null,   -- 'public_liability' | 'participant_accident'
  cover_amount_aed numeric(14,2),
  valid_from      date not null,
  valid_to        date not null,
  document_url    text,
  verified_at     timestamptz,
  verified_by     uuid references app.profiles(id),
  created_at      timestamptz not null default now()
);

create index insurance_holder_idx on app.insurance_certificates (holder_type, holder_id, valid_to desc);

-- ---------------------------------------------------------------------
-- Append-only audit log. Every entitlement decision, permit override,
-- payout approval and admin action lands here.
-- ---------------------------------------------------------------------

create table app.audit_log (
  id            bigserial primary key,
  actor_id      uuid references app.profiles(id),
  actor_role    text,
  action        text not null,
  subject_type  text not null,
  subject_id    uuid,
  before_state  jsonb,
  after_state   jsonb,
  ip_address    inet,
  occurred_at   timestamptz not null default now()
);

create index audit_log_subject_idx on app.audit_log (subject_type, subject_id, occurred_at desc);
create index audit_log_actor_idx   on app.audit_log (actor_id, occurred_at desc);

-- ---------------------------------------------------------------------
-- Data subject requests (PDPL access / erasure / portability).
-- ---------------------------------------------------------------------

create table app.data_subject_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references app.profiles(id) on delete cascade,
  request_type  text not null check (request_type in ('access', 'erasure', 'portability', 'rectification', 'restriction')),
  status        text not null default 'received'
                check (status in ('received', 'verifying', 'in_progress', 'completed', 'rejected')),
  received_at   timestamptz not null default now(),
  -- Statutory response clock. Set on receipt so it cannot be quietly reset.
  due_at        timestamptz not null default (now() + interval '30 days'),
  completed_at  timestamptz,
  export_url    text,
  rejection_reason text,
  handled_by    uuid references app.profiles(id)
);

create index dsr_status_due_idx on app.data_subject_requests (status, due_at);
