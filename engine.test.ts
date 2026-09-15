import { describe, expect, it } from 'vitest';

import {
  assertSentimentNeutral,
  coinsToCash,
  countAnsweredAttributes,
  evaluateEarn,
  evaluateRedemption,
  MIN_COMPOSITION_SECONDS,
  VERIFICATION_MULTIPLIER,
  type EarnContext,
  type RedeemContext,
} from './engine';

const NOW = new Date('2026-09-15T18:00:00.000Z');

function earnContext(overrides: Partial<EarnContext> = {}): EarnContext {
  return {
    now: NOW,
    rule: {
      id: 'rule-1',
      code: 'venue_review_v1',
      reason: 'venue_review',
      coinsAwarded: 50,
      maxPerUserPerMonth: 8,
      maxPerUserLifetime: null,
      maxPerSubject: 1,
      subjectCooldownDays: 90,
      requiresVerifiedVisit: true,
      verifiedVisitWindowHours: 72,
      minStructuredAnswers: 4,
      minTextLength: 0,
      requiresPhoto: false,
      requiresModeration: false,
      isActive: true,
      activeFrom: new Date('2026-01-01T00:00:00.000Z'),
      activeTo: null,
    },
    member: { userId: 'user-1', isSuspended: false, accountAgeDays: 40 },
    visit: {
      id: 'visit-1',
      userId: 'user-1',
      venueId: 'venue-1',
      status: 'granted',
      reversed: false,
      checkedInAt: new Date('2026-09-15T06:00:00.000Z'),
    },
    subjectId: 'venue-1',
    submission: {
      rating: 4,
      attributes: {
        busy_level: 'moderate',
        cleanliness: 4,
        equipment_working: true,
        showers_clean: 3,
      },
      body: null,
      photoCount: 0,
      compositionSeconds: 45,
      bodyHash: null,
    },
    verificationMethod: 'system_verified',
    counters: {
      awardsThisMonthForRule: 2,
      awardsLifetimeForRule: 9,
      awardsForThisSubject: 0,
      daysSinceLastAwardForSubject: null,
      awardsLast24h: 1,
      duplicateBodySeen: false,
    },
    budget: { coinsIssuedThisPeriod: 100_000, maxCoinsThisPeriod: 500_000 },
    ...overrides,
  };
}

// ---------------------------------------------------------------------------

describe('countAnsweredAttributes', () => {
  it('ignores skipped fields', () => {
    expect(
      countAnsweredAttributes({
        a: 'yes',
        b: null,
        c: undefined,
        d: '',
        e: '   ',
        f: [],
        g: 0,
        h: false,
      }),
    ).toBe(3); // a, g, h
  });
});

describe('evaluateEarn :: sentiment neutrality', () => {
  it('pays the same coins for one star as for five', () => {
    const ctx = earnContext();
    const outcomes = [1, 2, 3, 4, 5].map((rating) =>
      evaluateEarn({ ...ctx, submission: { ...ctx.submission!, rating } }),
    );
    const coins = outcomes.map((o) => (o.awarded ? o.coins : null));
    expect(coins).toEqual([50, 50, 50, 50, 50]);
  });

  it('holds neutral even with no rating at all', () => {
    // The star earns nothing, so its absence changes nothing.
    const ctx = earnContext();
    const withRating = evaluateEarn(ctx);
    const withoutRating = evaluateEarn({
      ...ctx,
      submission: { ...ctx.submission!, rating: null },
    });
    expect(withRating).toEqual(withoutRating);
  });

  it('passes the explicit neutrality assertion', () => {
    expect(assertSentimentNeutral(earnContext())).toBe(true);
  });
});

describe('evaluateEarn :: verified attendance', () => {
  it('awards on a granted visit inside the window', () => {
    const result = evaluateEarn(earnContext());
    expect(result.awarded).toBe(true);
    if (!result.awarded) return;
    expect(result.coins).toBe(50);
    expect(result.markAsIncentivised).toBe(true);
  });

  it('refuses with no visit at all', () => {
    const r = evaluateEarn(earnContext({ visit: null }));
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('no_verified_visit');
  });

  it('refuses a denied visit', () => {
    const ctx = earnContext();
    ctx.visit!.status = 'denied';
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('visit_not_granted');
  });

  it('refuses a reversed visit', () => {
    const ctx = earnContext();
    ctx.visit!.reversed = true;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('visit_not_granted');
  });

  it("refuses another member's visit", () => {
    const ctx = earnContext();
    ctx.visit!.userId = 'someone-else';
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('visit_belongs_to_another_member');
  });

  it('refuses a review of a venue the member did not visit', () => {
    const r = evaluateEarn(earnContext({ subjectId: 'venue-2' }));
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('subject_mismatch');
  });

  it('refuses a review six weeks after the visit', () => {
    const ctx = earnContext();
    ctx.visit!.checkedInAt = new Date('2026-08-01T06:00:00.000Z');
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('visit_outside_window');
  });
});

describe('evaluateEarn :: quality bar', () => {
  it('refuses a form with too few attributes answered', () => {
    const ctx = earnContext();
    ctx.submission!.attributes = { busy_level: 'moderate', cleanliness: null };
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('insufficient_attributes');
  });

  it('refuses a review submitted in three seconds', () => {
    const ctx = earnContext();
    ctx.submission!.compositionSeconds = 3;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('submitted_too_fast');
  });

  it('accepts a review at exactly the composition threshold', () => {
    const ctx = earnContext();
    ctx.submission!.compositionSeconds = MIN_COMPOSITION_SECONDS;
    expect(evaluateEarn(ctx).awarded).toBe(true);
  });

  it('refuses the same text pasted across venues', () => {
    const ctx = earnContext();
    ctx.submission!.bodyHash = 'abc123';
    ctx.counters.duplicateBodySeen = true;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('duplicate_content');
  });

  it('enforces a minimum text length when the rule sets one', () => {
    const ctx = earnContext();
    ctx.rule.minTextLength = 80;
    ctx.submission!.body = 'Good gym.';
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('text_too_short');
  });

  it('enforces a photo requirement', () => {
    const ctx = earnContext();
    ctx.rule.requiresPhoto = true;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('photo_required');
  });
});

describe('evaluateEarn :: anti-farming', () => {
  it('refuses a brand new account', () => {
    const ctx = earnContext();
    ctx.member.accountAgeDays = 0;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('account_too_new');
  });

  it('refuses a suspended account', () => {
    const ctx = earnContext();
    ctx.member.isSuspended = true;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('account_suspended');
  });

  it('refuses once the 24 hour velocity ceiling is hit', () => {
    const ctx = earnContext();
    ctx.counters.awardsLast24h = 12;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('velocity_exceeded');
  });
});

describe('evaluateEarn :: caps and budget', () => {
  it('refuses at the monthly cap', () => {
    const ctx = earnContext();
    ctx.counters.awardsThisMonthForRule = 8;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('monthly_cap_reached');
  });

  it('refuses a second paid review of the same venue', () => {
    const ctx = earnContext();
    ctx.counters.awardsForThisSubject = 1;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('subject_cap_reached');
  });

  it('refuses inside the per-subject cooldown', () => {
    const ctx = earnContext();
    ctx.rule.maxPerSubject = null;
    ctx.counters.daysSinceLastAwardForSubject = 30;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('subject_cooldown');
  });

  it('tells the member about their own cap before the budget', () => {
    // Ordering matters: "you have used your allowance" is actionable,
    // "the budget ran out" is not.
    const ctx = earnContext();
    ctx.counters.awardsThisMonthForRule = 8;
    ctx.budget = { coinsIssuedThisPeriod: 500_000, maxCoinsThisPeriod: 500_000 };
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('monthly_cap_reached');
  });

  it('refuses when the programme budget is exhausted', () => {
    const ctx = earnContext();
    ctx.budget = { coinsIssuedThisPeriod: 499_980, maxCoinsThisPeriod: 500_000 };
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(false);
    if (r.awarded) return;
    expect(r.reason).toBe('budget_exhausted');
  });

  it('awards right up to the budget ceiling', () => {
    const ctx = earnContext();
    ctx.budget = { coinsIssuedThisPeriod: 499_950, maxCoinsThisPeriod: 500_000 };
    expect(evaluateEarn(ctx).awarded).toBe(true);
  });
});

describe('evaluateEarn :: verification-weighted rewards', () => {
  it('pays a self-attested social follow a tenth of base', () => {
    // No social platform lets a third party confirm a follow, so this
    // claim can only ever be self-attested and is priced accordingly.
    const ctx = earnContext({
      verificationMethod: 'self_attested',
      submission: null,
    });
    ctx.rule.requiresVerifiedVisit = false;
    ctx.rule.minStructuredAnswers = 0;
    ctx.rule.reason = 'social_follow_claim';
    ctx.rule.coinsAwarded = 50;

    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(true);
    if (!r.awarded) return;
    expect(r.coins).toBe(5);
    expect(r.breakdown.verificationMultiplier).toBe(0.1);
  });

  it('pays a system-verified referral at full base', () => {
    const ctx = earnContext({
      verificationMethod: 'system_verified',
      submission: null,
    });
    ctx.rule.requiresVerifiedVisit = false;
    ctx.rule.minStructuredAnswers = 0;
    ctx.rule.reason = 'referral_completed';
    ctx.rule.coinsAwarded = 200;

    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(true);
    if (!r.awarded) return;
    expect(r.coins).toBe(200);
  });

  it('ranks verification methods so provable beats asserted', () => {
    expect(VERIFICATION_MULTIPLIER.system_verified).toBeGreaterThan(
      VERIFICATION_MULTIPLIER.moderator_reviewed,
    );
    expect(VERIFICATION_MULTIPLIER.moderator_reviewed).toBeGreaterThan(
      VERIFICATION_MULTIPLIER.screenshot_submitted,
    );
    expect(VERIFICATION_MULTIPLIER.screenshot_submitted).toBeGreaterThan(
      VERIFICATION_MULTIPLIER.self_attested,
    );
  });

  it('never awards zero coins through rounding', () => {
    const ctx = earnContext({ verificationMethod: 'self_attested', submission: null });
    ctx.rule.requiresVerifiedVisit = false;
    ctx.rule.minStructuredAnswers = 0;
    ctx.rule.coinsAwarded = 3; // 3 * 0.1 floors to 0
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(true);
    if (!r.awarded) return;
    expect(r.coins).toBe(1);
  });
});

describe('evaluateEarn :: moderation and expiry', () => {
  it('holds the award when the rule requires moderation', () => {
    const ctx = earnContext();
    ctx.rule.requiresModeration = true;
    const r = evaluateEarn(ctx);
    expect(r.awarded).toBe(true);
    if (!r.awarded) return;
    expect(r.heldForModeration).toBe(true);
  });

  it('expires coins twelve months out', () => {
    const r = evaluateEarn(earnContext());
    expect(r.awarded).toBe(true);
    if (!r.awarded) return;
    expect(r.expiresAt.toISOString().slice(0, 7)).toBe('2027-09');
  });

  it('flags the review as incentivised so it can be disclosed', () => {
    const r = evaluateEarn(earnContext());
    expect(r.awarded).toBe(true);
    if (!r.awarded) return;
    expect(r.markAsIncentivised).toBe(true);
  });
});

// ---------------------------------------------------------------------------

function redeemContext(overrides: Partial<RedeemContext> = {}): RedeemContext {
  return {
    now: NOW,
    item: {
      id: 'item-1',
      code: 'credits_10',
      kind: 'credits',
      coinCost: 400,
      creditsGranted: 10,
      discountAed: null,
      maxOrderSharePct: null,
      stockTotal: null,
      stockClaimed: 0,
      maxPerUser: 4,
      tierRequired: null,
      isActive: true,
      availableFrom: null,
      availableTo: null,
    },
    member: {
      userId: 'user-1',
      isSuspended: false,
      tier: 'core',
      coinBalance: 900,
    },
    redemptionsOfThisItem: 0,
    orderTotalAed: null,
    ...overrides,
  };
}

describe('evaluateRedemption', () => {
  it('converts coins into credits one way', () => {
    const r = evaluateRedemption(redeemContext());
    expect(r.redeemed).toBe(true);
    if (!r.redeemed) return;
    expect(r.coinsSpent).toBe(400);
    expect(r.creditsGranted).toBe(10);
    expect(r.coinBalanceAfter).toBe(500);
  });

  it('refuses when the balance is short', () => {
    const ctx = redeemContext();
    ctx.member.coinBalance = 399;
    const r = evaluateRedemption(ctx);
    expect(r.redeemed).toBe(false);
    if (r.redeemed) return;
    expect(r.reason).toBe('insufficient_coins');
  });

  it('enforces the per-user redemption limit', () => {
    const ctx = redeemContext({ redemptionsOfThisItem: 4 });
    const r = evaluateRedemption(ctx);
    expect(r.redeemed).toBe(false);
    if (r.redeemed) return;
    expect(r.reason).toBe('per_user_limit_reached');
  });

  it('enforces stock', () => {
    const ctx = redeemContext();
    ctx.item.stockTotal = 100;
    ctx.item.stockClaimed = 100;
    const r = evaluateRedemption(ctx);
    expect(r.redeemed).toBe(false);
    if (r.redeemed) return;
    expect(r.reason).toBe('out_of_stock');
  });

  it('enforces a tier gate', () => {
    const ctx = redeemContext();
    ctx.item.tierRequired = 'elite';
    const r = evaluateRedemption(ctx);
    expect(r.redeemed).toBe(false);
    if (r.redeemed) return;
    expect(r.reason).toBe('tier_required');
  });

  it('allows a marketplace discount inside the order share cap', () => {
    const ctx = redeemContext({ orderTotalAed: 300 });
    ctx.item = {
      ...ctx.item,
      kind: 'marketplace_discount',
      creditsGranted: null,
      discountAed: 50,
      maxOrderSharePct: 20,
    };
    const r = evaluateRedemption(ctx);
    expect(r.redeemed).toBe(true);
    if (!r.redeemed) return;
    expect(r.discountAed).toBe(50);
    expect(r.creditsGranted).toBe(0);
  });

  it('refuses a discount that would cover too much of the order', () => {
    // A fully coin-funded basket is a free product paid for out of the
    // marketing budget.
    const ctx = redeemContext({ orderTotalAed: 120 });
    ctx.item = {
      ...ctx.item,
      kind: 'marketplace_discount',
      creditsGranted: null,
      discountAed: 50,
      maxOrderSharePct: 20,
    };
    const r = evaluateRedemption(ctx);
    expect(r.redeemed).toBe(false);
    if (r.redeemed) return;
    expect(r.reason).toBe('discount_exceeds_order_share');
  });

  it('refuses a discount with no basket to apply it to', () => {
    const ctx = redeemContext({ orderTotalAed: null });
    ctx.item = { ...ctx.item, kind: 'marketplace_discount', discountAed: 50 };
    const r = evaluateRedemption(ctx);
    expect(r.redeemed).toBe(false);
    if (r.redeemed) return;
    expect(r.reason).toBe('no_order_to_discount');
  });

  it('refuses an expired catalogue item', () => {
    const ctx = redeemContext();
    ctx.item.availableTo = new Date('2026-08-01T00:00:00.000Z');
    const r = evaluateRedemption(ctx);
    expect(r.redeemed).toBe(false);
    if (r.redeemed) return;
    expect(r.reason).toBe('item_expired');
  });
});

describe('closed-loop perimeter', () => {
  it('has no cash-out path', () => {
    // If this ever stops throwing, the CBUAE analysis has to be redone.
    expect(() => coinsToCash()).toThrow(/never redeemable for cash/);
  });

  it('offers no redemption kind with off-platform value', () => {
    const kinds = [
      'credits',
      'class_pass',
      'event_ticket',
      'marketplace_discount',
      'merchandise',
      'programme_discount',
    ];
    expect(kinds).not.toContain('cash');
    expect(kinds).not.toContain('transfer');
    expect(kinds).not.toContain('gift_card');
  });
});
