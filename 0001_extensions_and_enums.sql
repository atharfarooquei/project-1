-- =====================================================================
-- NABD :: 0001 :: Extensions, schemas and enumerated types
-- ---------------------------------------------------------------------
-- Run order matters. Every later migration depends on the types below.
-- =====================================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";      -- gen_random_uuid, digest, hmac
create extension if not exists "postgis";       -- venue / meeting-point geography
create extension if not exists "btree_gist";    -- exclusion constraints on time ranges
create extension if not exists "citext";        -- case-insensitive slugs and emails

-- Application schema. `public` is left for Supabase-managed objects.
create schema if not exists app;

-- ---------------------------------------------------------------------
-- Geography / locale
-- ---------------------------------------------------------------------

create type app.emirate as enum (
  'dubai', 'abu_dhabi', 'sharjah', 'ajman',
  'ras_al_khaimah', 'fujairah', 'umm_al_quwain'
);

create type app.language_code as enum ('en', 'ar');

-- ---------------------------------------------------------------------
-- Access control / policy
-- ---------------------------------------------------------------------

-- Gender policy is a hard constraint enforced at check-in and at booking,
-- not a display filter. `ladies_hours` means the venue is mixed except
-- inside declared windows (see app.venue_gender_windows).
create type app.gender_policy as enum (
  'mixed', 'ladies_only', 'men_only', 'ladies_hours'
);

create type app.gender as enum ('male', 'female', 'prefer_not_to_say');

-- Tier codes. `community` is the free tier: no venue access at all.
create type app.tier_code as enum ('community', 'core', 'elite');

create type app.subscription_status as enum (
  'trialing', 'active', 'paused', 'past_due', 'cancelled', 'expired'
);

-- ---------------------------------------------------------------------
-- Supply
-- ---------------------------------------------------------------------

create type app.venue_type as enum (
  'commercial_gym', 'boutique_studio', 'crossfit_box', 'hotel_gym',
  'padel_club', 'tennis_club', 'swimming_pool', 'yoga_studio',
  'martial_arts', 'climbing', 'running_track', 'cycling_track', 'multi_sport'
);

create type app.venue_status as enum (
  'draft', 'pending_review', 'active', 'suspended', 'licence_expired', 'offboarded'
);

create type app.discipline as enum (
  'running', 'cycling', 'padel', 'tennis', 'swimming', 'strength',
  'crossfit', 'hyrox', 'yoga', 'pilates', 'hiit', 'boxing',
  'martial_arts', 'football', 'basketball', 'hiking', 'climbing',
  'triathlon', 'rowing', 'dance', 'other'
);

-- ---------------------------------------------------------------------
-- Activity records
-- ---------------------------------------------------------------------

create type app.visit_status as enum (
  'granted', 'denied', 'manual_override', 'reversed'
);

create type app.checkin_method as enum (
  'dynamic_qr', 'manual_override', 'nfc', 'geofence_auto'
);

-- Every denial returns one of these. A generic failure is useless to both
-- the member and the receptionist: "tier does not cover" and "you have used
-- your four visits here" produce completely different member behaviour.
create type app.denial_reason as enum (
  'invalid_signature', 'expired_code', 'venue_inactive', 'venue_licence_expired',
  'partner_paused_access', 'outside_geofence', 'no_subscription',
  'subscription_paused', 'subscription_past_due', 'tier_not_covered',
  'gender_policy', 'blackout_window', 'venue_daily_cap_reached',
  'venue_concurrency_reached', 'user_venue_monthly_cap_reached',
  'insufficient_credits', 'duplicate_checkin', 'age_restricted',
  'waiver_required', 'account_suspended'
);

create type app.booking_status as enum (
  'confirmed', 'waitlisted', 'cancelled_by_user',
  'cancelled_by_venue', 'attended', 'no_show'
);

-- ---------------------------------------------------------------------
-- Community
-- ---------------------------------------------------------------------

create type app.club_visibility as enum ('public', 'request_to_join', 'invite_only');
create type app.club_role as enum ('owner', 'admin', 'leader', 'member');

create type app.attendance_status as enum (
  'going', 'waitlist', 'attended', 'no_show', 'cancelled'
);

-- Drop / no-drop matters for cycling: a beginner needs to know whether the
-- group will wait. Pace groups for running are stored separately as jsonb.
create type app.ride_style as enum ('no_drop', 'drop', 'regroup_at_points');

-- ---------------------------------------------------------------------
-- Events and tournaments
-- ---------------------------------------------------------------------

create type app.event_type as enum (
  'race', 'tournament', 'workshop', 'retreat', 'bootcamp',
  'social', 'activation', 'clinic'
);

create type app.event_status as enum (
  'draft', 'pending_compliance', 'published', 'sold_out',
  'in_progress', 'completed', 'cancelled', 'postponed'
);

create type app.registration_status as enum (
  'reserved', 'confirmed', 'waitlisted', 'cancelled',
  'refunded', 'transferred', 'dns', 'dnf', 'finished'
);

create type app.tournament_format as enum (
  'single_elimination', 'double_elimination', 'round_robin',
  'group_then_knockout', 'americano', 'mexicano', 'ladder'
);

create type app.match_status as enum (
  'scheduled', 'in_progress', 'completed', 'walkover', 'cancelled'
);

create type app.challenge_metric as enum (
  'distance_km', 'duration_min', 'checkin_count',
  'streak_days', 'steps', 'elevation_m', 'sessions'
);

-- ---------------------------------------------------------------------
-- Compliance
-- ---------------------------------------------------------------------

create type app.permit_authority as enum (
  'dubai_sports_council', 'abu_dhabi_sports_council', 'sharjah_sports_council',
  'ajman_sports_council', 'municipality', 'dtcm', 'rta', 'police',
  'civil_defence', 'other'
);

create type app.permit_status as enum (
  'not_required', 'pending', 'approved', 'rejected', 'expired'
);

-- PDPL: consent purposes are enumerated so that a data subject request can
-- be answered mechanically rather than by reading code.
create type app.consent_purpose as enum (
  'terms_of_service', 'privacy_policy', 'marketing_email', 'marketing_push',
  'marketing_sms', 'location_processing', 'health_data_processing',
  'photography_media', 'partner_data_sharing'
);

-- ---------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------

create type app.payment_provider as enum (
  'stripe', 'apple_pay', 'google_pay', 'tabby', 'tamara',
  'network_intl', 'bank_transfer', 'credit_balance'
);

create type app.payment_status as enum (
  'requires_action', 'processing', 'succeeded',
  'failed', 'refunded', 'partially_refunded', 'disputed'
);

-- Agent vs principal changes the VAT treatment and revenue recognition on
-- every ticket sold. Recorded per order, not assumed globally.
create type app.supply_role as enum ('principal', 'agent');

create type app.credit_reason as enum (
  'monthly_allocation', 'rollover', 'purchase', 'promotional',
  'class_booking', 'court_booking', 'premium_checkin', 'event_entry',
  'no_show_penalty', 'late_cancel_penalty', 'refund', 'expiry',
  'admin_adjustment', 'pause_freeze', 'pause_unfreeze'
);

create type app.payout_status as enum (
  'accruing', 'pending_review', 'approved', 'paid', 'disputed', 'on_hold'
);
