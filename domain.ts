/**
 * NABD :: shared domain types
 *
 * These mirror the enums declared in supabase/migrations/0001. Keep them in
 * sync; the codegen script (`pnpm db:types`) regenerates the row types, but
 * these hand-written unions are what the entitlement engine reasons over and
 * they are deliberately independent of any database client.
 */

export type Emirate =
  | 'dubai'
  | 'abu_dhabi'
  | 'sharjah'
  | 'ajman'
  | 'ras_al_khaimah'
  | 'fujairah'
  | 'umm_al_quwain';

export type LanguageCode = 'en' | 'ar';

export type Gender = 'male' | 'female' | 'prefer_not_to_say';

/**
 * `ladies_hours` means the venue is mixed except inside declared windows.
 * The engine never sees this value: `effectiveGenderPolicy` resolves it to a
 * concrete policy for the instant being evaluated before the check runs.
 */
export type GenderPolicy = 'mixed' | 'ladies_only' | 'men_only' | 'ladies_hours';

export type TierCode = 'community' | 'core' | 'elite';

export type SubscriptionStatus =
  | 'trialing'
  | 'active'
  | 'paused'
  | 'past_due'
  | 'cancelled'
  | 'expired';

export type VenueType =
  | 'commercial_gym'
  | 'boutique_studio'
  | 'crossfit_box'
  | 'hotel_gym'
  | 'padel_club'
  | 'tennis_club'
  | 'swimming_pool'
  | 'yoga_studio'
  | 'martial_arts'
  | 'climbing'
  | 'running_track'
  | 'cycling_track'
  | 'multi_sport';

export type Discipline =
  | 'running'
  | 'cycling'
  | 'padel'
  | 'tennis'
  | 'swimming'
  | 'strength'
  | 'crossfit'
  | 'hyrox'
  | 'yoga'
  | 'pilates'
  | 'hiit'
  | 'boxing'
  | 'martial_arts'
  | 'football'
  | 'basketball'
  | 'hiking'
  | 'climbing'
  | 'triathlon'
  | 'rowing'
  | 'dance'
  | 'other';

/**
 * Every denial returns one of these. A generic "access denied" is useless:
 * "your pass does not cover this gym", "you have used your four visits here
 * this month" and "this gym is at capacity right now" produce completely
 * different member behaviour, and reception needs to know which it is.
 */
export type DenialReason =
  | 'invalid_signature'
  | 'expired_code'
  | 'venue_inactive'
  | 'venue_licence_expired'
  | 'partner_paused_access'
  | 'outside_geofence'
  | 'no_subscription'
  | 'subscription_paused'
  | 'subscription_past_due'
  | 'tier_not_covered'
  | 'gender_policy'
  | 'blackout_window'
  | 'venue_daily_cap_reached'
  | 'venue_concurrency_reached'
  | 'user_venue_monthly_cap_reached'
  | 'insufficient_credits'
  | 'duplicate_checkin'
  | 'age_restricted'
  | 'waiver_required'
  | 'account_suspended';

export type TournamentFormat =
  | 'single_elimination'
  | 'double_elimination'
  | 'round_robin'
  | 'group_then_knockout'
  | 'americano'
  | 'mexicano'
  | 'ladder';

export type EventType =
  | 'race'
  | 'tournament'
  | 'workshop'
  | 'retreat'
  | 'bootcamp'
  | 'social'
  | 'activation'
  | 'clinic';

export interface LatLng {
  lat: number;
  lng: number;
}

export interface VenueSummary {
  id: string;
  slug: string;
  nameEn: string;
  nameAr: string | null;
  venueType: VenueType;
  disciplines: Discipline[];
  emirate: Emirate;
  area: string;
  genderPolicy: GenderPolicy;
  tierRequired: TierCode;
  checkinCreditCost: number;
  amenities: Record<string, unknown>;
  photos: string[];
  ratingAvg: number | null;
  ratingCount: number;
  lat: number;
  lng: number;
  distanceKm: number;
  isPaused: boolean;
}

export interface PaceGroup {
  label: string;
  paceSecPerKm?: number;
  leaderId?: string;
  capacity?: number;
}

/** Traffic-light outdoor safety state for the UAE summer. */
export type HeatFlag = 'green' | 'amber' | 'red';
