-- =====================================================================
-- NABD :: 0008 :: Orders, VAT invoicing, partner payouts
-- ---------------------------------------------------------------------
-- Partners churn over payment opacity more often than over rates. Every
-- payout line traces to a visit or a booking row.
-- =====================================================================

create table app.orders (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references app.profiles(id) on delete restrict,

  kind              text not null check (kind in
                    ('subscription', 'credit_pack', 'event_ticket',
                     'court_booking', 'class_booking', 'tournament_entry')),
  ref_type          text,
  ref_id            uuid,

  currency          char(3) not null default 'AED',
  -- Net + VAT = gross. Stored explicitly; never derived at read time, because
  -- the VAT rate can change and historic invoices must not move.
  subtotal_aed      numeric(12,2) not null check (subtotal_aed >= 0),
  vat_rate_pct      numeric(5,2) not null default 5.00,
  vat_amount_aed    numeric(12,2) not null default 0,
  discount_aed      numeric(12,2) not null default 0,
  total_aed         numeric(12,2) not null check (total_aed >= 0),
  credits_applied   integer not null default 0,

  -- Agent vs principal decides whether the gross ticket value is our revenue
  -- or a pass-through with only the fee as revenue.
  supply_role       app.supply_role not null default 'principal',
  platform_fee_aed  numeric(12,2) not null default 0,

  provider          app.payment_provider not null,
  provider_payment_id text,
  provider_customer_id text,
  status            app.payment_status not null default 'processing',

  -- BNPL is enabled for annual plans and event tickets only. Monthly
  -- subscription economics do not survive BNPL fees.
  bnpl_provider     app.payment_provider,
  bnpl_reference    text,

  paid_at           timestamptz,
  refunded_amount_aed numeric(12,2) not null default 0,
  refunded_at       timestamptz,
  failure_code      text,

  idempotency_key   text unique,
  metadata          jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index orders_user_idx     on app.orders (user_id, created_at desc);
create index orders_provider_idx on app.orders (provider, provider_payment_id);
create index orders_status_idx   on app.orders (status, created_at desc);
create index orders_ref_idx      on app.orders (ref_type, ref_id);

alter table app.event_registrations
  add constraint event_registrations_order_fk
  foreign key (order_id) references app.orders(id) on delete set null;

-- ---------------------------------------------------------------------
-- Tax invoices. Sequential numbering is a UAE VAT requirement, so the
-- number comes from a sequence and is never assembled in application code.
-- ---------------------------------------------------------------------

create sequence app.tax_invoice_seq start 1;

create table app.tax_invoices (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references app.orders(id) on delete restrict,
  invoice_number    text not null unique
                    default ('INV-' || to_char(now(), 'YYYY') || '-' ||
                             lpad(nextval('app.tax_invoice_seq')::text, 7, '0')),
  issued_at         timestamptz not null default now(),

  supplier_name     text not null,
  supplier_trn      text not null,
  supplier_address  text not null,

  customer_name     text not null,
  customer_email    citext,
  customer_trn      text,          -- set for B2B / corporate seats

  -- Place of supply drives whether UAE VAT applies at all.
  place_of_supply   text not null default 'UAE',

  currency          char(3) not null default 'AED',
  subtotal_aed      numeric(12,2) not null,
  vat_rate_pct      numeric(5,2) not null,
  vat_amount_aed    numeric(12,2) not null,
  total_aed         numeric(12,2) not null,

  line_items        jsonb not null default '[]'::jsonb,
  pdf_url           text,
  -- Credit note pointer when this invoice has been reversed.
  credit_note_for   uuid references app.tax_invoices(id),
  created_at        timestamptz not null default now()
);

create index tax_invoices_order_idx on app.tax_invoices (order_id);
create index tax_invoices_issued_idx on app.tax_invoices (issued_at desc);

comment on table app.tax_invoices is
  'UAE VAT: sequential numbering, supplier TRN and place of supply are mandatory. Agent vs principal treatment on event tickets requires tax advice before launch.';

-- ---------------------------------------------------------------------
-- Partner payouts
-- ---------------------------------------------------------------------

create table app.payouts (
  id                uuid primary key default gen_random_uuid(),
  partner_id        uuid not null references app.partners(id) on delete restrict,
  period_start      date not null,
  period_end        date not null,

  visits_count      integer not null default 0,
  class_fills_count integer not null default 0,
  court_bookings_count integer not null default 0,

  gross_aed         numeric(12,2) not null default 0,
  -- Partner-side VAT only where the partner is VAT registered.
  vat_aed           numeric(12,2) not null default 0,
  adjustments_aed   numeric(12,2) not null default 0,
  net_payable_aed   numeric(12,2) not null default 0,

  status            app.payout_status not null default 'accruing',
  approved_by       uuid references app.profiles(id),
  approved_at       timestamptz,
  paid_at           timestamptz,
  remittance_reference text,
  statement_url     text,
  dispute_notes     text,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (partner_id, period_start, period_end),
  constraint payouts_period_order check (period_end >= period_start)
);

create index payouts_partner_idx on app.payouts (partner_id, period_start desc);
create index payouts_status_idx  on app.payouts (status);

-- Every line traces to a source row. This is what ends a payout dispute.
create table app.payout_lines (
  id            bigserial primary key,
  payout_id     uuid not null references app.payouts(id) on delete cascade,
  venue_id      uuid not null references app.venues(id) on delete restrict,
  source_type   text not null check (source_type in
                ('visit', 'class_booking', 'court_booking', 'adjustment')),
  source_id     uuid,
  occurred_at   timestamptz not null,
  rate_aed      numeric(8,2) not null,
  quantity      integer not null default 1,
  amount_aed    numeric(10,2) not null,
  notes         text,
  created_at    timestamptz not null default now()
);

create index payout_lines_payout_idx on app.payout_lines (payout_id, venue_id);
create index payout_lines_source_idx on app.payout_lines (source_type, source_id);

-- ---------------------------------------------------------------------
-- Organiser payouts for ticketed events
-- ---------------------------------------------------------------------

create table app.organiser_payouts (
  id                uuid primary key default gen_random_uuid(),
  organiser_id      uuid not null references app.organisers(id) on delete restrict,
  event_id          uuid not null references app.events(id) on delete restrict,
  tickets_sold      integer not null default 0,
  gross_aed         numeric(12,2) not null default 0,
  platform_fee_aed  numeric(12,2) not null default 0,
  payment_fees_aed  numeric(12,2) not null default 0,
  refunds_aed       numeric(12,2) not null default 0,
  net_payable_aed   numeric(12,2) not null default 0,
  status            app.payout_status not null default 'accruing',
  -- Funds held until the event completes, so a cancelled event can be
  -- refunded from money we still hold.
  hold_until        timestamptz,
  paid_at           timestamptz,
  remittance_reference text,
  created_at        timestamptz not null default now(),
  unique (organiser_id, event_id)
);

-- ---------------------------------------------------------------------
-- Webhook inbox. Provider events land here first and are processed
-- idempotently, so a Stripe retry storm cannot double-credit an account.
-- ---------------------------------------------------------------------

create table app.webhook_events (
  id            uuid primary key default gen_random_uuid(),
  provider      app.payment_provider not null,
  provider_event_id text not null,
  event_type    text not null,
  payload       jsonb not null,
  signature_verified boolean not null default false,
  processed_at  timestamptz,
  processing_error text,
  attempts      integer not null default 0,
  received_at   timestamptz not null default now(),
  unique (provider, provider_event_id)
);

create index webhook_events_unprocessed_idx on app.webhook_events (received_at)
  where processed_at is null;
