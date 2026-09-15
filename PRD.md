# NABD - Product Requirements Document

**Working name:** NABD (نبض, "pulse"). Placeholder only. Trademark and domain clearance not done.
**Market:** United Arab Emirates (Dubai, Abu Dhabi, Sharjah, Ajman at MVP)
**Version:** 0.1 (MVP definition)
**Date:** September 2026
**Status:** Draft for founder sign-off

---

## 0. What changed from the original brief, and why

The brief described an aggregator: one subscription, many gyms. That product already exists in this market and is well defended. The changes below are the substance of this document, and they are the part worth arguing about before a line of code is written.

| Original brief | This PRD | Reason |
|---|---|---|
| Gym access is the product, community is a feature | Community is the front door, gym access is the paid conversion | Aggregator supply wars are won by whoever has capital. Community is won by whoever shows up every Tuesday at 6am. Only one of those is available to a bootstrapped founder. |
| Core Pass / Elite Pass, unlimited | Tiered subscription plus a monthly credit allowance | Unlimited access to high-cost supply is the single most reliable way to destroy an aggregator's margin. Credits price the expensive supply without breaking the bundle. |
| Visits table | Visits, plus an entitlement snapshot stored per visit | You will have partner disputes about what a member was entitled to on a given day. The entitlement must be frozen at check-in time, not recomputed later. |
| Partner dashboard shows revenue share | Partner dashboard plus caps, blackouts and per-user frequency limits | Gyms sign with aggregators and then churn when the aggregator floods their 7pm slot. Supply protection is a retention feature for partners, not a nice-to-have. |
| Compliance unmentioned | Waivers, permits, insurance, guardian consent, PDPL consent and VAT as first-class tables | The moment you put 60 people on a road at 5am or run a padel tournament, you are an event organiser with regulatory obligations. Building this in later means retrofitting it into a live liability. |

---

## 1. Thesis

Fitness in the UAE has three unusual properties that a generic ClassPass clone does not exploit.

**One.** The population is roughly 88% expatriate and highly transient. People arrive without a social graph and look for one through sport. Run clubs and padel groups are, functionally, the primary social infrastructure for new arrivals in Dubai. A product that solves belonging has a retention curve that a product that solves gym discounts does not.

**Two.** The activity calendar is bimodal. October to April, outdoor participation is enormous. May to September, outdoor training is genuinely hazardous and everything moves indoors or to 5am. Every incumbent treats this as a churn problem. It is actually a product feature waiting to be built: seasonal modes, heat-aware programming, and an explicit summer pause.

**Three.** Padel has grown to roughly 950 courts across 320 venues nationally, with 400 plus in Dubai and participation growing 40 to 50 percent annually. Court booking is fragmented and the social layer, finding a fourth player at your level, running a ladder, organising an Americano, is almost entirely on WhatsApp. That is an unowned category with real, recurring, high-frequency demand.

**The wedge:** own the social layer of UAE sport (clubs, meets, matches, tournaments, events) as a free product. Monetise it with a membership that converts that community habit into venue access. The gym pass is the business model; the community is the moat.

---

## 2. Competitive position

| Player | What they own | Where they are weak |
|---|---|---|
| Privilee | Beach clubs, hotel pools, resort gyms. The dominant UAE lifestyle pass. High annual price point, family/leisure positioning. | Almost no community layer. Leisure-led, not performance-led. Weak on studios, crossfit, padel, running. |
| ClassPass | Global brand, boutique studio supply, credit mechanics. | Thin UAE supply outside central Dubai. No local cultural product (Ramadan, heat, gender policy, Arabic). No events or clubs. |
| Playtomic | Padel court booking and player matching, the default booking rail. | Single sport. No gym access, no membership bundle, no cross-sport identity. |
| Standalone gym chains | Own their own members. | Cannot offer cross-venue access; lose the multi-venue user entirely. |
| WhatsApp groups | Where UAE run clubs, cycling crews and padel ladders actually live today. | No discovery, no payments, no waivers, no results, no safety layer, no memory. This is the real incumbent and the real opportunity. |

**Positioning statement:** NABD is not a cheaper gym membership. It is where you find your people, and the membership is what gets you in the door once you have.

**What we do not do:** compete with Privilee on beach clubs and hotel pools at MVP. Different buyer, different supply cost, different job.

---

## 3. Users

**Rashid, 29, new arrival, Dubai Marina.** Landed six weeks ago. Knows nobody. Wants to run, wants to play padel, does not know where or with whom. Downloads the app for a free Tuesday run club. Converts to a paid tier in week three because his new running friends train at three different gyms.
*Primary acquisition persona. Free tier is designed entirely around him.*

**Layla, 34, marketing manager, Abu Dhabi.** Wants ladies-only facilities, books three classes a week, travels to Dubai twice a month for work and wants access there too. Sensitive to gender policy being accurate, not aspirational.
*Primary paid persona. Gender policy filtering is a hard requirement, not a filter chip.*

**Tom, 41, padel obsessive, Jumeirah.** Plays four times a week. Wants a rating, a ladder, an Americano on Friday morning, and to stop managing three WhatsApp groups. Will pay for court credits and tournament entries.
*Primary transactional persona. Highest revenue per user, lowest subscription attachment.*

**Mariam, 38, HR lead, 400-person company in DIFC.** Needs a wellness benefit that produces an engagement report. Buys 120 seats.
*Primary B2B persona. Not MVP scope, but the schema must not exclude her.*

**Karim, gym owner, two locations in Sharjah.** Has empty capacity 10am to 4pm, full at 7pm. Will accept aggregator members off-peak at a discount, will churn instantly if they crowd his peak or displace his direct members.
*Supply persona. Caps and blackouts exist for him.*

---

## 4. Feature set

### 4.1 Community layer (free, the wedge)

**Clubs.** Persistent groups with a discipline (run, cycle, padel, swim, strength, hyrox, yoga, hiking), a home emirate, an owner, members, roles and a verification badge for established clubs. Public, request-to-join or invite-only. This is the container for repeat behaviour.

**Meets.** Recurring sessions attached to a club, defined by a recurrence rule rather than duplicated rows. A Tuesday 6am run at Kite Beach is one meet with occurrences, not 52 events. Each meet carries:
- Meeting point as a geographic point plus a human landmark ("Kite Beach car park, opposite the flagpole")
- Pace groups as structured data (5:00/km, 5:30/km, 6:00+/km, no-drop) so a beginner can see they will not be abandoned
- Route as an uploaded GPX with distance and elevation
- Gender policy, inherited or overridden
- A weather policy: what happens at 41C, and the automatic advisory that fires
- Capacity and waitlist

**Cycling meets.** Same primitive as running, with the fields cyclists actually need: average speed band rather than pace, drop or no-drop, mechanical support flag, and the UAE loop taxonomy (Al Qudra, Nad Al Sheba, Hudayriyat, Al Wathba, Masdar). Ride leader must be identified.

**Open matches (padel, tennis, basketball, football).** "Three players confirmed, need a fourth, Saturday 8am, Reform Athletica, level 3.5." Slot-based, rating-gated, auto-cancel and auto-refund if unfilled by a cutoff. This is the single highest-frequency object in the product and it is the reason someone opens the app daily.

**Player ratings.** An Elo-style rating per discipline, seeded by self-assessment and corrected by match results. Ratings are what make open matches work: a 3.0 player who lands in a 4.5 game does not come back. Ratings feed seeding for tournaments and ladders.

**Ladders and leagues.** Season-long standings by emirate and discipline. Challenge the player two rungs above you, report the score, move. Low operational cost, very high retention, and it generates court bookings, which is revenue.

**Tournaments.** Bracket engine supporting knockout, round robin, group-then-knockout, and the two formats that actually dominate UAE padel socially: **Americano** (rotating partners, individual points) and **Mexicano** (rotating partners, ranked pairing each round). Court scheduling, live scoring by a captain, published results. A padel tournament that runs itself is the highest-leverage supply acquisition tool we have: venues want the court revenue and the footfall.

**Events marketplace.** Ticketed, one-off, larger: desert trail races, hyrox-style events, aquathlons, beach bootcamps, yoga retreats, brand activations. Multiple ticket types, waves, bib numbers, waivers, capacity, refund policy, results upload. This is where the compliance layer becomes load-bearing.

**Challenges.** Time-boxed goals with leaderboards: distance, check-in count, streak, steps. Individual, team, club, corporate or emirate-wide. Explicitly designed to plug into Dubai Fitness Challenge in November and a Ramadan night-movement challenge, because those are the two moments per year when the entire country is already primed.

**Social graph.** Follow, a lightweight activity feed, shared check-ins and results, club walls. Strava import for activity verification on challenges. Deliberately thin: we are not building a social network, we are building proof that your friends showed up.

### 4.2 Access layer (paid)

**Tiers.**

| Tier | Monthly (AED, indicative, VAT inclusive) | Venue access | Credits/month |
|---|---|---|---|
| Community | 0 | None | 0 |
| Core | 349 | Standard commercial gyms, off-peak unrestricted, peak subject to venue caps | 30 |
| Elite | 749 | Core plus boutique studios, crossfit boxes, hotel gyms | 90 |
| Padel add-on | 199 | Court credit pack, ladder entry, priority open-match slots | 60 court credits |

Prices are placeholders pending unit-economics modelling against real partner rates. Do not put these in front of a partner.

**Credits.** Every bookable item has a credit cost that tracks our actual cost of supply: a 6pm hot yoga class in DIFC costs more credits than a 2pm gym visit in Al Nahda. Gym check-ins at Core venues cost zero credits within the visit cap. Credits expire monthly with a small rollover cap. Overflow credits purchasable in packs.

*This is the mechanism that keeps the business alive. Unlimited access to premium supply is how aggregators die.*

**Visit caps.** Per user, per venue, per month (default 4 at Core, 6 at Elite, configurable per partner contract). Prevents a member using us as a 40-visit-a-month substitute for a direct membership, which is the outcome every gym owner fears and the reason they refuse to sign.

**Pause.** Up to 30 days per subscription year, minimum 7 days per pause, maximum two pauses per year. Summer-travel behaviour in this market is not an edge case, it is the majority. Billing suspends, credits freeze, community access continues. Community access continuing during a pause is deliberate: it is what brings them back in September.

**Dynamic check-in.** The venue displays a rotating QR code on a tablet at reception. The member scans it. The reverse of the common design, and the correct one: a member-displayed code can be screenshotted and shared, a venue-displayed rotating code cannot. See section 7.

**Class and court booking.** Real inventory, real capacity, waitlists, no-show penalties. A no-show costs credits, because a no-show costs the partner a seat.

### 4.3 Partner layer

**Reception app.** One screen. Rotating QR, plus a live feed of who just checked in with photo and tier so the receptionist can spot a mismatch. Manual override with reason code for when the member's phone is dead.

**Supply protection controls.**
- Daily cap on aggregator check-ins
- Peak-hour blackout windows by day of week
- Concurrent occupancy limit
- Per-user monthly visit cap override
- Instant pause of all aggregator access (a switch they can hit at 7pm on a bad day, which is precisely why they will trust us)

**Payouts.** Visit count, class fills, revenue share, VAT breakdown, remittance reference, period statements. Partners churn over payment opacity more than over rates.

**Event organiser tools.** Anyone can run a club for free. Running a ticketed event requires organiser verification: trade licence, insurance certificate, and permit references. See section 6.

### 4.4 UAE-specific intelligence

This is the section that a generic build will not have, and it is where the product earns the right to call itself a UAE product.

- **Heat advisory.** Outdoor meets between May and September surface a live heat and humidity index with a traffic-light advisory. Above a configured threshold the meet is auto-flagged, participants are notified, and the app surfaces indoor alternatives. Organisers can set a policy that auto-cancels. This is both a safety feature and a liability-reduction feature.
- **Ramadan mode.** Alternate scheduling surface for the Holy Month: post-iftar and pre-suhoor training windows, reduced-intensity flags, adjusted gym hours, and suppression of daytime outdoor meet promotion. Opt-in, not assumed.
- **Prayer-time awareness.** Booking slots show prayer times for the relevant emirate so scheduling does not collide. Passive, non-prescriptive.
- **Gender policy as a hard constraint.** Mixed, ladies only, men only, and ladies-hours (time-windowed) at venue, class, meet and event level. Enforced at check-in and at booking, not merely displayed as a filter. Getting this wrong is a serious product failure, not a UX inconvenience.
- **Emirate-aware discovery and tiering.** Cross-emirate access is a distinct entitlement. A Sharjah member commuting to Dubai is a different product than a Dubai-only member.
- **Arabic and RTL.** Full i18n from the first commit, not a retrofit. Venue and event names stored bilingually. Layout direction driven by locale. Arabic register: Modern Standard Arabic, UAE convention, for anything contractual.
- **School-holiday and family mode.** Family-friendly venue and event filtering during the July to August and December windows.

### 4.5 Deliberately out of MVP scope

Nutrition, wearables beyond Strava import, personal training marketplace, corporate wellness portal, physio and recovery, retail, Abu Dhabi beach clubs, any emirate beyond the four named. Each of these is a plausible v2. None of them make the wedge work.

---

## 5. Business model

**Revenue lines**
1. Subscription (Core, Elite, add-ons) - recurring, the primary line
2. Credit pack sales - high margin, purely incremental
3. Event ticketing platform fee (target 8 to 12 percent plus payment cost)
4. Tournament entry fees, where we are the organiser
5. Sponsorship of challenges and clubs (a bank or a sports brand sponsoring a 30-day emirate challenge is a very saleable unit in this market)
6. Corporate seats (post-MVP)

**Cost structure**
1. Partner payouts per visit or per class fill, the dominant variable cost
2. Payment processing, roughly 2.9 percent plus fixed for cards, higher for BNPL
3. Event operations where we organise
4. Cloud and mapping

**The number that decides whether this works:** blended cost per active member per month versus subscription price. Every credit rule, visit cap and blackout in this document exists to hold that line. Model it before signing a single partner contract.

**Payments.** Stripe in AED as the primary rail, requiring a UAE entity and a Stripe UAE account. Apple Pay and Google Pay from day one, because card-on-file conversion in this market without them is materially worse. Tabby and Tamara integrated as BNPL for annual plans and event tickets only, not for monthly subscriptions, where BNPL economics do not work. Provider abstraction in the schema so a switch to Network International, Telr or Checkout.com does not require a migration.

**VAT.** 5 percent on the subscription and on platform fees. Tax invoices with sequential numbering, supplier TRN, and place of supply recorded. Where we are agent rather than principal on an event ticket, the VAT treatment differs and the schema records which we are. Take tax advice on the agent versus principal question before launch, because it changes the revenue recognition on every ticket sold.

---

## 6. Compliance layer

Built into the data model, per the founder decision. Not a memo.

**Event permits.** Under the Dubai framework governing sports establishments and sports events, an organised sports event requires Dubai Sports Council approval, with parallel regimes in Abu Dhabi (ADSC) and the other emirates. Road-based running and cycling events additionally engage RTA and Police road-closure approvals. Venue-based events engage the venue's own licence and, for public events, municipality and DTCM permissions. The platform therefore holds a `permits` table keyed to an event, recording authority, permit number, issue and expiry dates and a document reference. **An event of type race, tournament or open-to-public cannot move to published status without a permit record, or an explicit recorded override by an admin.** Club meets below a participant threshold are treated as informal gatherings and are exempt, with the threshold configurable, because that boundary is a judgement call and will move.

**Waivers.** Versioned, bilingual, with an effective date. Signature records capture user, waiver version, timestamp, IP and a signature hash. A participant cannot be checked in to an event without a valid signature against the current version. Waiver enforceability in the UAE is not absolute, particularly regarding gross negligence, so waivers reduce risk rather than eliminate it and do not substitute for insurance.

**Insurance.** Organiser public liability certificates with expiry tracking. Expired certificate blocks publication of new events by that organiser.

**Minors.** Date of birth captured. Under-18 registration requires a linked guardian consent record. Certain event types and venues are age-gated outright. Guardian consent is versioned and auditable.

**Data protection.** Federal Decree-Law 45 of 2021 (UAE PDPL) applies, and DIFC or ADGM regimes apply instead if the operating entity sits in one of those. Design consequences: a `consents` table with purpose, version, grant and revoke timestamps and evidence; a defined retention schedule per table; an export and erasure path for data subject requests; explicit separate consent for marketing; and location data treated as sensitive with a documented purpose limitation. Health information (medical notes, emergency contact data on events) is high-sensitivity, encrypted at rest, restricted by role, and never used for personalisation or shared with partners.

**Sports establishment licensing.** Partner venues record their trade licence and sports establishment permit with expiry. Expired licence flags the venue and suspends new bookings pending renewal. This protects us from routing members into an unlicensed facility.

**Anti-abuse.** Device binding, geofence validation on check-in, velocity checks, and a rotating venue code. Account sharing is the main fraud vector in every aggregator and it is handled by design in section 7 rather than by policy.

---

## 7. Check-in security design

The requirement was a dynamic QR code. The important design decision is which side displays it.

**Rejected:** member's phone displays a QR, venue scans it. A screenshot is transferable. Venues need scanning hardware.

**Adopted:** the venue tablet displays a QR that rotates every 30 seconds. The member scans it with the app.

The QR payload is `v1.{venue_id}.{time_window}.{hmac}` where the HMAC is computed over venue id and time window with a per-venue secret held server-side and delivered to the tablet over an authenticated session. The server accepts the current window and one either side to tolerate clock skew.

On scan the client posts the payload plus its current coordinates. The server then runs the entitlement engine, in order, failing fast:

1. Payload signature valid and within the accepted time window
2. Venue active, licence not expired, aggregator access not paused by the partner
3. Member coordinates within the venue geofence (default 150m, configurable)
4. Subscription active and not paused
5. Member tier covers the venue tier
6. Gender policy satisfied for the member and the current time window
7. Venue not inside a blackout window
8. Venue daily cap not exhausted
9. Member's monthly visit cap for that venue not exhausted
10. Credit balance sufficient where the venue carries a credit cost
11. No duplicate check-in inside the cooldown window

On success the engine writes a visit row with an **entitlement snapshot**: the tier, plan, credit cost, caps and policy values as they stood at that instant, serialised into the row. When a partner disputes a payout eight weeks later, the answer is in the row, not in a recomputation against rules that have since changed.

Failures return a typed reason code, never a generic denial, because the receptionist and the member both need to know whether this is "your pass does not cover this gym", "you have used all four visits here this month" or "this gym is at capacity right now". Those three produce completely different member behaviour.

---

## 8. Architecture

Monorepo, pnpm workspaces, Turborepo.

```
nabd/
├── apps/
│   ├── mobile/          Expo (React Native), iOS and Android
│   └── web/             Next.js (marketing, admin, partner reception, organiser console)
├── packages/
│   ├── shared/          Types, zod schemas, entitlement engine, i18n, formatters
│   └── ui/              Design tokens shared across native and web
├── supabase/
│   ├── migrations/      Ordered SQL
│   └── functions/       Edge functions (webhooks, scheduled jobs)
└── docs/
```

**Why the entitlement engine lives in `packages/shared` and not in the API route:** it is pure, deterministic, and it must be unit-testable without a database. Every rule in section 7 is a function of an input object. The API route's only job is to load state, call the engine, and persist the result. This is the single most important structural decision in the codebase, because entitlement logic scattered across route handlers is how aggregators end up unable to answer "why was this member let in".

**Data.** Supabase Postgres with PostGIS for venue and meet geography, row level security on every user-facing table, and service-role access confined to server-side routes. Realtime subscriptions for the partner reception feed and live tournament scoring.

**Auth.** Supabase Auth: email, Google, Apple. Apple sign-in is mandatory for App Store approval given Google sign-in is present. Phone OTP added at v1.1, because UAE users expect it.

**Maps.** Mapbox rather than Google Maps for native, on cost and styling control. Distances computed with PostGIS `ST_DistanceSphere`, returned in kilometres, never computed client-side from a list.

**i18n.** Locale files in `packages/shared`, `i18next` on both surfaces, RTL driven by `I18nManager` on native and `dir` on web. Bilingual content columns (`name_en`, `name_ar`) rather than a translations table, because the content set is small and the join cost is not worth it at this scale.

**Testing.** The entitlement engine and the bracket generator have unit tests, because both are pure and both are where correctness bugs are expensive. Everything else gets integration coverage at v1.

---

## 9. Roadmap

**Phase 0, weeks 1 to 6. Community only, no payments.**
Clubs, meets, open matches, ratings, profiles, Arabic. Seed with 15 to 20 existing run clubs, cycling groups and padel crews who are currently on WhatsApp. Success is not downloads, it is: do those groups stop using WhatsApp for their Tuesday run. If they do not, nothing downstream works, and that answer costs six weeks rather than six months.

**Phase 1, weeks 7 to 14. Monetise the community.**
Ticketed events, tournaments with the Americano and Mexicano formats, waivers, permits, payments. Run our own padel tournament series and one trail-run series. This produces revenue and, critically, produces the venue relationships that phase 2 depends on, because a venue that has already taken our court bookings will sign an access deal.

**Phase 2, weeks 15 to 26. The pass.**
Core and Elite tiers, check-in, caps, blackouts, partner dashboard, payouts. Target 40 venues at launch across Dubai and Abu Dhabi, concentrated by area rather than spread thin, because a member needs three covered venues within 15 minutes of them or the pass is worthless.

**Phase 3, month 7 onward.** Corporate seats, Sharjah and Ajman depth, wearables, Northern Emirates.

---

## 10. Success metrics

Phase 0: weekly active clubs, meet attendance rate (registered versus attended), 4-week community retention, groups fully migrated off WhatsApp.
Phase 1: gross ticketed volume, organiser repeat rate, tournament fill rate, no-show rate.
Phase 2: paid conversion from community, blended cost per member per month, visits per member per month, partner churn, ratio of members who check in at 2 or more distinct venues (the number that proves the aggregator thesis is true for that member).

**The metric that should scare us:** members who check in at exactly one venue. They are paying us for something their gym sells cheaper direct, and they will work that out.

---

## 11. Open questions for the founder

1. **Operating entity.** Mainland versus freezone determines whether you can hold a Stripe UAE account, invoice UAE customers directly, and act as an event organiser. Freezone entities face restrictions on onshore activity that directly affect ticketing and organiser status. This decision blocks payments integration.
2. **Agent or principal on event tickets.** Changes VAT treatment, revenue recognition and liability exposure on every ticket. Needs a decision plus tax advice before phase 1.
3. **Do we organise events, or only host other organisers?** Organising puts the permit, insurance and liability burden on us, and gives us margin and control. Hosting is lighter and slower. The schema supports both; the business cannot do both well at once.
4. **Pricing.** Every number in section 5 is a placeholder. They need to come out of a partner-rate model, not out of a document.
5. **Name.** NABD is unverified for trademark and domain.
6. **Insurance.** Public liability and participant accident cover for platform-organised events, before the first event, not after the first injury.

---

## 12. Coins: the rewards economy

Added after the first draft. The brief asked for members to "earn tokens" for reviews, for following venues on social media, and "for all marketing angles", redeemable against classes and events.

The mechanic is right. Three things about how it was specified needed changing first.

### 12.1 Do not call them tokens

The word decides which regulator you are talking to. A **closed-loop loyalty point**, redeemable only against the platform's own services, sits outside the CBUAE Stored Value Facilities regime. A balance that is transferable between members, or redeemable for cash in any part, is arguing about whether it is a stored value facility, and an on-chain version brings VARA into scope.

Founder decision: closed-loop. Four properties hold the perimeter, and they are enforced by the absence of any code path rather than by policy:

1. Non-transferable between members. There is no gifting, no trading, no secondary market.
2. Never redeemable for cash, in whole or in part.
3. Redeemable only against NABD's own services.
4. No off-platform value of any kind.

The product calls them **coins**, never tokens, in English and Arabic, in the UI and in the code. `coinsToCash()` in the rewards engine exists solely to throw an error explaining this, so that any future attempt to add a cash-out path fails loudly and lands in a code review.

### 12.2 Coins are not credits, and the two ledgers never merge

| | Credits | Coins |
|---|---|---|
| Origin | Cash or subscription revenue | Marketing giveaway |
| Cash received | Yes | No |
| VAT | Charged on purchase | None |
| Accounting | Deferred revenue | Promotional liability, expensed on redemption |
| Refundable for cash | Sometimes | Never |
| Expiry | Billing cycle, with rollover cap | 12 months rolling |

Merging them breaks three things simultaneously: revenue recognition, because you can no longer tell earned-free from paid-for; refunds, because cash must never be returned for a coin-funded credit; and the regulatory story, because a single balance mixing paid-in value with promotional value starts to resemble stored value rather than loyalty.

The bridge is one-way. Coins convert into credits at redemption; credits never convert back into coins.

**Liability control.** Every earn rule is a budget line with a per-user cap, a per-subject cap and a share of a programme budget, and the engine refuses to award once any is reached. The `coin_liability` view reports coins outstanding, valued at the accounting rate and provisioned at the expected redemption rate, so the exposure is visible in the management accounts rather than discovered at year end.

### 12.3 Pay for data, never for sentiment

Paying for star ratings is the fastest available way to destroy the rating dataset, and the rating dataset is what the discovery ranking runs on. Undisclosed incentivised reviews are also a consumer-protection exposure.

Founder decision, implemented as engine invariants:

- **The star rating earns nothing.** It is optional, it sits at the bottom of the form, and the screen says so.
- **Structured attributes earn the coins.** How busy was it, were the showers clean, was the equipment working, how long did you wait, and, at single-gender venues, was the stated access policy actually honoured. That last question is the most valuable in the set and has no other source.
- **The reward is identical for one star and five.** `assertSentimentNeutral()` exists so that if anyone ever adds a sentiment term, a test fails rather than the dataset quietly skewing.
- **A granted, unreversed visit within 72 hours is required.** Otherwise the cheapest way to farm coins is to review venues you have never entered.
- **Every incentivised review is publicly labelled.** The flag is a column that drives a mandatory label, not metadata.
- **Anti-farming:** minimum composition time, duplicate body-hash detection, minimum account age, a rolling 24-hour velocity ceiling, and coin clawback by trigger when a review is removed in moderation.

An award refused does not mean a review refused. A member who has hit their monthly cap still publishes; they are simply not paid. Discarding the review would be the wrong trade.

### 12.4 The honest limit on "follow us for coins"

No major social platform exposes "does user X follow page Y" to a third party. A follow claim is therefore self-attested and trivially farmed, and paying it at full rate is paying for nothing.

So reward size tracks how much the platform can actually prove, through a verification multiplier:

| Verification | Multiplier | Example |
|---|---|---|
| System verified | 1.0 | Referral where the referred member completed a check-in |
| Partner confirmed | 1.0 | Venue confirms the member's content |
| Moderator reviewed | 0.75 | UGC checked by a human |
| Screenshot submitted | 0.35 | Follow evidenced by a screenshot |
| Self-attested | 0.1 | "I followed them", unverifiable |

The marketing mechanics worth funding are the verifiable ones. Referrals pay on the qualifying action, never on signup, because paying at signup buys dormant accounts.

---

## 13. Marketplace (phase 2)

Founder decision: **agent model, verified sellers.** NABD never imports, never holds stock and is never merchant of record. Licensed UAE retailers list; the platform verifies and product liability stays with the seller.

### 13.1 What "authentic products" has to mean

The brief promised "authentic products with full nutritional value". Stated as marketing copy with nothing behind it, that is a warranty the platform cannot honour, and the first counterfeit destroys the claim permanently.

So it is a gate, not a promise. A listing cannot go active without all of:

- a verified seller whose trade licence is current and carries the right trading activity
- a verified, in-date product registration, with the number displayed publicly so a member can check it against the regulator rather than take our word for it
- a passed prohibited-substance screen
- a GMP certificate and a certificate of analysis on file
- Arabic name, ingredients and label image, which are mandatory rather than optional columns
- stock that has not passed its expiry date

`enforce_listing_gates()` refuses the state transition. A daily sweep delists anything whose registration or licence lapses.

### 13.2 The regulatory shape

Supplements in the UAE route to **MOHAP** where there are therapeutic claims or pharmaceutical actives, and to **Dubai Municipality** for vitamins and minerals without disease claims, with Arabic labelling, GMP certification and a certificate of analysis required either way. Several ingredients are prohibited outright and carry criminal exposure, which is why the banned screen blocks listing rather than being a post-hoc check. Therapeutic claims are prohibited on food supplements, so the mandatory disclaimer is attached to the product record rather than left to the seller's copywriting.

**Nutrition is structured, not a PDF.** `nutrition_per_serving` is typed jsonb with energy, macros, amino acid profile and vitamins, because a panel buried in an image cannot be compared, filtered or checked, and comparison is the entire value the member was promised.

### 13.3 What was argued against

First-party retail. Buying, registering, importing and holding stock gives full margin and full control of authenticity, and makes you the importer of record with per-SKU registration, customs, warehousing, returns and criminal exposure on banned ingredients. That is a separate company, not a phase 2 feature of a fitness app.

---

## 14. Academies, programmes and camps (phase 3)

Founder decision: **model the schema now, launch in phase 3.** Sporting club memberships, kids' football and karate, and school break camps are the strongest revenue line in the expanded brief and the heaviest to operate.

### 14.1 Why it is a new primitive

Classes are drop-in. Events are one-off. Neither fits a twelve-week karate course, a season-long football squad or a two-week summer camp, all of which are **fixed cohorts with enrolment, attendance across many sessions, instalment billing and sibling discounts**. Hence `programmes`, distinct from both, with `programme_sessions` and `programme_attendance` beneath it.

### 14.2 Minors change everything

This is a different buyer (the parent), a different trust bar and a different legal exposure.

- **Children have no login.** A child exists as a guardian-managed `child_profiles` record. That also keeps the child's data inside one accountable data-subject relationship for PDPL purposes.
- **Coaches working with minors must hold a cleared, in-date background check.** Enforced twice: a table constraint forbids `works_with_minors` without cleared vetting, and the publication gate refuses a programme whose assigned coach's clearance expires before the programme ends.
- **A programme admitting minors cannot publish** without a verified academy approved for minors, a safeguarding policy and named safeguarding lead on file, current public liability cover valid through the end date, an assigned coach, and a declared supervision ratio.
- **Collection is recorded.** `programme_attendance` captures who collected the child and whether that person was verified against the guardian's authorised list. A verbal arrangement at the gate is exactly where safeguarding fails.
- **Medical notes, allergies and authorised collectors are restricted-role data.** Guardians see their own children and nobody else's; academy staff reach a session register through a server route rather than a policy that would let them enumerate every child.

### 14.3 Licensing

A sports academy in Dubai needs a trade licence carrying the sports instruction activity plus Dubai Sports Council approval, with parallel regimes in the other emirates. Where the offer reads as educational rather than purely recreational, KHDA or the relevant education authority may also apply. That judgement is recorded on the academy record rather than assumed, because it is a judgement and it will be argued about.

---

## 15. Revised roadmap

| Phase | Weeks | Content |
|---|---|---|
| 0 | 1 to 6 | Community only. Clubs, meets, open matches, ratings, Arabic. |
| 1 | 7 to 14 | Ticketed events, tournaments, waivers, permits, payments. |
| 2 | 15 to 26 | The pass: tiers, check-in, caps, partner dashboard, payouts. **Coins launch here**, alongside check-in, because a review economy needs verified visits to exist first. |
| 3 | Month 7 to 10 | Marketplace as agent with verified sellers. Adult club memberships. |
| 4 | Month 10 onward | Academies, kids' programmes and school break camps, once the safeguarding spine is genuinely operational. Corporate seats. |

**Coins cannot ship before check-in.** The entire integrity model rests on a verified visit, and without one the programme is an open invitation to farm. This is the sequencing constraint most likely to be argued with, and it should not be.

---

## 16. Additional open questions

7. **Coin accounting treatment.** Contra-revenue or marketing expense, and what breakage rate to assume. Needs your auditor before the first coin is issued, because restating a loyalty liability afterwards is unpleasant.
8. **Coin value.** The AED rate per coin sets both the redemption economics and the reported liability. Currently a placeholder of 0.05.
9. **Marketplace VAT.** Agent treatment on commission versus principal on gross. Different from the event-ticket question in section 11 and needs its own answer.
10. **Who runs product verification.** Checking registrations and prohibited-substance screens is ongoing operational work, not a one-off onboarding step. It needs an owner before the first listing.
11. **Background check provider.** The UAE has no single DBS equivalent. Which provider, what it actually covers, what it costs per coach, and how often it is refreshed.
12. **Whether to organise camps or host academies.** Same principal-versus-agent question as events in section 11, with a much higher duty of care attached.

---

*Prepared for Athar Farooquei. Not legal advice; the regulatory positions in sections 6, 12, 13 and 14 are a design map and require verification with UAE counsel and a tax adviser before launch. The CBUAE, MOHAP, Dubai Municipality, Dubai Sports Council and KHDA positions summarised here should each be confirmed against current guidance, which moves.*
