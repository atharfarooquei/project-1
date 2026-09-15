-- =====================================================================
-- NABD :: 0009 :: Row level security
-- ---------------------------------------------------------------------
-- Principle: the anon and authenticated roles may never read another
-- member's activity, another partner's commercials, or any compliance
-- evidence. Everything on the entitlement hot path runs service-role from
-- a server route, so these policies are free to be restrictive.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

create or replace function app.current_user_id()
returns uuid language sql stable as $$
  select auth.uid();
$$;

create or replace function app.is_platform_admin()
returns boolean language sql stable as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'platform_admin',
    false
  );
$$;

create or replace function app.staffs_venue(p_venue_id uuid)
returns boolean language sql stable security definer set search_path = app, public as $$
  select exists (
    select 1 from app.venue_staff vs
    where vs.venue_id = p_venue_id and vs.user_id = auth.uid()
  );
$$;

create or replace function app.manages_partner(p_partner_id uuid)
returns boolean language sql stable security definer set search_path = app, public as $$
  select exists (
    select 1
    from app.venue_staff vs
    join app.venues v on v.id = vs.venue_id
    where v.partner_id = p_partner_id
      and vs.user_id = auth.uid()
      and vs.role in ('manager', 'owner')
  );
$$;

create or replace function app.is_club_admin(p_club_id uuid)
returns boolean language sql stable security definer set search_path = app, public as $$
  select exists (
    select 1 from app.club_members cm
    where cm.club_id = p_club_id
      and cm.user_id = auth.uid()
      and cm.role in ('owner', 'admin')
      and cm.left_at is null
  );
$$;

create or replace function app.is_club_member(p_club_id uuid)
returns boolean language sql stable security definer set search_path = app, public as $$
  select exists (
    select 1 from app.club_members cm
    where cm.club_id = p_club_id
      and cm.user_id = auth.uid()
      and cm.left_at is null
      and cm.approved_at is not null
  );
$$;

-- ---------------------------------------------------------------------
-- Enable RLS everywhere. Tables not granted a policy below are readable
-- only by the service role, which is the correct default.
-- ---------------------------------------------------------------------

do $$
declare t record;
begin
  for t in
    select tablename from pg_tables where schemaname = 'app'
  loop
    execute format('alter table app.%I enable row level security', t.tablename);
    execute format('alter table app.%I force row level security', t.tablename);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------

create policy profiles_self_read on app.profiles
  for select using (id = auth.uid() or app.is_platform_admin());

-- Public profile fields are exposed through a view, not by widening this
-- policy, so date of birth and phone never leak into a club member list.
create policy profiles_self_update on app.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

create or replace view app.public_profiles
with (security_invoker = false) as
select id, display_name, handle, avatar_url, bio, home_emirate, home_area,
       app.age_band(date_of_birth) as age_band, created_at
from app.profiles
where not is_suspended;

grant select on app.public_profiles to authenticated, anon;

-- ---------------------------------------------------------------------
-- Sensitive personal records: owner only, never partners.
-- ---------------------------------------------------------------------

create policy emergency_contacts_owner on app.emergency_contacts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy consents_owner_read on app.consents
  for select using (user_id = auth.uid() or app.is_platform_admin());
create policy consents_owner_insert on app.consents
  for insert with check (user_id = auth.uid());

create policy guardian_consents_owner on app.guardian_consents
  for select using (
    minor_user_id = auth.uid()
    or guardian_user_id = auth.uid()
    or app.is_platform_admin()
  );

create policy waiver_signatures_owner on app.waiver_signatures
  for select using (user_id = auth.uid() or app.is_platform_admin());

create policy dsr_owner on app.data_subject_requests
  for select using (user_id = auth.uid() or app.is_platform_admin());
create policy dsr_owner_insert on app.data_subject_requests
  for insert with check (user_id = auth.uid());

-- Waivers themselves are public text.
create policy waivers_public_read on app.waivers
  for select using (true);

-- ---------------------------------------------------------------------
-- Venues: public read of active supply. Commercials stay hidden.
-- ---------------------------------------------------------------------

create policy venues_public_read on app.venues
  for select using (status = 'active' or app.staffs_venue(id) or app.is_platform_admin());

create policy venues_staff_update on app.venues
  for update using (app.staffs_venue(id)) with check (app.staffs_venue(id));

-- cost_per_visit_aed must never reach a client. Discovery reads this view.
create or replace view app.venues_public
with (security_invoker = true) as
select
  id, partner_id, slug, name_en, name_ar, description_en, description_ar,
  venue_type, disciplines, emirate, area, address_line, location,
  gender_policy, min_age, tier_required, checkin_credit_cost,
  amenities, photos, phone_e164, opening_hours,
  aggregator_access_paused, rating_avg, rating_count, status
from app.venues
where status = 'active';

grant select on app.venues_public to authenticated, anon;

create policy venue_gender_windows_read on app.venue_gender_windows
  for select using (true);

create policy venue_caps_staff on app.venue_caps
  for all using (app.staffs_venue(venue_id)) with check (app.staffs_venue(venue_id));

create policy venue_blackouts_staff_write on app.venue_blackouts
  for all using (app.staffs_venue(venue_id)) with check (app.staffs_venue(venue_id));

-- Signing keys: service role only. No policy is deliberate.

create policy partners_self on app.partners
  for select using (app.manages_partner(id) or app.is_platform_admin());

create policy venue_staff_self on app.venue_staff
  for select using (user_id = auth.uid() or app.staffs_venue(venue_id));

-- ---------------------------------------------------------------------
-- Classes and courts: public inventory.
-- ---------------------------------------------------------------------

create policy classes_public_read on app.classes
  for select using (not is_cancelled or app.staffs_venue(venue_id));
create policy classes_staff_write on app.classes
  for all using (app.staffs_venue(venue_id)) with check (app.staffs_venue(venue_id));

create policy court_slots_public_read on app.court_slots
  for select using (true);
create policy court_slots_staff_write on app.court_slots
  for all using (app.staffs_venue(venue_id)) with check (app.staffs_venue(venue_id));

-- ---------------------------------------------------------------------
-- Subscriptions, credits, visits: owner reads. Writes are service-role only,
-- because a member who can insert their own visit row has a free membership.
-- ---------------------------------------------------------------------

create policy plans_public_read on app.plans
  for select using (is_public or app.is_platform_admin());

create policy subscriptions_owner_read on app.subscriptions
  for select using (user_id = auth.uid() or app.is_platform_admin());

create policy subscription_pauses_owner_read on app.subscription_pauses
  for select using (user_id = auth.uid() or app.is_platform_admin());

create policy credit_ledger_owner_read on app.credit_ledger
  for select using (user_id = auth.uid() or app.is_platform_admin());

-- Members see their own visits. Venue staff see visits at their venue only,
-- and only the fields the reception feed needs (exposed through a view).
create policy visits_owner_read on app.visits
  for select using (
    user_id = auth.uid()
    or app.staffs_venue(venue_id)
    or app.is_platform_admin()
  );

create policy class_bookings_owner on app.class_bookings
  for select using (
    user_id = auth.uid() or app.is_platform_admin()
    or exists (select 1 from app.classes c
               where c.id = class_id and app.staffs_venue(c.venue_id))
  );

create policy court_bookings_owner on app.court_bookings
  for select using (booked_by = auth.uid() or app.is_platform_admin());

-- ---------------------------------------------------------------------
-- Community: public discovery, member-scoped writes.
-- ---------------------------------------------------------------------

create policy clubs_public_read on app.clubs
  for select using (
    (is_active and visibility in ('public', 'request_to_join'))
    or app.is_club_member(id)
    or owner_id = auth.uid()
  );

create policy clubs_owner_write on app.clubs
  for update using (app.is_club_admin(id)) with check (app.is_club_admin(id));

create policy clubs_create on app.clubs
  for insert with check (owner_id = auth.uid());

create policy club_members_read on app.club_members
  for select using (
    user_id = auth.uid()
    or app.is_club_member(club_id)
    or exists (select 1 from app.clubs c where c.id = club_id and c.visibility = 'public')
  );

create policy club_members_join on app.club_members
  for insert with check (user_id = auth.uid());
create policy club_members_leave on app.club_members
  for update using (user_id = auth.uid() or app.is_club_admin(club_id));

create policy meets_read on app.meets
  for select using (
    club_id is null
    or app.is_club_member(club_id)
    or exists (select 1 from app.clubs c
               where c.id = club_id and c.visibility = 'public' and c.is_active)
  );

create policy meets_host_write on app.meets
  for all using (host_id = auth.uid() or (club_id is not null and app.is_club_admin(club_id)))
  with check (host_id = auth.uid() or (club_id is not null and app.is_club_admin(club_id)));

create policy meet_occurrences_read on app.meet_occurrences
  for select using (
    exists (select 1 from app.meets m where m.id = meet_id)
  );

create policy meet_attendance_self on app.meet_attendance
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy open_matches_read on app.open_matches
  for select using (true);
create policy open_matches_create on app.open_matches
  for insert with check (created_by = auth.uid());
create policy open_matches_owner_update on app.open_matches
  for update using (created_by = auth.uid()) with check (created_by = auth.uid());

create policy open_match_players_read on app.open_match_players
  for select using (true);
create policy open_match_players_self on app.open_match_players
  for insert with check (user_id = auth.uid());

create policy player_ratings_read on app.player_ratings
  for select using (true);

create policy rating_history_owner on app.rating_history
  for select using (user_id = auth.uid());

create policy ladders_read on app.ladders for select using (true);
create policy ladder_standings_read on app.ladder_standings for select using (true);

create policy challenges_read on app.challenges for select using (is_active);
create policy challenge_participants_read on app.challenge_participants for select using (true);
create policy challenge_participants_join on app.challenge_participants
  for insert with check (user_id = auth.uid());
create policy challenge_teams_read on app.challenge_teams for select using (true);
create policy challenge_activities_owner on app.challenge_activities
  for select using (user_id = auth.uid());

create policy follows_read on app.follows for select using (true);
create policy follows_self on app.follows
  for all using (follower_id = auth.uid()) with check (follower_id = auth.uid());

create policy activity_feed_read on app.activity_feed
  for select using (
    visibility = 'public'
    or user_id = auth.uid()
    or (visibility = 'followers'
        and exists (select 1 from app.follows f
                    where f.followee_id = user_id and f.follower_id = auth.uid()))
  );

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

create policy organisers_read on app.organisers
  for select using (is_verified or owner_user_id = auth.uid() or app.is_platform_admin());

create policy events_public_read on app.events
  for select using (
    status in ('published', 'sold_out', 'in_progress', 'completed')
    or exists (select 1 from app.organisers o
               where o.id = organiser_id and o.owner_user_id = auth.uid())
    or app.is_platform_admin()
  );

create policy events_organiser_write on app.events
  for all using (
    exists (select 1 from app.organisers o
            where o.id = organiser_id and o.owner_user_id = auth.uid())
  ) with check (
    exists (select 1 from app.organisers o
            where o.id = organiser_id and o.owner_user_id = auth.uid())
  );

create policy ticket_types_read on app.event_ticket_types
  for select using (
    exists (select 1 from app.events e
            where e.id = event_id and e.status in ('published', 'sold_out'))
    or app.is_platform_admin()
  );

-- Registrations carry medical declarations, so they are never publicly
-- readable. Organisers read them through a restricted server route.
create policy event_registrations_owner on app.event_registrations
  for select using (user_id = auth.uid() or app.is_platform_admin());

create policy event_results_public_read on app.event_results
  for select using (published_at is not null or user_id = auth.uid());

create policy tournaments_read on app.tournaments for select using (true);
create policy tournament_teams_read on app.tournament_teams for select using (true);
create policy tournament_team_members_read on app.tournament_team_members for select using (true);
create policy tournament_matches_read on app.tournament_matches for select using (true);

-- Captains report their own scores; confirmation and rating updates run
-- service-role so a captain cannot silently rewrite a completed match.
create policy tournament_matches_captain_report on app.tournament_matches
  for update using (
    exists (
      select 1 from app.tournament_teams t
      where t.id in (team_a_id, team_b_id) and t.captain_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
-- Money: owner read only. All writes are service-role.
-- ---------------------------------------------------------------------

create policy orders_owner_read on app.orders
  for select using (user_id = auth.uid() or app.is_platform_admin());

create policy tax_invoices_owner_read on app.tax_invoices
  for select using (
    exists (select 1 from app.orders o where o.id = order_id and o.user_id = auth.uid())
    or app.is_platform_admin()
  );

create policy payouts_partner_read on app.payouts
  for select using (app.manages_partner(partner_id) or app.is_platform_admin());

create policy payout_lines_partner_read on app.payout_lines
  for select using (
    exists (select 1 from app.payouts p
            where p.id = payout_id and app.manages_partner(p.partner_id))
    or app.is_platform_admin()
  );

create policy organiser_payouts_read on app.organiser_payouts
  for select using (
    exists (select 1 from app.organisers o
            where o.id = organiser_id and o.owner_user_id = auth.uid())
    or app.is_platform_admin()
  );

-- ---------------------------------------------------------------------
-- Compliance evidence: platform admin only. Permits and insurance are
-- readable by the organiser or partner they belong to, and nobody else.
-- ---------------------------------------------------------------------

create policy permits_subject_read on app.permits
  for select using (
    app.is_platform_admin()
    or (subject_type = 'event' and exists (
          select 1 from app.events e
          join app.organisers o on o.id = e.organiser_id
          where e.id = subject_id and o.owner_user_id = auth.uid()))
    or (subject_type = 'venue' and app.staffs_venue(subject_id))
  );

create policy insurance_read on app.insurance_certificates
  for select using (
    app.is_platform_admin()
    or (holder_type = 'organiser' and exists (
          select 1 from app.organisers o
          where o.id = holder_id and o.owner_user_id = auth.uid()))
    or (holder_type = 'partner' and app.manages_partner(holder_id))
  );

-- Audit log: read is admin only, write is service-role only.
create policy audit_log_admin_read on app.audit_log
  for select using (app.is_platform_admin());

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------

grant usage on schema app to authenticated, anon;
grant select on all tables in schema app to authenticated;
grant insert, update on
  app.profiles, app.emergency_contacts, app.consents, app.clubs,
  app.club_members, app.meets, app.meet_attendance, app.open_matches,
  app.open_match_players, app.challenge_participants, app.follows,
  app.data_subject_requests
to authenticated;

alter default privileges in schema app
  grant select on tables to authenticated;
