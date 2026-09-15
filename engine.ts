/**
 * NABD :: rewards engine
 *
 * Pure. Same discipline as the entitlement engine: no I/O, fully testable,
 * and the only place that decides whether a coin is awarded or spent.
 *
 * Three invariants are enforced here rather than left to policy, because
 * each one fails silently and expensively if it drifts.
 *
 * 1. SENTIMENT NEUTRALITY. A review earns the same coins whether it is one
 *    star or five. The moment a positive review pays better than a negative
 *    one, the rating data stops describing reality, and the discovery
 *    ranking that the entire product depends on becomes noise. The star
 *    rating earns nothing at all; the structured attributes earn the coins.
 *
 * 2. VERIFIED ATTENDANCE. Coins for a review require a granted, unreversed
 *    visit inside a window. Without this, the cheapest way to farm coins is
 *    to review venues you have never entered.
 *
 * 3. BUDGET CEILING. Every award is checked against a per-user cap, a
 *    per-subject cap and a programme budget. A rewards programme without a
 *    ceiling is an unbounded liability.
 *
 * Coins are NOT credits. See the header of migration 0011. Coins convert
 * into credits at redemption; credits never convert back.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type CoinEarnReason =
  | 'venue_review'
  | 'class_review'
  | 'event_review'
  | 'photo_upload'
  | 'attribute_correction'
  | 'first_checkin_at_venue'
  | 'checkin_streak'
  | 'meet_attendance'
  | 'referral_completed'
  | 'social_follow_claim'
  | 'ugc_post_verified'
  | 'profile_completed'
  | 'challenge_completed'
  | 'survey_completed';

/**
 * How much the platform can actually prove about a claim. Reward size must
 * track this, because a self-attested claim is worth roughly what it costs
 * to fake.
 */
export type VerificationMethod =
  | 'system_verified'
  | 'partner_confirmed'
  | 'moderator_reviewed'
  | 'screenshot_submitted'
  | 'self_attested';

/**
 * Ceiling on what each verification level may pay, as a multiple of the
 * base rule value.
 *
 * The honest constraint behind this table: no social platform exposes
 * "does user X follow page Y" to a third party, so a follow claim can only
 * ever be self-attested and is trivially farmed. It is capped at a tenth of
 * base for that reason. The marketing mechanics that carry real reward are
 * the ones the platform can verify end to end: a referral whose referred
 * member actually checked in, and user content the venue itself confirms.
 */
export const VERIFICATION_MULTIPLIER: Record<VerificationMethod, number> = {
  system_verified: 1,
  partner_confirmed: 1,
  moderator_reviewed: 0.75,
  screenshot_submitted: 0.35,
  self_attested: 0.1,
};

export interface EarnRule {
  id: string;
  code: string;
  reason: CoinEarnReason;
  coinsAwarded: number;
  maxPerUserPerMonth: number | null;
  maxPerUserLifetime: number | null;
  maxPerSubject: number | null;
  subjectCooldownDays: number | null;
  requiresVerifiedVisit: boolean;
  verifiedVisitWindowHours: number;
  minStructuredAnswers: number;
  minTextLength: number;
  requiresPhoto: boolean;
  requiresModeration: boolean;
  isActive: boolean;
  activeFrom: Date;
  activeTo: Date | null;
}

export interface ReviewSubmission {
  /** Earns nothing. Present so the engine can assert that fact. */
  rating: number | null;
  /** The part that earns. Keys are the venue attributes answered. */
  attributes: Record<string, unknown>;
  body: string | null;
  photoCount: number;
  /** Seconds between opening and submitting. A three-second review is not
   *  a review. */
  compositionSeconds: number;
  /** Normalised hash of the body, for duplicate detection. */
  bodyHash: string | null;
}

export interface EarnContext {
  now: Date;
  rule: EarnRule;
  member: {
    userId: string;
    isSuspended: boolean;
    accountAgeDays: number;
  };
  /** Attendance evidence, when the rule requires it. */
  visit: {
    id: string;
    userId: string;
    venueId: string;
    status: 'granted' | 'denied' | 'manual_override' | 'reversed';
    reversed: boolean;
    checkedInAt: Date;
  } | null;
  subjectId: string;
  submission: ReviewSubmission | null;
  verificationMethod: VerificationMethod;
  counters: {
    awardsThisMonthForRule: number;
    awardsLifetimeForRule: number;
    awardsForThisSubject: number;
    daysSinceLastAwardForSubject: number | null;
    /** Awards across all rules in the last 24h. Velocity guard. */
    awardsLast24h: number;
    /** True when this exact body text has been submitted before. */
    duplicateBodySeen: boolean;
  };
  budget: {
    coinsIssuedThisPeriod: number;
    maxCoinsThisPeriod: number;
  };
}

export type EarnRefusalReason =
  | 'rule_inactive'
  | 'account_suspended'
  | 'account_too_new'
  | 'no_verified_visit'
  | 'visit_not_granted'
  | 'visit_belongs_to_another_member'
  | 'visit_outside_window'
  | 'subject_mismatch'
  | 'insufficient_attributes'
  | 'text_too_short'
  | 'photo_required'
  | 'submitted_too_fast'
  | 'duplicate_content'
  | 'velocity_exceeded'
  | 'monthly_cap_reached'
  | 'lifetime_cap_reached'
  | 'subject_cap_reached'
  | 'subject_cooldown'
  | 'budget_exhausted';

export interface EarnGranted {
  awarded: true;
  coins: number;
  /** True when the award is written but withheld until moderation clears. */
  heldForModeration: boolean;
  /** Coins expire. An unexpiring balance only ever grows. */
  expiresAt: Date;
  /** Set on the review row; drives the mandatory public disclosure label. */
  markAsIncentivised: boolean;
  breakdown: {
    baseCoins: number;
    verificationMultiplier: number;
    appliedMultiplier: VerificationMethod;
  };
}

export interface EarnRefused {
  awarded: false;
  reason: EarnRefusalReason;
  messageKey: string;
}

export type EarnDecision = EarnGranted | EarnRefused;

export const REWARDS_ENGINE_VERSION = '1.0.0';

/** Coins expire twelve months after they are earned. */
export const COIN_LIFETIME_MONTHS = 12;

/** A review composed in under this many seconds is not a review. */
export const MIN_COMPOSITION_SECONDS = 15;

/** Accounts younger than this cannot earn. Blocks throwaway-account farming. */
export const MIN_ACCOUNT_AGE_DAYS = 2;

/** Ceiling on awards in a rolling 24 hours, across all rules. */
export const MAX_AWARDS_PER_24H = 12;

// ---------------------------------------------------------------------------
// Attribute counting
// ---------------------------------------------------------------------------

/**
 * Counts substantively answered attributes. Null, undefined, empty string
 * and empty array do not count: a form submitted with every field skipped
 * is not data, and paying for it teaches members to skip every field.
 */
export function countAnsweredAttributes(attributes: Record<string, unknown>): number {
  return Object.values(attributes).filter((v) => {
    if (v === null || v === undefined) return false;
    if (typeof v === 'string') return v.trim().length > 0;
    if (Array.isArray(v)) return v.length > 0;
    return true;
  }).length;
}

// ---------------------------------------------------------------------------
// The engine
// ---------------------------------------------------------------------------

export function evaluateEarn(ctx: EarnContext): EarnDecision {
  const refuse = (reason: EarnRefusalReason): EarnRefused => ({
    awarded: false,
    reason,
    messageKey: `rewards.refused.${reason}`,
  });

  const { rule, member, counters, submission } = ctx;

  // -- Rule availability -----------------------------------------------------
  if (!rule.isActive) return refuse('rule_inactive');
  if (ctx.now < rule.activeFrom) return refuse('rule_inactive');
  if (rule.activeTo && ctx.now > rule.activeTo) return refuse('rule_inactive');

  // -- Account standing ------------------------------------------------------
  if (member.isSuspended) return refuse('account_suspended');
  if (member.accountAgeDays < MIN_ACCOUNT_AGE_DAYS) return refuse('account_too_new');

  // -- Attendance ------------------------------------------------------------
  // The rule that makes a review verified rather than merely asserted.
  if (rule.requiresVerifiedVisit) {
    if (!ctx.visit) return refuse('no_verified_visit');
    if (ctx.visit.userId !== member.userId) {
      return refuse('visit_belongs_to_another_member');
    }
    if (
      ctx.visit.reversed ||
      (ctx.visit.status !== 'granted' && ctx.visit.status !== 'manual_override')
    ) {
      return refuse('visit_not_granted');
    }
    if (ctx.visit.venueId !== ctx.subjectId) return refuse('subject_mismatch');

    const hoursSince =
      (ctx.now.getTime() - ctx.visit.checkedInAt.getTime()) / 3_600_000;
    // A review six weeks after the session is not a review of the session.
    if (hoursSince > rule.verifiedVisitWindowHours) return refuse('visit_outside_window');
    if (hoursSince < 0) return refuse('visit_outside_window');
  }

  // -- Quality bar -----------------------------------------------------------
  if (submission) {
    const answered = countAnsweredAttributes(submission.attributes);
    if (answered < rule.minStructuredAnswers) return refuse('insufficient_attributes');

    const bodyLength = submission.body?.trim().length ?? 0;
    if (bodyLength < rule.minTextLength) return refuse('text_too_short');

    if (rule.requiresPhoto && submission.photoCount < 1) return refuse('photo_required');

    if (submission.compositionSeconds < MIN_COMPOSITION_SECONDS) {
      return refuse('submitted_too_fast');
    }
    // The same paragraph pasted across twenty venues.
    if (submission.bodyHash && counters.duplicateBodySeen) {
      return refuse('duplicate_content');
    }
  } else if (rule.minStructuredAnswers > 0 || rule.minTextLength > 0) {
    // The rule demands content and none was supplied.
    return refuse('insufficient_attributes');
  }

  // -- Velocity --------------------------------------------------------------
  if (counters.awardsLast24h >= MAX_AWARDS_PER_24H) return refuse('velocity_exceeded');

  // -- Caps ------------------------------------------------------------------
  // Member-specific caps first, so a member who has exhausted their own
  // allowance hears that rather than "the budget ran out".
  if (
    rule.maxPerUserPerMonth !== null &&
    counters.awardsThisMonthForRule >= rule.maxPerUserPerMonth
  ) {
    return refuse('monthly_cap_reached');
  }
  if (
    rule.maxPerUserLifetime !== null &&
    counters.awardsLifetimeForRule >= rule.maxPerUserLifetime
  ) {
    return refuse('lifetime_cap_reached');
  }
  if (rule.maxPerSubject !== null && counters.awardsForThisSubject >= rule.maxPerSubject) {
    return refuse('subject_cap_reached');
  }
  if (
    rule.subjectCooldownDays !== null &&
    counters.daysSinceLastAwardForSubject !== null &&
    counters.daysSinceLastAwardForSubject < rule.subjectCooldownDays
  ) {
    return refuse('subject_cooldown');
  }

  // -- Budget ----------------------------------------------------------------
  const multiplier = VERIFICATION_MULTIPLIER[ctx.verificationMethod];
  const coins = Math.max(1, Math.floor(rule.coinsAwarded * multiplier));

  if (ctx.budget.coinsIssuedThisPeriod + coins > ctx.budget.maxCoinsThisPeriod) {
    return refuse('budget_exhausted');
  }

  const expiresAt = new Date(ctx.now);
  expiresAt.setMonth(expiresAt.getMonth() + COIN_LIFETIME_MONTHS);

  return {
    awarded: true,
    coins,
    heldForModeration: rule.requiresModeration,
    expiresAt,
    // Any review the member was paid for must carry a visible disclosure.
    markAsIncentivised: submission !== null,
    breakdown: {
      baseCoins: rule.coinsAwarded,
      verificationMultiplier: multiplier,
      appliedMultiplier: ctx.verificationMethod,
    },
  };
}

/**
 * The sentiment-neutrality invariant, expressed as a callable assertion so
 * it can be exercised in tests and, if anyone ever adds a sentiment term to
 * the engine, fail loudly rather than quietly skew the dataset.
 */
export function assertSentimentNeutral(ctx: EarnContext): boolean {
  if (!ctx.submission) return true;
  const ratings = [1, 2, 3, 4, 5];
  const outcomes = ratings.map((rating) =>
    evaluateEarn({
      ...ctx,
      submission: { ...ctx.submission!, rating },
    }),
  );
  const coinValues = outcomes.map((o) => (o.awarded ? o.coins : -1));
  return new Set(coinValues).size === 1;
}

// ---------------------------------------------------------------------------
// Redemption
// ---------------------------------------------------------------------------

export type RedemptionKind =
  | 'credits'
  | 'class_pass'
  | 'event_ticket'
  | 'marketplace_discount'
  | 'merchandise'
  | 'programme_discount';

export interface RedemptionItem {
  id: string;
  code: string;
  kind: RedemptionKind;
  coinCost: number;
  creditsGranted: number | null;
  discountAed: number | null;
  /** Cap on how much of an order coins may cover. A fully coin-funded
   *  order is a free product paid for out of the marketing budget. */
  maxOrderSharePct: number | null;
  stockTotal: number | null;
  stockClaimed: number;
  maxPerUser: number;
  tierRequired: 'community' | 'core' | 'elite' | null;
  isActive: boolean;
  availableFrom: Date | null;
  availableTo: Date | null;
}

export interface RedeemContext {
  now: Date;
  item: RedemptionItem;
  member: {
    userId: string;
    isSuspended: boolean;
    tier: 'community' | 'core' | 'elite';
    coinBalance: number;
  };
  redemptionsOfThisItem: number;
  /** Order value, when redeeming a discount against a basket. */
  orderTotalAed: number | null;
}

export type RedeemRefusalReason =
  | 'item_inactive'
  | 'item_not_yet_available'
  | 'item_expired'
  | 'account_suspended'
  | 'insufficient_coins'
  | 'out_of_stock'
  | 'per_user_limit_reached'
  | 'tier_required'
  | 'no_order_to_discount'
  | 'discount_exceeds_order_share';

export interface RedeemGranted {
  redeemed: true;
  coinsSpent: number;
  creditsGranted: number;
  discountAed: number;
  coinBalanceAfter: number;
}

export interface RedeemRefused {
  redeemed: false;
  reason: RedeemRefusalReason;
  messageKey: string;
}

export type RedeemDecision = RedeemGranted | RedeemRefused;

const TIER_RANK = { community: 0, core: 1, elite: 2 } as const;

export function evaluateRedemption(ctx: RedeemContext): RedeemDecision {
  const refuse = (reason: RedeemRefusalReason): RedeemRefused => ({
    redeemed: false,
    reason,
    messageKey: `rewards.redeem.refused.${reason}`,
  });

  const { item, member } = ctx;

  if (!item.isActive) return refuse('item_inactive');
  if (item.availableFrom && ctx.now < item.availableFrom) {
    return refuse('item_not_yet_available');
  }
  if (item.availableTo && ctx.now > item.availableTo) return refuse('item_expired');

  if (member.isSuspended) return refuse('account_suspended');

  if (item.tierRequired && TIER_RANK[member.tier] < TIER_RANK[item.tierRequired]) {
    return refuse('tier_required');
  }

  if (item.stockTotal !== null && item.stockClaimed >= item.stockTotal) {
    return refuse('out_of_stock');
  }
  if (ctx.redemptionsOfThisItem >= item.maxPerUser) {
    return refuse('per_user_limit_reached');
  }

  if (member.coinBalance < item.coinCost) return refuse('insufficient_coins');

  let discountAed = 0;

  if (item.kind === 'marketplace_discount' || item.kind === 'programme_discount') {
    if (ctx.orderTotalAed === null || ctx.orderTotalAed <= 0) {
      return refuse('no_order_to_discount');
    }
    discountAed = item.discountAed ?? 0;

    // Never let coins cover the whole basket.
    if (item.maxOrderSharePct !== null) {
      const ceiling = (ctx.orderTotalAed * item.maxOrderSharePct) / 100;
      if (discountAed > ceiling) return refuse('discount_exceeds_order_share');
    }
  }

  return {
    redeemed: true,
    coinsSpent: item.coinCost,
    // The one-way bridge between the two ledgers.
    creditsGranted: item.kind === 'credits' ? (item.creditsGranted ?? 0) : 0,
    discountAed,
    coinBalanceAfter: member.coinBalance - item.coinCost,
  };
}

/**
 * Coins never convert to cash and never move between members. Exposed as a
 * named function so the constraint is greppable: if anything ever needs
 * this to return a number, the closed-loop perimeter has been broken and
 * the CBUAE Stored Value Facilities analysis has to be redone first.
 */
export function coinsToCash(): never {
  throw new Error(
    'Coins are a closed-loop loyalty balance. They are never redeemable for cash, ' +
      'in whole or in part, and are never transferable between members. Changing this ' +
      'moves the programme into the CBUAE Stored Value Facilities perimeter and requires ' +
      'a licensing review before any code change.',
  );
}
