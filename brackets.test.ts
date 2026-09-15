import { describe, expect, it } from 'vitest';

import {
  generateAmericano,
  generateDraw,
  generateMexicanoRound,
  generateRoundRobin,
  generateSingleElimination,
  kFactor,
  seedOrder,
  updateElo,
  type DrawOptions,
  type Entrant,
} from './brackets';

const opts: DrawOptions = {
  courtLabels: ['Court 1', 'Court 2', 'Court 3', 'Court 4'],
  matchDurationMinutes: 45,
  startsAt: new Date('2026-10-02T04:00:00.000Z'), // 08:00 Dubai, a Friday
  seeding: 'rating',
};

function entrants(n: number): Entrant[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `p${i + 1}`,
    name: `Player ${i + 1}`,
    rating: 2000 - i * 25,
  }));
}

describe('seedOrder', () => {
  it('places the top two seeds on opposite sides of the bracket', () => {
    // Standard bracket order: 1 plays 8, 4 plays 5 on the top half; 2 plays 7,
    // 3 plays 6 on the bottom. Seeds 1 and 2 can only meet in the final.
    expect(seedOrder(4)).toEqual([1, 4, 2, 3]);
    expect(seedOrder(8)).toEqual([1, 8, 4, 5, 2, 7, 3, 6]);
  });

  it('keeps the top two seeds apart until the final at every size', () => {
    for (const size of [4, 8, 16, 32]) {
      const order = seedOrder(size);
      const posOfOne = order.indexOf(1);
      const posOfTwo = order.indexOf(2);
      // Top seed in the first half of the draw, second seed in the other.
      expect(posOfOne < size / 2).toBe(true);
      expect(posOfTwo >= size / 2).toBe(true);
      // Every seed appears exactly once.
      expect(new Set(order).size).toBe(size);
    }
  });
});

describe('generateSingleElimination', () => {
  it('produces a complete bracket for a power of two', () => {
    const matches = generateSingleElimination(entrants(8), opts);
    // 4 + 2 + 1
    expect(matches).toHaveLength(7);
    expect(matches.filter((m) => m.roundNumber === 1)).toHaveLength(4);
    expect(matches.filter((m) => m.roundLabel === 'Final')).toHaveLength(1);
  });

  it('wires every first-round match to a parent', () => {
    const matches = generateSingleElimination(entrants(8), opts);
    for (const m of matches.filter((x) => x.roundNumber === 1)) {
      expect(m.nextMatchIndex).toBeDefined();
      expect([1, 2]).toContain(m.nextMatchSlot);
    }
    const final = matches.find((m) => m.roundLabel === 'Final');
    expect(final?.nextMatchIndex).toBeUndefined();
  });

  it('pads with byes for a non-power-of-two field', () => {
    const matches = generateSingleElimination(entrants(6), opts);
    expect(matches.filter((m) => m.roundNumber === 1)).toHaveLength(4);
    // Two byes for a field of 6 in a bracket of 8.
    expect(matches.filter((m) => m.isBye)).toHaveLength(2);
  });

  it('gives byes to the top seeds, not at random', () => {
    const matches = generateSingleElimination(entrants(5), opts);
    const byes = matches.filter((m) => m.isBye);
    // Top seed p1 must be one of the entrants receiving a bye.
    const byeTeams = byes.flatMap((m) => [m.teamAId, m.teamBId]).filter(Boolean);
    expect(byeTeams).toContain('p1');
  });

  it('assigns courts and times without clashes inside a round', () => {
    const matches = generateSingleElimination(entrants(8), opts);
    const r1 = matches.filter((m) => m.roundNumber === 1 && !m.isBye);
    const slots = r1.map((m) => `${m.courtLabel}@${m.scheduledAt}`);
    expect(new Set(slots).size).toBe(slots.length);
  });

  it('starts later rounds after the earlier ones finish', () => {
    const matches = generateSingleElimination(entrants(8), opts);
    const r1Latest = Math.max(
      ...matches.filter((m) => m.roundNumber === 1).map((m) => Date.parse(m.scheduledAt!)),
    );
    const r2Earliest = Math.min(
      ...matches.filter((m) => m.roundNumber === 2).map((m) => Date.parse(m.scheduledAt!)),
    );
    expect(r2Earliest).toBeGreaterThan(r1Latest);
  });
});

describe('generateRoundRobin', () => {
  it('has every entrant meet every other exactly once', () => {
    const field = entrants(6);
    const matches = generateRoundRobin(field, opts);
    expect(matches).toHaveLength((6 * 5) / 2);

    const pairs = new Set(
      matches.map((m) => [m.teamAId, m.teamBId].sort().join('|')),
    );
    expect(pairs.size).toBe(15);
  });

  it('handles an odd field by giving each entrant one bye round', () => {
    const matches = generateRoundRobin(entrants(5), opts);
    expect(matches).toHaveLength((5 * 4) / 2);
    const rounds = new Set(matches.map((m) => m.roundNumber));
    expect(rounds.size).toBe(5);
  });

  it('never schedules an entrant twice in the same round', () => {
    const matches = generateRoundRobin(entrants(8), opts);
    for (const round of new Set(matches.map((m) => m.roundNumber))) {
      const inRound = matches.filter((m) => m.roundNumber === round);
      const ids = inRound.flatMap((m) => [m.teamAId, m.teamBId]);
      expect(new Set(ids).size).toBe(ids.length);
    }
  });
});

describe('generateAmericano', () => {
  it('refuses a field that is not a multiple of four', () => {
    // Refusing loudly beats silently dropping a paying entrant.
    expect(() => generateAmericano(entrants(6), opts)).toThrow(/multiple of 4/);
    expect(() => generateAmericano(entrants(2), opts)).toThrow();
  });

  it('puts all four players on court in each match', () => {
    const matches = generateAmericano(entrants(8), { ...opts, roundsTotal: 5 });
    for (const m of matches) {
      expect(m.teamAPlayers).toHaveLength(2);
      expect(m.teamBPlayers).toHaveLength(2);
      const all = [...m.teamAPlayers!, ...m.teamBPlayers!];
      expect(new Set(all).size).toBe(4);
    }
  });

  it('gives everyone a game in every round', () => {
    const field = entrants(12);
    const matches = generateAmericano(field, { ...opts, roundsTotal: 4 });
    for (const round of new Set(matches.map((m) => m.roundNumber))) {
      const playing = matches
        .filter((m) => m.roundNumber === round)
        .flatMap((m) => [...m.teamAPlayers!, ...m.teamBPlayers!]);
      expect(new Set(playing).size).toBe(field.length);
    }
  });

  it('rotates partners rather than repeating the same pairing', () => {
    const matches = generateAmericano(entrants(8), { ...opts, roundsTotal: 5 });
    const partnerships = matches.flatMap((m) => [
      m.teamAPlayers!.slice().sort().join('|'),
      m.teamBPlayers!.slice().sort().join('|'),
    ]);
    // Variety is the whole point of the format; at minimum, most pairings
    // across the session should be distinct.
    expect(new Set(partnerships).size).toBeGreaterThan(partnerships.length / 2);
  });
});

describe('generateMexicanoRound', () => {
  const standings = [
    { playerId: 'a', points: 40 },
    { playerId: 'b', points: 35 },
    { playerId: 'c', points: 30 },
    { playerId: 'd', points: 25 },
    { playerId: 'e', points: 20 },
    { playerId: 'f', points: 15 },
    { playerId: 'g', points: 10 },
    { playerId: 'h', points: 5 },
  ];

  it('pairs ranks 1+4 against 2+3 on the top court', () => {
    const [top] = generateMexicanoRound(standings, 2, opts);
    expect(top.teamAPlayers).toEqual(['a', 'd']);
    expect(top.teamBPlayers).toEqual(['b', 'c']);
  });

  it('keeps ability bands together across courts', () => {
    const matches = generateMexicanoRound(standings, 2, opts);
    expect(matches).toHaveLength(2);
    const second = matches[1];
    expect([...second.teamAPlayers!, ...second.teamBPlayers!].sort()).toEqual([
      'e', 'f', 'g', 'h',
    ]);
  });

  it('is deterministic when points tie', () => {
    const tied = standings.map((s) => ({ ...s, points: 10 }));
    const a = generateMexicanoRound(tied, 3, opts);
    const b = generateMexicanoRound(tied, 3, opts);
    expect(a).toEqual(b);
  });

  it('refuses a field that is not a multiple of four', () => {
    expect(() => generateMexicanoRound(standings.slice(0, 6), 2, opts)).toThrow();
  });
});

describe('generateDraw', () => {
  it('routes group_then_knockout into four snake-seeded groups', () => {
    const matches = generateDraw('group_then_knockout', entrants(16), opts);
    const groups = new Set(matches.map((m) => m.groupLabel));
    expect(groups).toEqual(new Set(['Group A', 'Group B', 'Group C', 'Group D']));
  });

  it('refuses to pre-generate a ladder', () => {
    expect(() => generateDraw('ladder', entrants(8), opts)).toThrow(/challenge-driven/);
  });
});

describe('updateElo', () => {
  it('moves both ratings by the same magnitude with equal K', () => {
    const { ratingA, ratingB } = updateElo(1500, 1500, 1);
    expect(ratingA).toBeCloseTo(1516, 0);
    expect(ratingB).toBeCloseTo(1484, 0);
    expect(ratingA - 1500).toBeCloseTo(1500 - ratingB, 5);
  });

  it('rewards an upset more than an expected win', () => {
    const upset = updateElo(1400, 1800, 1);
    const expected = updateElo(1800, 1400, 1);
    expect(upset.ratingA - 1400).toBeGreaterThan(expected.ratingA - 1800);
  });

  it('leaves evenly matched players unchanged on a draw', () => {
    const { ratingA, ratingB } = updateElo(1600, 1600, 0.5);
    expect(ratingA).toBe(1600);
    expect(ratingB).toBe(1600);
  });

  it('widens K for provisional players so they converge fast', () => {
    expect(kFactor(0)).toBe(64);
    expect(kFactor(15)).toBe(40);
    expect(kFactor(100)).toBe(24);
  });
});
