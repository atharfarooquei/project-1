# NABD - Architecture and repository layout

## Folder structure

```
nabd/
├── apps/
│   ├── mobile/                        Expo (React Native), iOS and Android
│   │   ├── app/                       expo-router file-based routes
│   │   │   ├── (tabs)/
│   │   │   │   ├── explore.tsx        Home / Explore  [built]
│   │   │   │   ├── community.tsx      Clubs, meets, matches, challenges
│   │   │   │   ├── bookings.tsx       Classes, courts, event tickets
│   │   │   │   └── profile.tsx        Membership, credits, pause, language
│   │   │   ├── checkin.tsx            Dynamic QR check-in  [built]
│   │   │   ├── venue/[slug].tsx
│   │   │   ├── community/
│   │   │   │   ├── clubs.tsx
│   │   │   │   ├── club/[slug].tsx
│   │   │   │   ├── meet/[occurrenceId].tsx
│   │   │   │   ├── match/[id].tsx
│   │   │   │   ├── events.tsx
│   │   │   │   ├── event/[slug].tsx
│   │   │   │   └── tournament/[id].tsx     live bracket and scoring
│   │   │   └── membership/
│   │   │       ├── plans.tsx
│   │   │       ├── credits.tsx
│   │   │       └── pause.tsx
│   │   └── src/
│   │       ├── components/            VenueCard, FilterSheet, CommunityRail,
│   │       │                          HeatBanner  [built]
│   │       ├── hooks/                 useVenueDiscovery, useMember  [built]
│   │       ├── lib/                   supabase, api  [built]
│   │       └── theme/                 tokens  [built]
│   │
│   └── web/                           Next.js: marketing, admin, partner, organiser
│       ├── app/
│       │   ├── (marketing)/           Landing, pricing, partner recruitment
│       │   ├── partner/[venueId]/
│       │   │   ├── reception/         Rotating QR tablet screen  [built]
│       │   │   ├── dashboard/         Visits, fills, payouts
│       │   │   └── settings/          Caps, blackouts, gender windows
│       │   ├── organiser/             Event creation, permits, registrations
│       │   ├── admin/                 Venue onboarding, compliance queue, DSARs
│       │   └── api/
│       │       ├── checkin/                              [built]
│       │       ├── events/[eventId]/register/            [built]
│       │       ├── partner/venues/[venueId]/checkin-code/ [built]
│       │       ├── partner/venues/[venueId]/pause/
│       │       ├── partner/venues/[venueId]/recent-visits/
│       │       ├── community/meets/upcoming/
│       │       ├── community/matches/open/
│       │       ├── tournaments/[id]/draw/
│       │       ├── tournaments/[id]/matches/[matchId]/score/
│       │       ├── subscriptions/pause/
│       │       ├── reviews/                                [built]
│       │       ├── reviews/context/
│       │       ├── rewards/redeem/                         [built]
│       │       ├── rewards/claims/
│       │       ├── marketplace/{products,orders}/
│       │       ├── programmes/{list,enrol}/
│       │       ├── weather/
│       │       └── webhooks/{stripe,tabby,tamara,strava}/
│       └── src/lib/                   supabase-server, audit  [built]
│
├── packages/
│   ├── shared/                        Pure logic. No I/O anywhere in here.
│   │   └── src/
│   │       ├── entitlement/engine.ts  Check-in decision engine  [built, tested]
│   │       ├── rewards/engine.ts      Coin earn + redemption    [built, tested]
│   │       ├── tournament/brackets.ts Draw generation + Elo     [built, tested]
│   │       ├── util/heat.ts           Heat advisory             [built, tested]
│   │       ├── i18n/                  en + ar, RTL, formatters  [built]
│   │       └── types/domain.ts        Domain unions             [built]
│   └── ui/                            Tokens shared across native and web
│
├── supabase/
│   ├── migrations/                    0001 to 0012  [built, parse-verified]
│   ├── functions/                     Edge functions: webhooks, cron jobs
│   └── seed/dev_seed.sql              Realistic UAE fixture data  [built]
│
└── docs/
    ├── PRD.md
    └── ARCHITECTURE.md
```

## The one structural decision that matters

The entitlement engine is a pure function in `packages/shared`, not code inside
an API route.

It takes a fully-loaded context object and returns a decision. It performs no
I/O, knows nothing about Supabase or HTTP, and is unit-tested exhaustively
without a database. The API route's entire job is to load state, call the
engine, and persist what comes back.

The reason is operational rather than aesthetic. Every aggregator eventually
faces two questions it must be able to answer precisely: "why was this member
let in" and "why was this member refused". If that logic lives scattered
across route handlers, mixed with database calls, the honest answer is that
nobody knows. With the engine isolated, the answer is a test case.

The same applies to the bracket generator. A tournament draw that cannot be
reproduced cannot be defended when a player claims it was rigged, and in a
paid tournament someone eventually will. Hence the seeded PRNG.

## Two ledgers, never merged

Credits and coins are separate tables with separate balances, and the
separation is load-bearing rather than tidy.

Credits are a paid entitlement: cash or subscription revenue came in, VAT
was charged, and in some circumstances they are refundable. Coins are a
marketing giveaway: no cash came in, no VAT applies, and they are expensed
on redemption against a budget.

Merging them would break revenue recognition (you could no longer tell
earned-free from paid-for), refunds (cash must never be returned for a
coin-funded credit), and the regulatory position (a single balance mixing
paid-in value with promotional value starts to look like stored value
rather than loyalty).

Coins convert into credits at redemption. Credits never convert back. Coins
are non-transferable and have no cash-out path; `coinsToCash()` exists only
to throw an error saying so, so that any attempt to add one fails loudly in
a code review rather than quietly moving the programme into the CBUAE
Stored Value Facilities perimeter.

## Compliance gates are triggers, not checks in handlers

Four state transitions are refused by the database rather than by
application code, because a gate that can be bypassed by calling a
different code path is not a gate:

| Transition | Gate |
|---|---|
| Event to `published` | `enforce_event_publication_gates()`: approved permit or recorded override, verified organiser, current public liability cover, waiver attached |
| Under-18 event registration | `enforce_minor_registration()`: verified guardian consent, age band |
| Listing to `active` | `enforce_listing_gates()`: verified seller with current licence, in-date product registration, passed prohibited-substance screen, unexpired stock |
| Programme to `published` | `enforce_programme_publication_gates()`: verified academy, insurance, assigned coach, and for minors a safeguarding policy, named lead, supervision ratio and cleared coach vetting in date through the end of the programme |

Plus two table constraints worth naming: a coach cannot be flagged as
working with minors without cleared vetting, and a programme admitting
minors cannot exist without a supervision ratio.

## Data layer

**Postgres with PostGIS.** Venue and meeting-point geography are real
geographic types, not float pairs. Distance is computed in the database with
`ST_Distance` and returned in kilometres. A client that computes distance from
a fetched page cannot sort or page correctly, and will confidently show the
wrong nearest gym the moment the result set exceeds one page.

**Row level security on every table.** The anon and authenticated roles can
never read another member's activity, another partner's commercials, or any
compliance evidence. Everything on the entitlement hot path runs service-role
from a server route, which is what lets the policies be restrictive.

**Append-only ledgers.** Credits are a ledger with derived balances, never a
mutable integer column. A mutable balance with concurrent writers is how
members end up with free access and partners end up unpaid. The audit log and
the consent table are likewise append-only: a revoked consent is a new row, so
the history survives for a data subject request.

**Entitlement snapshots.** Every visit freezes the tier, plan, caps, policies
and balances as they stood at that instant, into a jsonb column. Partner rates
change, tier definitions change, caps get renegotiated. Historic payouts must
not move underneath them.

## Check-in security

The venue tablet displays a QR that rotates every 30 seconds; the member scans
it. This is the reverse of the common design and it is the correct direction:
a member-displayed code is one screenshot away from being shared, and it
obliges every partner to buy scanning hardware.

Payload: `v1.{venueId}.{timeWindow}.{hmac}`, where the HMAC is computed over
venue id and time window with a per-venue secret that never leaves the server.
The server accepts the current window and one either side for clock skew, and
retains the previous secret briefly across a rotation so an in-flight tablet
does not break mid-shift.

On scan the client posts the payload plus its coordinates and decides nothing.
A poor GPS fix widens the geofence by up to 60m, capped, because basement and
mall gyms are common in this market and refusing a member standing at
reception costs more than the marginal fraud it prevents.

## Payments

Stripe in AED as the primary rail, with Apple Pay and Google Pay from day one:
card-on-file conversion in this market without them is materially worse.
Tabby and Tamara for annual plans and event tickets only; BNPL fees do not
survive monthly subscription economics.

The provider is an enum on the order, not a hard-coded assumption, so moving
to Network International, Telr or Checkout.com is a configuration change
rather than a migration.

VAT at 5 percent, with sequential invoice numbering driven by a Postgres
sequence rather than assembled in application code, because sequential
numbering is a requirement rather than a convention. Whether we are agent or
principal on an event ticket is recorded per event, because it changes VAT
treatment and revenue recognition on every ticket sold.

## Internationalisation

English and Arabic from the first commit. Content columns are bilingual
(`name_en`, `name_ar`) rather than a translations table: the content set is
small and the join cost is not worth it at this scale.

Layout direction is driven by locale through `I18nManager` on native and `dir`
on web, and every row in the built screens has an RTL variant. Bolting RTL on
in v2 produces a layout that never quite works.

## Scheduled work

Run daily via `pg_cron` or Supabase scheduled functions:

| Job | Purpose |
|---|---|
| `app.retention_sweep()` | Nulls precise scan coordinates and device data past 90 days. PDPL storage limitation. |
| `app.suspend_expired_venue_licences()` | Suspends venues whose trade or sports licence has lapsed. |
| Meet occurrence generation | Materialises the next 8 weeks of recurring club meets. |
| Heat evaluation | Snapshots weather onto tomorrow's outdoor occurrences and fires auto-cancel policies. |
| Credit cycle | Allocates monthly credits, applies the rollover cap, expires the remainder. |
| Payout accrual | Rolls granted visits and class fills into the current partner period. |
| Open match reaper | Cancels and refunds matches that did not fill by their deadline. |
| `app.expire_coins()` | Expires coins past 12 months as explicit negative ledger entries, so the ledger sums to the balance without a date filter. |
| `app.sweep_expired_listings()` | Delists marketplace products whose registration, seller licence or stock expiry has lapsed. |
| Review moderation release | Releases held coin awards once moderation clears; clawback on removal is trigger-driven. |
| Coach vetting expiry | Flags academies whose coach background checks expire within 60 days, before a programme is refused publication. |

## Testing

The pure modules carry real unit coverage: 110 tests across the entitlement
engine, the rewards engine, the bracket generator and the heat advisory,
including the ordering guarantees that matter (a member who has exhausted
their own allowance must be told that, not that the gym is busy) and the
sentiment-neutrality invariant on review rewards, which is asserted
explicitly so that adding a sentiment term breaks a test rather than quietly
skewing the rating data.

The SQL is parse-verified against libpg_query. It has not been executed
against a live PostGIS instance in this environment, so run `supabase db reset`
against a local stack before trusting the migrations end to end.

Integration coverage for the API routes, and Detox or Maestro coverage for the
two mobile flows, belong in phase 1.
