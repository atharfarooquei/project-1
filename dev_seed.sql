-- =====================================================================
-- NABD :: development seed
-- ---------------------------------------------------------------------
-- Realistic UAE fixture data for local development and demos.
--
-- Venue names, partners and clubs below are INVENTED. They are shaped like
-- real UAE supply (areas, price bands, gender policies, padel court counts)
-- so the UI can be judged honestly, but no real business is represented and
-- none of these are partners. Replace before any external demo.
--
-- Coordinates are approximate real locations for the named areas, so the map
-- and the distance sort behave believably.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- Plans
-- ---------------------------------------------------------------------

insert into app.plans
  (code, tier, name_en, name_ar, price_aed, billing_interval, monthly_credits,
   credit_rollover_cap, default_venue_monthly_cap, max_pause_days_per_year, sort_order)
values
  ('community', 'community', 'Community', 'المجتمع', 0, 'month', 0, 0, 0, 0, 0),
  ('core_monthly', 'core', 'Core', 'أساسي', 349, 'month', 30, 15, 4, 30, 1),
  ('elite_monthly', 'elite', 'Elite', 'مميز', 749, 'month', 90, 45, 6, 30, 2),
  ('core_annual', 'core', 'Core Annual', 'أساسي سنوي', 3490, 'year', 30, 15, 4, 45, 3);

-- Padel credit add-on.
insert into app.plans
  (code, tier, name_en, name_ar, price_aed, billing_interval, monthly_credits,
   credit_rollover_cap, default_venue_monthly_cap, is_addon, sort_order)
values
  ('padel_addon', 'core', 'Padel Pack', 'باقة البادل', 199, 'month', 60, 30, 8, true, 4);

-- ---------------------------------------------------------------------
-- Partners (fictional)
-- ---------------------------------------------------------------------

insert into app.partners
  (id, legal_name, trading_name, trading_name_ar, trade_licence_number, licence_authority,
   licence_expires_at, trn, is_vat_registered, per_visit_rate_aed, payout_frequency,
   contract_signed_at, is_active)
values
  ('11111111-1111-4111-8111-111111111111', 'Sahil Fitness Group LLC', 'Sahil Fitness',
   'ساحل للياقة', 'CN-0000001', 'DED Dubai', '2027-03-31', '100000000000001', true,
   22.00, 'monthly', '2026-06-01', true),
  ('22222222-2222-4222-8222-222222222222', 'Barr Athletic Holdings FZ-LLC', 'Barr Athletic',
   'بر الرياضية', 'CN-0000002', 'DMCC', '2027-08-15', '100000000000002', true,
   48.00, 'monthly', '2026-06-15', true),
  ('33333333-3333-4333-8333-333333333333', 'Majlis Padel Courts LLC', 'Majlis Padel',
   'مجلس البادل', 'CN-0000003', 'DED Dubai', '2027-01-20', '100000000000003', true,
   65.00, 'biweekly', '2026-07-01', true),
  ('44444444-4444-4444-8444-444444444444', 'Reem Wellness LLC', 'Reem Wellness',
   'ريم للعافية', 'CN-0000004', 'ADDED', '2027-05-10', '100000000000004', true,
   30.00, 'monthly', '2026-07-10', true);

-- ---------------------------------------------------------------------
-- Venues (fictional). Deliberately spread across tiers, gender policies
-- and emirates so every filter in the Explore screen has something to hit.
-- ---------------------------------------------------------------------

insert into app.venues
  (id, partner_id, slug, name_en, name_ar, venue_type, disciplines, status,
   emirate, area, location, gender_policy, tier_required, checkin_credit_cost,
   cost_per_visit_aed, amenities, opening_hours, sports_permit_number,
   sports_permit_expires_at, geofence_radius_m)
values
  -- Core supply, Dubai
  ('a0000001-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111',
   'sahil-marina', 'Sahil Fitness Marina', 'ساحل للياقة - المارينا',
   'commercial_gym', '{strength,hiit,swimming}', 'active',
   'dubai', 'Dubai Marina', st_point(55.1390, 25.0805)::geography,
   'mixed', 'core', 0, 22.00,
   '{"showers":true,"lockers":true,"parking":true,"prayer_room":true,"pool":true,"towel_service":true}',
   '[{"dow":0,"open":"06:00","close":"23:00"},{"dow":1,"open":"06:00","close":"23:00"},
     {"dow":2,"open":"06:00","close":"23:00"},{"dow":3,"open":"06:00","close":"23:00"},
     {"dow":4,"open":"06:00","close":"23:00"},{"dow":5,"open":"08:00","close":"22:00"},
     {"dow":6,"open":"08:00","close":"22:00"}]',
   'DSC-SE-10001', '2027-04-30', 150),

  ('a0000001-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111',
   'sahil-al-nahda', 'Sahil Fitness Al Nahda', 'ساحل للياقة - النهدة',
   'commercial_gym', '{strength,hiit,boxing}', 'active',
   'sharjah', 'Al Nahda', st_point(55.3708, 25.2960)::geography,
   'mixed', 'core', 0, 18.00,
   '{"showers":true,"lockers":true,"parking":true,"prayer_room":true}',
   '[{"dow":0,"open":"05:30","close":"00:00"},{"dow":1,"open":"05:30","close":"00:00"},
     {"dow":2,"open":"05:30","close":"00:00"},{"dow":3,"open":"05:30","close":"00:00"},
     {"dow":4,"open":"05:30","close":"00:00"},{"dow":5,"open":"07:00","close":"23:00"},
     {"dow":6,"open":"07:00","close":"23:00"}]',
   'SSC-SE-20001', '2027-06-30', 200),

  -- Ladies only, Dubai
  ('a0000001-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111',
   'sahil-ladies-jumeirah', 'Sahil Ladies Jumeirah', 'ساحل للسيدات - جميرا',
   'commercial_gym', '{strength,yoga,pilates,dance}', 'active',
   'dubai', 'Jumeirah 1', st_point(55.2440, 25.2210)::geography,
   'ladies_only', 'core', 0, 26.00,
   '{"showers":true,"lockers":true,"parking":true,"women_only_floor":true,"creche":true,"prayer_room":true}',
   '[{"dow":0,"open":"07:00","close":"22:00"},{"dow":1,"open":"07:00","close":"22:00"},
     {"dow":2,"open":"07:00","close":"22:00"},{"dow":3,"open":"07:00","close":"22:00"},
     {"dow":4,"open":"07:00","close":"22:00"},{"dow":5,"open":"09:00","close":"20:00"},
     {"dow":6,"open":"09:00","close":"20:00"}]',
   'DSC-SE-10002', '2027-04-30', 120),

  -- Elite supply: boutique studio, credit-priced
  ('a0000001-0000-4000-8000-000000000004', '22222222-2222-4222-8222-222222222222',
   'barr-dxb-difc', 'Barr Athletic DIFC', 'بر الرياضية - المركز المالي',
   'boutique_studio', '{hiit,strength,pilates}', 'active',
   'dubai', 'DIFC', st_point(55.2810, 25.2110)::geography,
   'mixed', 'elite', 8, 48.00,
   '{"showers":true,"lockers":true,"towel_service":true,"sauna":true,"wheelchair_access":true}',
   '[{"dow":0,"open":"06:00","close":"21:30"},{"dow":1,"open":"06:00","close":"21:30"},
     {"dow":2,"open":"06:00","close":"21:30"},{"dow":3,"open":"06:00","close":"21:30"},
     {"dow":4,"open":"06:00","close":"21:30"},{"dow":5,"open":"08:00","close":"18:00"},
     {"dow":6,"open":"08:00","close":"18:00"}]',
   'DSC-SE-10003', '2027-02-28', 100),

  -- Elite: crossfit box, ladies hours
  ('a0000001-0000-4000-8000-000000000005', '22222222-2222-4222-8222-222222222222',
   'barr-box-al-quoz', 'Barr Box Al Quoz', 'بر بوكس - القوز',
   'crossfit_box', '{crossfit,hyrox,strength,rowing}', 'active',
   'dubai', 'Al Quoz', st_point(55.2340, 25.1420)::geography,
   'ladies_hours', 'elite', 6, 44.00,
   '{"showers":true,"lockers":true,"parking":true}',
   '[{"dow":0,"open":"05:30","close":"21:00"},{"dow":1,"open":"05:30","close":"21:00"},
     {"dow":2,"open":"05:30","close":"21:00"},{"dow":3,"open":"05:30","close":"21:00"},
     {"dow":4,"open":"05:30","close":"21:00"},{"dow":5,"open":"07:00","close":"14:00"},
     {"dow":6,"open":"07:00","close":"14:00"}]',
   'DSC-SE-10004', '2027-09-30', 150),

  -- Padel, Dubai. Peak rates are why this is credit-priced rather than flat.
  ('a0000001-0000-4000-8000-000000000006', '33333333-3333-4333-8333-333333333333',
   'majlis-padel-al-barsha', 'Majlis Padel Al Barsha', 'مجلس البادل - البرشاء',
   'padel_club', '{padel}', 'active',
   'dubai', 'Al Barsha South', st_point(55.2060, 25.0580)::geography,
   'mixed', 'core', 14, 65.00,
   '{"showers":true,"lockers":true,"parking":true,"padel_courts":6,"prayer_room":true}',
   '[{"dow":0,"open":"06:00","close":"02:00"},{"dow":1,"open":"06:00","close":"02:00"},
     {"dow":2,"open":"06:00","close":"02:00"},{"dow":3,"open":"06:00","close":"02:00"},
     {"dow":4,"open":"06:00","close":"02:00"},{"dow":5,"open":"06:00","close":"02:00"},
     {"dow":6,"open":"06:00","close":"02:00"}]',
   'DSC-SE-10005', '2027-01-31', 180),

  -- Abu Dhabi
  ('a0000001-0000-4000-8000-000000000007', '44444444-4444-4444-8444-444444444444',
   'reem-wellness-al-reem', 'Reem Wellness Al Reem Island', 'ريم للعافية - جزيرة الريم',
   'multi_sport', '{strength,swimming,yoga,hiit}', 'active',
   'abu_dhabi', 'Al Reem Island', st_point(54.4020, 24.4970)::geography,
   'mixed', 'core', 0, 30.00,
   '{"showers":true,"lockers":true,"parking":true,"pool":true,"sauna":true,"prayer_room":true,"creche":true}',
   '[{"dow":0,"open":"06:00","close":"22:00"},{"dow":1,"open":"06:00","close":"22:00"},
     {"dow":2,"open":"06:00","close":"22:00"},{"dow":3,"open":"06:00","close":"22:00"},
     {"dow":4,"open":"06:00","close":"22:00"},{"dow":5,"open":"08:00","close":"20:00"},
     {"dow":6,"open":"08:00","close":"20:00"}]',
   'ADSC-SE-30001', '2027-07-31', 200),

  -- Ajman, men only
  ('a0000001-0000-4000-8000-000000000008', '11111111-1111-4111-8111-111111111111',
   'sahil-ajman', 'Sahil Fitness Ajman', 'ساحل للياقة - عجمان',
   'commercial_gym', '{strength,boxing,martial_arts}', 'active',
   'ajman', 'Al Rashidiya', st_point(55.4450, 25.4050)::geography,
   'men_only', 'core', 0, 15.00,
   '{"showers":true,"lockers":true,"parking":true,"prayer_room":true}',
   '[{"dow":0,"open":"06:00","close":"23:30"},{"dow":1,"open":"06:00","close":"23:30"},
     {"dow":2,"open":"06:00","close":"23:30"},{"dow":3,"open":"06:00","close":"23:30"},
     {"dow":4,"open":"06:00","close":"23:30"},{"dow":5,"open":"08:00","close":"23:30"},
     {"dow":6,"open":"08:00","close":"23:30"}]',
   'AJSC-SE-40001', '2027-03-15', 200);

-- Signing keys for the rotating check-in QR.
insert into app.venue_signing_keys (venue_id)
select id from app.venues;

-- Ladies hours at the Al Quoz box: 09:00 to 12:00, Sunday through Thursday.
insert into app.venue_gender_windows (venue_id, day_of_week, start_time, end_time, policy)
select 'a0000001-0000-4000-8000-000000000005', d, '09:00', '12:00', 'ladies_only'
from generate_series(0, 4) d;

-- ---------------------------------------------------------------------
-- Supply protection. These numbers are the whole reason a gym signs.
-- ---------------------------------------------------------------------

insert into app.venue_caps
  (venue_id, max_daily_checkins, max_concurrent, max_visits_per_user_monthly, cooldown_minutes)
values
  ('a0000001-0000-4000-8000-000000000001', 60, 25, 6, 240),
  ('a0000001-0000-4000-8000-000000000002', 80, 30, 8, 240),
  ('a0000001-0000-4000-8000-000000000003', 40, 15, 6, 240),
  ('a0000001-0000-4000-8000-000000000004', 20,  8, 4, 360),
  ('a0000001-0000-4000-8000-000000000005', 25, 10, 4, 360),
  ('a0000001-0000-4000-8000-000000000006', 40, 24, 8, 120),
  ('a0000001-0000-4000-8000-000000000007', 50, 20, 6, 240),
  ('a0000001-0000-4000-8000-000000000008', 60, 20, 8, 240);

-- Peak-hour blackouts. 18:00 to 20:30 on weekdays at the premium venues:
-- this is exactly the slot a gym will not give away, and pretending otherwise
-- is how the partner churns in month two.
insert into app.venue_blackouts (venue_id, day_of_week, start_time, end_time, reason)
select v.id, d, '18:00', '20:30', 'Peak hours reserved for direct members'
from app.venues v, generate_series(0, 4) d
where v.slug in ('barr-dxb-difc', 'barr-box-al-quoz');

-- Padel peak: Friday and Saturday mornings are the busiest slots in the UAE
-- padel week.
insert into app.venue_blackouts (venue_id, day_of_week, start_time, end_time, reason)
values
  ('a0000001-0000-4000-8000-000000000006', 5, '07:00', '11:00', 'Weekend peak'),
  ('a0000001-0000-4000-8000-000000000006', 6, '07:00', '11:00', 'Weekend peak');

-- ---------------------------------------------------------------------
-- Waivers
-- ---------------------------------------------------------------------

insert into app.waivers
  (id, code, version, title_en, title_ar, body_en, body_ar, effective_from)
values
  ('b0000001-0000-4000-8000-000000000001', 'general_participation', 1,
   'Participation waiver and assumption of risk',
   'إقرار بالمشاركة وتحمل المخاطر',
   'PLACEHOLDER. Replace with text settled by UAE counsel before any live event. '
   'Note that waiver enforceability in the UAE is not absolute, particularly in '
   'respect of gross negligence, and this document does not substitute for public '
   'liability cover.',
   'نص مبدئي. يجب استبداله بنص معتمد من مستشار قانوني في دولة الإمارات قبل أي فعالية فعلية.',
   '2026-01-01'),
  ('b0000001-0000-4000-8000-000000000002', 'outdoor_endurance', 1,
   'Outdoor endurance event waiver',
   'إقرار فعاليات التحمل في الهواء الطلق',
   'PLACEHOLDER. Heat, hydration and remote-location risk disclosures for desert '
   'and road events. Replace before use.',
   'نص مبدئي. يشمل الإفصاح عن مخاطر الحرارة والجفاف والمواقع النائية. يجب استبداله قبل الاستخدام.',
   '2026-01-01');

-- ---------------------------------------------------------------------
-- Ladders and challenges
-- ---------------------------------------------------------------------

insert into app.ladders
  (name_en, name_ar, discipline, emirate, season_label, starts_on, ends_on, challenge_range)
values
  ('Dubai Padel Ladder', 'سلم البادل - دبي', 'padel', 'dubai', '2026 Autumn',
   '2026-10-01', '2026-12-20', 2),
  ('Abu Dhabi Padel Ladder', 'سلم البادل - أبوظبي', 'padel', 'abu_dhabi', '2026 Autumn',
   '2026-10-01', '2026-12-20', 2);

-- Built to ride the two moments a year when the whole country is already
-- primed: Dubai Fitness Challenge in November, and Ramadan.
insert into app.challenges
  (slug, title_en, title_ar, metric, target_value, starts_at, ends_at,
   scope, emirate, allows_teams, team_size_max, accepts_strava, accepts_checkins)
values
  ('dfc-30x30-2026', '30 x 30', 'ثلاثون × ثلاثون', 'duration_min', 900,
   '2026-11-01 00:00+04', '2026-11-30 23:59+04', 'emirate', 'dubai', true, 8, true, true),
  ('night-movement-2027', 'Night Movement', 'حركة الليل', 'distance_km', 100,
   '2027-02-17 18:00+04', '2027-03-18 23:59+04', 'global', null, true, 6, true, true);

commit;

-- ---------------------------------------------------------------------
-- Notes for whoever runs this next
-- ---------------------------------------------------------------------
-- Profiles, subscriptions and clubs are not seeded here because they hang off
-- auth.users, which Supabase owns. Create test users through the Auth API or
-- Studio first, then run supabase/seed/dev_seed_members.sql, which is not
-- written yet.
--
-- Before any external demo: replace every venue and partner name above. They
-- are invented, and a demo that looks like it shows real signed partners is a
-- misrepresentation whether or not anyone says the word out loud.
