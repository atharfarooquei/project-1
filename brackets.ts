/**
 * NABD :: tournament draw generation
 *
 * Pure functions. No I/O, no database, fully unit-testable.
 *
 * Americano and Mexicano are here because they, not knockout brackets, are
 * what UAE padel clubs actually run socially. A tournament that runs itself
 * is the strongest venue-acquisition tool the product has: the venue gets
 * court revenue and footfall, we get the relationship, and the relationship
 * is what makes the access deal signable later.
 */

import type { TournamentFormat } from '../types/domain';

export interface Entrant {
  id: string;
  name: string;
  /** Elo-style rating used for seeding. Unrated entrants sort last. */
  rating?: number;
}

export interface GeneratedMatch {
  roundNumber: number;
  roundLabel: string;
  bracketPosition: number;
  groupLabel?: string;
  /** For fixed-team formats. */
  teamAId?: string | null;
  teamBId?: string | null;
  /** For rotating-partner formats (Americano, Mexicano), pairings are per
   *  match rather than per team. */
  teamAPlayers?: string[];
  teamBPlayers?: string[];
  courtLabel?: string;
  scheduledAt?: string;
  /** Knockout progression: index into the generated array. */
  nextMatchIndex?: number;
  nextMatchSlot?: 1 | 2;
  isBye?: boolean;
}

export interface DrawOptions {
  courtLabels: string[];
  matchDurationMinutes: number;
  startsAt: Date;
  /** Americano / Mexicano: how many rounds to play. */
  roundsTotal?: number;
  seeding?: 'rating' | 'random' | 'manual';
  /** Deterministic shuffling, so a draw can be reproduced in a dispute. */
  randomSeed?: number;
}

// ---------------------------------------------------------------------------
// Deterministic PRNG. A draw that cannot be reproduced cannot be defended
// when a player claims it was rigged, and in a paid tournament someone
// eventually will.
// ---------------------------------------------------------------------------

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function seededShuffle<T>(items: T[], seed: number): T[] {
  const rng = mulberry32(seed);
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

export function seedEntrants(entrants: Entrant[], opts: DrawOptions): Entrant[] {
  if (opts.seeding === 'manual') return entrants;
  if (opts.seeding === 'random') return seededShuffle(entrants, opts.randomSeed ?? 1);
  // Rating seeding: highest first, unrated last, ties broken by id so the
  // result is stable across runs.
  return [...entrants].sort((a, b) => {
    const ra = a.rating ?? -Infinity;
    const rb = b.rating ?? -Infinity;
    if (rb !== ra) return rb - ra;
    return a.id.localeCompare(b.id);
  });
}

// ---------------------------------------------------------------------------
// Court and time assignment
// ---------------------------------------------------------------------------

/**
 * Spreads matches across the available courts round by round. Matches inside
 * a round run concurrently; the next round starts after the slowest court.
 * This matches how a club with four courts actually runs a Friday morning.
 */
function scheduleMatches(matches: GeneratedMatch[], opts: DrawOptions): GeneratedMatch[] {
  const courts = opts.courtLabels.length > 0 ? opts.courtLabels : ['Court 1'];
  const byRound = new Map<number, GeneratedMatch[]>();
  for (const m of matches) {
    if (m.isBye) continue;
    const list = byRound.get(m.roundNumber) ?? [];
    list.push(m);
    byRound.set(m.roundNumber, list);
  }

  let cursor = new Date(opts.startsAt);
  const rounds = [...byRound.keys()].sort((a, b) => a - b);

  for (const round of rounds) {
    const roundMatches = byRound.get(round) ?? [];
    roundMatches.forEach((m, i) => {
      const courtIndex = i % courts.length;
      const wave = Math.floor(i / courts.length);
      const start = new Date(cursor.getTime() + wave * opts.matchDurationMinutes * 60_000);
      m.courtLabel = courts[courtIndex];
      m.scheduledAt = start.toISOString();
    });
    const waves = Math.ceil(roundMatches.length / courts.length);
    cursor = new Date(cursor.getTime() + waves * opts.matchDurationMinutes * 60_000);
  }

  return matches;
}

// ---------------------------------------------------------------------------
// Single elimination
// ---------------------------------------------------------------------------

function nextPowerOfTwo(n: number): number {
  let p = 1;
  while (p < n) p *= 2;
  return p;
}

const KNOCKOUT_LABELS: Record<number, string> = {
  2: 'Final',
  4: 'Semi-final',
  8: 'Quarter-final',
  16: 'Round of 16',
  32: 'Round of 32',
  64: 'Round of 64',
};

function roundLabel(teamsRemaining: number): string {
  return KNOCKOUT_LABELS[teamsRemaining] ?? `Round of ${teamsRemaining}`;
}

/**
 * Standard bracket seeding order, so that the top seed and the second seed
 * can only meet in the final. For a bracket of 8 this yields
 * [1, 8, 5, 4, 3, 6, 7, 2].
 */
export function seedOrder(size: number): number[] {
  let order = [1, 2];
  while (order.length < size) {
    const next: number[] = [];
    const rounds = order.length * 2 + 1;
    for (const s of order) {
      next.push(s, rounds - s);
    }
    order = next;
  }
  return order;
}

export function generateSingleElimination(
  entrants: Entrant[],
  opts: DrawOptions,
): GeneratedMatch[] {
  const seeded = seedEntrants(entrants, opts);
  const size = nextPowerOfTwo(Math.max(2, seeded.length));
  const order = seedOrder(size);

  // Pad with byes so the bracket is a clean power of two. Byes fall to the
  // lowest seeds, which is what a seeded draw is for.
  const slots: (Entrant | null)[] = order.map((seedNo) => seeded[seedNo - 1] ?? null);

  const matches: GeneratedMatch[] = [];
  const roundCount = Math.log2(size);

  // First round.
  let previousRoundIndices: number[] = [];
  for (let i = 0; i < size / 2; i++) {
    const a = slots[i * 2];
    const b = slots[i * 2 + 1];
    matches.push({
      roundNumber: 1,
      roundLabel: roundLabel(size),
      bracketPosition: i + 1,
      teamAId: a?.id ?? null,
      teamBId: b?.id ?? null,
      isBye: a === null || b === null,
    });
    previousRoundIndices.push(matches.length - 1);
  }

  // Subsequent rounds, wiring each match to its parent.
  for (let round = 2; round <= roundCount; round++) {
    const teamsRemaining = size / 2 ** (round - 1);
    const current: number[] = [];
    for (let i = 0; i < teamsRemaining / 2; i++) {
      matches.push({
        roundNumber: round,
        roundLabel: roundLabel(teamsRemaining),
        bracketPosition: i + 1,
        teamAId: null,
        teamBId: null,
      });
      const idx = matches.length - 1;
      current.push(idx);

      matches[previousRoundIndices[i * 2]].nextMatchIndex = idx;
      matches[previousRoundIndices[i * 2]].nextMatchSlot = 1;
      matches[previousRoundIndices[i * 2 + 1]].nextMatchIndex = idx;
      matches[previousRoundIndices[i * 2 + 1]].nextMatchSlot = 2;
    }
    previousRoundIndices = current;
  }

  return scheduleMatches(matches, opts);
}

// ---------------------------------------------------------------------------
// Round robin (circle method)
// ---------------------------------------------------------------------------

export function generateRoundRobin(
  entrants: Entrant[],
  opts: DrawOptions,
  groupLabel?: string,
): GeneratedMatch[] {
  const teams: (Entrant | null)[] = [...entrants];
  if (teams.length % 2 === 1) teams.push(null); // bye marker

  const n = teams.length;
  const rounds = n - 1;
  const half = n / 2;
  const matches: GeneratedMatch[] = [];
  let rotation = [...teams];

  for (let round = 1; round <= rounds; round++) {
    for (let i = 0; i < half; i++) {
      const a = rotation[i];
      const b = rotation[n - 1 - i];
      if (a === null || b === null) continue;
      matches.push({
        roundNumber: round,
        roundLabel: `Round ${round}`,
        bracketPosition: i + 1,
        groupLabel,
        teamAId: a.id,
        teamBId: b.id,
      });
    }
    // Rotate all but the first entry.
    rotation = [rotation[0], rotation[n - 1], ...rotation.slice(1, n - 1)];
  }

  return scheduleMatches(matches, opts);
}

// ---------------------------------------------------------------------------
// Americano
// ---------------------------------------------------------------------------

/**
 * Americano: players rotate partners every round and score individually.
 * Everybody plays with and against as many different people as the round
 * count allows. This is the default social padel format in the UAE and the
 * reason a club's Friday morning fills.
 *
 * Requires a multiple of four players. The caller is responsible for putting
 * surplus players on a rest rotation; this function refuses rather than
 * silently dropping someone from a paid event.
 */
export function generateAmericano(
  players: Entrant[],
  opts: DrawOptions,
): GeneratedMatch[] {
  if (players.length < 4 || players.length % 4 !== 0) {
    throw new Error(
      `Americano requires a multiple of 4 players; received ${players.length}. ` +
        'Split surplus players into a rest rotation before generating the draw.',
    );
  }

  const rounds = opts.roundsTotal ?? Math.max(3, players.length - 1);
  const ordered = seedEntrants(players, opts);
  const matches: GeneratedMatch[] = [];

  // Rotate a fixed anchor with a revolving field, which is the standard
  // Americano rotation and guarantees partner variety across rounds.
  let rotation = ordered.map((p) => p.id);

  for (let round = 1; round <= rounds; round++) {
    const courtsThisRound = rotation.length / 4;
    for (let c = 0; c < courtsThisRound; c++) {
      const block = rotation.slice(c * 4, c * 4 + 4);
      matches.push({
        roundNumber: round,
        roundLabel: `Round ${round}`,
        bracketPosition: c + 1,
        teamAPlayers: [block[0], block[3]],
        teamBPlayers: [block[1], block[2]],
      });
    }
    // Rotate: anchor the first player, shift the rest by one.
    rotation = [rotation[0], ...rotation.slice(2), rotation[1]];
  }

  return scheduleMatches(matches, opts);
}

// ---------------------------------------------------------------------------
// Mexicano
// ---------------------------------------------------------------------------

export interface PlayerStanding {
  playerId: string;
  points: number;
}

/**
 * Mexicano: like Americano, but each round is paired by current standings
 * rather than by a fixed rotation. Ranks 1 and 4 play 2 and 3 on the top
 * court, 5 and 8 play 6 and 7 on the next, and so on. Games stay competitive
 * as the session goes on, which is why clubs prefer it for mixed-ability
 * fields.
 *
 * Round one has no standings to work from, so it is drawn as an Americano
 * round. Call `generateMexicanoRound` after each round with live standings.
 */
export function generateMexicanoRound(
  standings: PlayerStanding[],
  roundNumber: number,
  opts: DrawOptions,
): GeneratedMatch[] {
  if (standings.length % 4 !== 0) {
    throw new Error(
      `Mexicano requires a multiple of 4 players; received ${standings.length}.`,
    );
  }

  // Descending points; ties broken by player id for reproducibility.
  const ranked = [...standings].sort(
    (a, b) => b.points - a.points || a.playerId.localeCompare(b.playerId),
  );

  const matches: GeneratedMatch[] = [];
  for (let c = 0; c < ranked.length / 4; c++) {
    const [p1, p2, p3, p4] = ranked.slice(c * 4, c * 4 + 4);
    matches.push({
      roundNumber,
      roundLabel: `Round ${roundNumber}`,
      bracketPosition: c + 1,
      // 1 + 4 against 2 + 3: the standard Mexicano pairing, which balances
      // the two sides rather than letting the top two stack together.
      teamAPlayers: [p1.playerId, p4.playerId],
      teamBPlayers: [p2.playerId, p3.playerId],
    });
  }

  return scheduleMatches(matches, opts);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export function generateDraw(
  format: TournamentFormat,
  entrants: Entrant[],
  opts: DrawOptions,
): GeneratedMatch[] {
  switch (format) {
    case 'single_elimination':
    case 'double_elimination':
      // Double elimination generates the winners bracket here; the losers
      // bracket is wired as losers drop in, handled at match completion.
      return generateSingleElimination(entrants, opts);
    case 'round_robin':
      return generateRoundRobin(entrants, opts);
    case 'group_then_knockout': {
      // Four groups is the practical default for a club tournament: it fits
      // a morning on four courts.
      const groups = 4;
      const seeded = seedEntrants(entrants, opts);
      const buckets: Entrant[][] = Array.from({ length: groups }, () => []);
      // Snake seeding, so group strength is even.
      seeded.forEach((e, i) => {
        const row = Math.floor(i / groups);
        const col = i % groups;
        buckets[row % 2 === 0 ? col : groups - 1 - col].push(e);
      });
      return buckets.flatMap((bucket, i) =>
        generateRoundRobin(bucket, opts, `Group ${String.fromCharCode(65 + i)}`),
      );
    }
    case 'americano':
      return generateAmericano(entrants, opts);
    case 'mexicano':
      // Round one only. Subsequent rounds come from generateMexicanoRound.
      return generateAmericano(entrants, { ...opts, roundsTotal: 1 });
    case 'ladder':
      throw new Error('Ladders are challenge-driven and have no pre-generated draw.');
    default: {
      const exhaustive: never = format;
      throw new Error(`Unsupported tournament format: ${String(exhaustive)}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Rating update
// ---------------------------------------------------------------------------

/**
 * Elo with a volatility-scaled K factor. New players move fast so they reach
 * a truthful rating within a handful of matches, which is what makes open
 * matches work: a 3.0 dropped into a 4.5 game does not come back.
 */
export function updateElo(
  ratingA: number,
  ratingB: number,
  scoreA: 0 | 0.5 | 1,
  options: { kA?: number; kB?: number } = {},
): { ratingA: number; ratingB: number } {
  const expectedA = 1 / (1 + 10 ** ((ratingB - ratingA) / 400));
  const kA = options.kA ?? 32;
  const kB = options.kB ?? 32;
  return {
    ratingA: Math.round((ratingA + kA * (scoreA - expectedA)) * 100) / 100,
    ratingB: Math.round((ratingB + kB * (1 - scoreA - (1 - expectedA))) * 100) / 100,
  };
}

/** Provisional players (fewer than 10 matches) get a wider K. */
export function kFactor(matchesPlayed: number): number {
  if (matchesPlayed < 10) return 64;
  if (matchesPlayed < 30) return 40;
  return 24;
}
