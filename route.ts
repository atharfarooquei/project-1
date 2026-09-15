/**
 * NABD :: POST /api/checkin
 *
 * Processes a gym check-in from a scanned venue code.
 *
 * The route does three things and nothing else: load state, call the pure
 * entitlement engine, persist the result. Every rule lives in
 * `@nabd/shared/entitlement`, which is unit-tested without a database.
 *
 * Two properties this endpoint must have, and the reasons they are not
 * optional:
 *
 *  1. Every attempt is recorded, granted or denied. A member refused three
 *     times at one venue is either a fraud signal or a product bug, and you
 *     cannot tell which without the rows.
 *
 *  2. The entitlement in force is frozen onto the visit. Partner rates, caps
 *     and tier definitions all change. Historic payouts must not.
 */

import { NextResponse, type NextRequest } from 'next/server';
import { z } from 'zod';

import {
  ENGINE_VERSION,
  evaluateCheckin,
  type CheckinContext,
  type EntitlementSnapshot,
} from '@nabd/shared/entitlement';

import { getServiceClient, getUserFromRequest } from '@/lib/supabase-server';
import { logAudit } from '@/lib/audit';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// ---------------------------------------------------------------------------
// Request
// ---------------------------------------------------------------------------

const PAYLOAD_PATTERN = /^v1\.([0-9a-f-]{36})\.(\d+)\.([0-9a-f]{64})$/i;

const bodySchema = z.object({
  /** v1.<venueId>.<timeWindow>.<hmac>, as displayed on the venue tablet. */
  payload: z.string().regex(PAYLOAD_PATTERN),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  /** GPS accuracy in metres. A very poor fix widens the geofence, because
   *  refusing a member standing in a basement gym is worse than the marginal
   *  fraud risk of a 40m allowance. */
  accuracyM: z.number().nonnegative().optional(),
  idempotencyKey: z.string().min(8).max(200),
});

interface VenueRow {
  id: string;
  name_en: string;
  name_ar: string | null;
  emirate: string;
  status: string;
  tier_required: 'community' | 'core' | 'elite';
  gender_policy: string;
  min_age: number | null;
  checkin_credit_cost: number;
  cost_per_visit_aed: number | null;
  aggregator_access_paused: boolean;
  sports_permit_expires_at: string | null;
  geofence_radius_m: number;
}

const MAX_ACCURACY_ALLOWANCE_M = 60;

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export async function POST(request: NextRequest) {
  const user = await getUserFromRequest(request);
  if (!user) {
    return NextResponse.json({ error: 'unauthenticated' }, { status: 401 });
  }

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: 'invalid_request', detail: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const { payload, lat, lng, accuracyM, idempotencyKey } = parsed.data;
  const match = PAYLOAD_PATTERN.exec(payload);
  if (!match) {
    return NextResponse.json({ error: 'invalid_request' }, { status: 400 });
  }

  const [, venueId, windowRaw, code] = match;
  const timeWindow = Number(windowRaw);
  const db = getServiceClient();
  const now = new Date();

  // -------------------------------------------------------------------------
  // Idempotency. A retried submission of the same scan must return the
  // original decision rather than create a second visit and a second charge.
  // -------------------------------------------------------------------------

  const { data: existing } = await db
    .from('credit_ledger')
    .select('ref_id')
    .eq('idempotency_key', idempotencyKey)
    .maybeSingle();

  if (existing?.ref_id) {
    const { data: priorVisit } = await db
      .from('visits')
      .select('id, status, denial_reason, credits_charged, entitlement_snapshot')
      .eq('id', existing.ref_id)
      .single();

    if (priorVisit) {
      return NextResponse.json(replayResponse(priorVisit));
    }
  }

  // -------------------------------------------------------------------------
  // Load state. Everything the engine needs, in as few round trips as the
  // shape allows.
  // -------------------------------------------------------------------------

  const [
    { data: venue },
    { data: entitlement },
    { data: caps },
    { data: signatureValid },
    { data: inBlackout },
    { data: effectivePolicy },
  ] = await Promise.all([
    db
      .from('venues')
      .select(
        'id, name_en, name_ar, emirate, status, tier_required, gender_policy, min_age, ' +
          'checkin_credit_cost, cost_per_visit_aed, aggregator_access_paused, ' +
          'sports_permit_expires_at, geofence_radius_m',
      )
      .eq('id', venueId)
      .maybeSingle<VenueRow>(),

    db
      .from('member_entitlements')
      .select('*')
      .eq('user_id', user.id)
      .maybeSingle(),

    db.from('venue_caps').select('*').eq('venue_id', venueId).maybeSingle(),

    db.rpc('verify_checkin_code', {
      p_venue_id: venueId,
      p_window: timeWindow,
      p_code: code,
    }),

    db.rpc('venue_in_blackout', { p_venue_id: venueId, p_at: now.toISOString() }),

    db.rpc('effective_gender_policy', { p_venue_id: venueId, p_at: now.toISOString() }),
  ]);

  if (!venue) {
    return NextResponse.json({ error: 'venue_not_found' }, { status: 404 });
  }

  // Counts depend on the venue existing, so they follow rather than join the
  // batch above.
  const [
    { data: checkinsToday },
    { data: userVisitsThisMonth },
    { data: lastVisit },
    { data: profile },
  ] = await Promise.all([
    db.rpc('venue_checkins_today', { p_venue_id: venueId }),
    db.rpc('user_venue_visits_this_month', { p_user_id: user.id, p_venue_id: venueId }),
    db
      .from('visits')
      .select('checked_in_at')
      .eq('user_id', user.id)
      .eq('venue_id', venueId)
      .in('status', ['granted', 'manual_override'])
      .is('reversed_at', null)
      .order('checked_in_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
    db
      .from('profiles')
      .select('gender, date_of_birth, is_suspended')
      .eq('id', user.id)
      .single(),
  ]);

  // Authoritative distance from PostGIS. A client-supplied distance is a
  // client-supplied lie, so the client's coordinates are the only thing we
  // take from it and the measurement happens here.
  const { data: distanceRows } = await db.rpc('venues_near', {
    p_lat: lat,
    p_lng: lng,
    p_radius_km: 5,
    p_limit: 200,
    p_offset: 0,
  });

  const distanceFromVenueM =
    (distanceRows as Array<{ id: string; distance_km: number }> | null)?.find(
      (row) => row.id === venueId,
    )?.distance_km != null
      ? Math.round(
          (distanceRows as Array<{ id: string; distance_km: number }>).find(
            (row) => row.id === venueId,
          )!.distance_km * 1000,
        )
      : null;

  // A poor GPS fix widens the fence, capped. Basement and mall gyms are
  // common here and refusing a member who is genuinely standing at reception
  // costs more than the marginal fraud it prevents.
  const geofenceRadiusM =
    venue.geofence_radius_m +
    Math.min(accuracyM ?? 0, MAX_ACCURACY_ALLOWANCE_M);

  const minutesSinceLastVisit = lastVisit?.checked_in_at
    ? Math.round((now.getTime() - new Date(lastVisit.checked_in_at).getTime()) / 60_000)
    : null;

  // -------------------------------------------------------------------------
  // Decide.
  // -------------------------------------------------------------------------

  const context: CheckinContext = {
    now,
    member: {
      userId: user.id,
      gender: (profile?.gender as CheckinContext['member']['gender']) ?? null,
      ageBand: entitlement?.age_band ?? 'unknown',
      isSuspended: Boolean(profile?.is_suspended),
    },
    subscription: entitlement
      ? {
          status: entitlement.subscription_status,
          tier: entitlement.tier,
          planCode: entitlement.plan_code,
          currentPeriodEnd: new Date(entitlement.current_period_end),
          pauseStartsAt: entitlement.pause_starts_at
            ? new Date(entitlement.pause_starts_at)
            : null,
          pauseEndsAt: entitlement.pause_ends_at ? new Date(entitlement.pause_ends_at) : null,
          emiratesCovered: entitlement.emirates_covered ?? [],
          defaultVenueMonthlyCap: entitlement.default_venue_monthly_cap,
        }
      : null,
    venue: {
      id: venue.id,
      emirate: venue.emirate,
      status: venue.status,
      tierRequired: venue.tier_required,
      effectiveGenderPolicy:
        (effectivePolicy as CheckinContext['venue']['effectiveGenderPolicy']) ?? 'mixed',
      minAge: venue.min_age,
      checkinCreditCost: venue.checkin_credit_cost,
      aggregatorAccessPaused: venue.aggregator_access_paused,
      sportsPermitExpiresAt: venue.sports_permit_expires_at
        ? new Date(venue.sports_permit_expires_at)
        : null,
      geofenceRadiusM,
    },
    code: {
      signatureValid: Boolean(signatureValid),
      // verify_checkin_code already enforces the accepted window; a false
      // result with a well-formed code is an expiry, not a forgery.
      withinTimeWindow: Boolean(signatureValid),
    },
    location: { distanceFromVenueM },
    caps: {
      venueDailyLimit: caps?.max_daily_checkins ?? null,
      venueCheckinsToday: (checkinsToday as number) ?? 0,
      venueConcurrentLimit: caps?.max_concurrent ?? null,
      venueCurrentlyInside: 0, // populated once check-out is live
      userVenueMonthlyLimit: caps?.max_visits_per_user_monthly ?? null,
      userVenueVisitsThisMonth: (userVisitsThisMonth as number) ?? 0,
      cooldownMinutes: caps?.cooldown_minutes ?? 240,
      minutesSinceLastVisitHere: minutesSinceLastVisit,
    },
    credits: { balance: entitlement?.credit_balance ?? 0 },
    venueState: { inBlackoutWindow: Boolean(inBlackout) },
  };

  const decision = evaluateCheckin(context);

  // -------------------------------------------------------------------------
  // Persist. Denials are recorded too.
  // -------------------------------------------------------------------------

  const visitRow = {
    user_id: user.id,
    venue_id: venue.id,
    status: decision.granted ? 'granted' : 'denied',
    denial_reason: decision.granted ? null : decision.reason,
    method: 'dynamic_qr' as const,
    checked_in_at: now.toISOString(),
    scan_location: `SRID=4326;POINT(${lng} ${lat})`,
    distance_from_venue_m: distanceFromVenueM,
    ip_address: request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? null,
    credits_charged: decision.granted ? decision.creditsToCharge : 0,
    // Frozen at decision time so a later rate change cannot rewrite history.
    cost_to_platform_aed: decision.granted ? venue.cost_per_visit_aed : null,
    entitlement_snapshot: decision.snapshot as unknown as Record<string, unknown>,
  };

  const { data: visit, error: insertError } = await db
    .from('visits')
    .insert(visitRow)
    .select('id')
    .single();

  if (insertError || !visit) {
    return NextResponse.json({ error: 'checkin_write_failed' }, { status: 500 });
  }

  if (!decision.granted) {
    await logAudit(db, {
      actorId: user.id,
      action: 'checkin.denied',
      subjectType: 'visit',
      subjectId: visit.id,
      afterState: { reason: decision.reason, venueId: venue.id },
    });

    return NextResponse.json({
      granted: false,
      visitId: visit.id,
      reason: decision.reason,
      messageKey: decision.messageKey,
      remedy: decision.remedy,
      params: denialParams(decision.reason, context, venue),
    });
  }

  // Credit charge and visit insert are two writes. The idempotency key on the
  // ledger is what makes a mid-flight failure safe to retry: a repeat lands on
  // the unique constraint and the replay path above returns the first result.
  if (decision.creditsToCharge > 0) {
    const { error: ledgerError } = await db.from('credit_ledger').insert({
      user_id: user.id,
      delta: -decision.creditsToCharge,
      reason: 'premium_checkin',
      ref_type: 'visit',
      ref_id: visit.id,
      idempotency_key: idempotencyKey,
    });

    if (ledgerError) {
      // The visit is already written and the member is already through the
      // door. Reversing it here would be worse than an uncharged visit, so
      // flag it for reconciliation rather than failing the request.
      await logAudit(db, {
        actorId: user.id,
        action: 'checkin.credit_charge_failed',
        subjectType: 'visit',
        subjectId: visit.id,
        afterState: { error: ledgerError.message, credits: decision.creditsToCharge },
      });
    }
  } else {
    // Keep the idempotency key even for a zero-credit visit, so the replay
    // path works for the free tiers too.
    await db.from('credit_ledger').insert({
      user_id: user.id,
      delta: 0,
      reason: 'premium_checkin',
      ref_type: 'visit',
      ref_id: visit.id,
      idempotency_key: idempotencyKey,
      notes: 'zero-cost check-in, recorded for idempotency',
    }).select().maybeSingle();
  }

  const monthlyCap = decision.snapshot.venueMonthlyCapApplied;

  return NextResponse.json({
    granted: true,
    visitId: visit.id,
    venueName: venue.name_en,
    venueNameAr: venue.name_ar,
    creditsCharged: decision.creditsToCharge,
    creditsRemaining: context.credits.balance - decision.creditsToCharge,
    visitsUsedHere: context.caps.userVenueVisitsThisMonth + 1,
    visitsAllowedHere: monthlyCap,
    engineVersion: ENGINE_VERSION,
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Interpolation values for the localised denial message. Computed here so the
 * client never has to reconstruct them from a snapshot it should not need to
 * parse.
 */
function denialParams(
  reason: string,
  ctx: CheckinContext,
  venue: VenueRow,
): Record<string, string | number> {
  switch (reason) {
    case 'insufficient_credits':
      return { count: venue.checkin_credit_cost, balance: ctx.credits.balance };
    case 'user_venue_monthly_cap_reached':
      return { count: ctx.caps.userVenueMonthlyLimit ?? ctx.subscription?.defaultVenueMonthlyCap ?? 0 };
    case 'tier_not_covered':
      return { tier: ctx.subscription?.tier ?? 'community' };
    case 'subscription_paused':
      return {
        date: ctx.subscription?.pauseEndsAt?.toISOString().slice(0, 10) ?? '',
      };
    default:
      return {};
  }
}

function replayResponse(visit: {
  id: string;
  status: string;
  denial_reason: string | null;
  credits_charged: number;
  entitlement_snapshot: EntitlementSnapshot;
}) {
  if (visit.status === 'denied') {
    return {
      granted: false,
      visitId: visit.id,
      reason: visit.denial_reason,
      messageKey: `checkin.denied.${visit.denial_reason}`,
      replayed: true,
    };
  }
  return {
    granted: true,
    visitId: visit.id,
    creditsCharged: visit.credits_charged,
    replayed: true,
  };
}
