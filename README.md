# NABD

One pass, every gym - and the community that gets you there.

A UAE fitness platform: clubs, run meets, cycling rides, padel matches,
tournaments and ticketed events as the free layer, with a tiered venue-access
membership behind it.

**Status: MVP scaffold.** Working name only; trademark and domain unverified.
Read `docs/PRD.md` before the code - it argues for a materially different
product shape than a straight ClassPass clone, and section 11 lists the
decisions that are still open.

---

## What is actually built here

| Area | State |
|---|---|
| Product requirements and positioning | `docs/PRD.md` |
| Architecture and folder map | `docs/ARCHITECTURE.md` |
| Database schema, 12 migrations | Written, parse-verified, not yet executed against a live PostGIS instance |
| Entitlement engine | Written, 31 unit tests |
| Rewards engine (coin earn, caps, redemption) | Written, 44 unit tests |
| Tournament draw engine (knockout, round robin, Americano, Mexicano, Elo) | Written, 25 unit tests |
| Heat advisory | Written, 10 unit tests |
| i18n, English and Arabic with RTL | Written, 255 keys at full parity |
| Home / Explore screen | Written |
| Dynamic QR check-in screen | Written |
| Post-visit review composer | Written |
| Check-in API endpoint | Written |
| Event registration endpoint with compliance gates | Written |
| Review submission and coin redemption endpoints | Written |
| Partner reception screen and rotating QR endpoint | Written |
| Marketplace, academies and programmes | Schema only, no UI or endpoints |
| Everything else in the folder map | Not written |

Nothing here has been run against a live Supabase project or built for a
device. The pure logic is tested; the wiring is not.

---

## Getting it running

```bash
pnpm install
cp .env.example .env.local        # fill in Supabase, Stripe, Mapbox

# Local database
supabase start
supabase db reset                 # applies supabase/migrations in order
pnpm db:seed                      # fictional UAE venues, plans, caps, blackouts
pnpm db:types                     # regenerates packages/shared/src/types/database.ts

# Verify the pure logic
pnpm --filter @nabd/shared test
pnpm --filter @nabd/shared typecheck

# Run
pnpm dev
```

The seed data is invented. Venue and partner names are shaped like real UAE
supply so the UI can be judged honestly, but no real business is represented
and none of them are partners. Replace before any external demo.

---

## Three things worth knowing before you change anything

**The entitlement engine is pure.** It lives in `packages/shared/src/entitlement`,
performs no I/O, and is the only place that decides whether a member may enter
a venue. The API route loads state, calls it, and persists the result. Keep it
that way: the questions "why was this member let in" and "why was this member
refused" arrive with every partner dispute, and they are only answerable if the
logic is a tested function rather than scattered across route handlers.

**The QR is displayed by the venue, not the member.** A member-displayed code
is one screenshot away from being shared. The venue tablet shows a code that
rotates every 30 seconds and the member scans it. The HMAC secret never leaves
the server.

**Credits are a ledger, not a number.** Balances are derived from
`app.credit_ledger`, which is append-only. A mutable balance column with
concurrent writers is how members end up with free access and partners end up
unpaid.

**Coins are not credits, and reviews are not paid for being positive.**
Coins are a closed-loop marketing balance in a separate ledger: never
transferable, never cashable, convertible into credits one way only. The
star rating on a review earns nothing; the structured attributes earn the
coins, and the reward is identical for one star and five. `assertSentimentNeutral()`
exists so that adding a sentiment term breaks a test rather than quietly
skewing the rating data that discovery ranks on. Read the header of
migration 0011 before changing anything in this area.

---

## Compliance is in the schema, not in a memo

Waivers, permits, insurance certificates, guardian consent and PDPL consent
records are real tables with real gates. `app.enforce_event_publication_gates()`
refuses to publish a race or tournament without an approved permit, a verified
organiser and current public liability cover, or a recorded admin override with
a reason. `app.enforce_minor_registration()` refuses an under-18 entry without
verified guardian consent.

The regulatory positions encoded here are a design map and require verification
with UAE counsel and a tax adviser before launch. See `docs/PRD.md` section 6
for what has been assumed and section 11 for what is unresolved.

---

## Licence

Private. All rights reserved.
