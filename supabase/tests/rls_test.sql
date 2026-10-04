-- Row-level security and integrity checks for the LaxPocket schema.
-- Run with supabase/tests/run-local.sh. Any failed assert stops the run.
--
-- Accounts: A owns a profile, B is a second family member, C is a stranger.

\set ON_ERROR_STOP 1

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com'),
  ('00000000-0000-4000-8000-00000000000c', 'c@example.com');

-- ---------------------------------------------------------------------------
-- A creates a profile with one of everything
-- ---------------------------------------------------------------------------
set request.jwt.claim.sub = '00000000-0000-4000-8000-00000000000a';
set role authenticated;

insert into public.profiles (id, first_name, class_year, benchmark_group, weekly_goal_hours, season_label, season_budget, theme_id)
values ('10000000-0000-4000-8000-000000000001', 'Sam', 2031, 'u15Women', 12.5, '2026/27', 14000, 'northwestern');

insert into public.programs (profile_id, id, name, program_group, session_category, monogram, sort_order) values
  ('10000000-0000-4000-8000-000000000001', 'club', 'Club 2031', 'teams', 'team', 'C31', 0),
  ('10000000-0000-4000-8000-000000000001', 'combine', 'Combine', 'combine', null, 'TC', 1);

insert into public.training_sessions (id, profile_id, program_id, started_at, category, minutes, effort, focus)
values ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'club',
        '2026-09-21T18:00:00Z', 'team', 90, 7, '{Dodging,Defence}');

insert into public.combine_results (id, profile_id, tested_at, event_name)
values ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '2026-08-20T09:00:00Z', 'Baseline');
insert into public.combine_measurements (result_id, profile_id, metric, value) values
  ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'gripLeft', 262),
  ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'sprint10m', 1.965);

insert into public.season_events (id, profile_id, kind, title, team, opponent, starts_at, our_score, their_score)
values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'game', 'vs Rivals', 'Club 2031', 'Rivals',
        '2026-09-26T12:00:00Z', 11, 7);
insert into public.game_stats (event_id, profile_id, goals, assists, shots, ground_balls, draw_controls, caused_turnovers)
values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 2, 1, 5, 4, 3, 1);
insert into public.game_reflections (event_id, profile_id, self_rating, went_well)
values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 7, 'Draws');
insert into public.event_focus_goals (id, event_id, profile_id, position, goal, outcome)
values ('21000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 0, 'Win 3+ draws', 'hit');
insert into public.event_videos (id, event_id, profile_id, position, title, url)
values ('22000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 0, 'Highlights', 'https://example.com/v/1');
insert into public.event_checklist_items (id, event_id, profile_id, position, title, done)
values ('23000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 0, 'Registration', true);

insert into public.expenses (id, profile_id, spent_at, title, category, amount)
values ('50000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '2026-09-01T12:00:00Z', 'Season fee', 'teamFees', 1850);
insert into public.mental_docs (id, profile_id, title, url, folder, kind, status, doc_updated_at)
values ('60000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Pre-game routine',
        'https://docs.google.com/document/d/abc', 'routines', 'word', 'toReview', '2026-09-22T12:00:00Z');
insert into public.body_measurements (id, profile_id, measured_at, height_cm, weight_kg) values
  ('70000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '2026-06-01T12:00:00Z', 160.0, 48.5),
  ('70000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '2026-09-28T12:00:00Z', null, 49.9);
insert into public.wallball_drills (profile_id, id, name, hands, default_reps)
values ('10000000-0000-4000-8000-000000000001', 'twister', 'Twister', 'each', 20);
insert into public.wallball_sessions (id, profile_id, done_at, minutes)
values ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '2026-09-28T16:00:00Z', 20);
insert into public.wallball_sessions (id, profile_id, done_at, challenge_seconds)
values ('80000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '2026-09-29T16:00:00Z', 30);
insert into public.wallball_sets (session_id, profile_id, drill_id, hand, reps, position) values
  ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'overhand', 'right', 50, 0),
  ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'overhand', 'left', 50, 1),
  ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'switch-hands', 'both', 30, 2),
  ('80000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'quick-sticks', 'right', 41, 0);

-- Budgets: the club team runs three seasons with a budget for two of them; the season fee is for the club.
update public.programs set first_season = 2026, last_season = 2028 where id = 'club';
insert into public.season_budgets (profile_id, season, amount) values ('10000000-0000-4000-8000-000000000001', 2026, 14000);
insert into public.program_budgets (profile_id, program_id, season, amount) values
  ('10000000-0000-4000-8000-000000000001', 'club', 2026, 3000),
  ('10000000-0000-4000-8000-000000000001', 'club', 2027, 3200);
update public.expenses set program_id = 'club', season = 2026 where id = '50000000-0000-4000-8000-000000000001';

-- The same upsert PostgREST runs for "resolution=merge-duplicates".
insert into public.profiles (id, first_name) values ('10000000-0000-4000-8000-000000000001', 'Sam K')
on conflict (id) do update set first_name = excluded.first_name;

do $$
begin
  assert (select count(*) from public.profiles) = 1, 'A sees their profile';
  assert (select first_name from public.profiles) = 'Sam K', 'A can upsert their profile';
  assert (select created_by from public.profiles) = '00000000-0000-4000-8000-00000000000a', 'created_by defaults to the caller';
  assert (select role from public.profile_members where user_id = '00000000-0000-4000-8000-00000000000a') = 'owner', 'creator becomes owner';
  assert (select count(*) from public.programs) = 2, 'A sees programs';
  assert (select count(*) from public.training_sessions) = 1, 'A sees sessions';
  assert (select count(*) from public.combine_measurements) = 2, 'A sees measurements';
  assert (select count(*) from public.game_stats) = 1, 'A sees stats';
  assert (select count(*) from public.event_focus_goals) = 1, 'A sees focus goals';
  assert (select count(*) from public.expenses) = 1, 'A sees expenses';
  assert (select count(*) from public.mental_docs) = 1, 'A sees docs';
  assert (select count(*) from public.body_measurements) = 2, 'A sees height and weight';
  assert (select body_units from public.profiles) = 'imperial', 'profiles default to imperial units';
  assert (select count(*) from public.wallball_drills) = 1, 'A sees wall ball drills';
  assert (select count(*) from public.wallball_sessions) = 2, 'A sees wall ball sessions';
  assert (select sum(reps) from public.wallball_sets) = 171, 'A sees wall ball reps';
  assert (select amount from public.season_budgets where season = 2026) = 14000, 'A sees the season budget';
  assert (select sum(amount) from public.program_budgets where program_id = 'club') = 6200, 'A sees a budget per season for the club';
  assert (select program_id from public.expenses) = 'club', 'an expense can be for a program';
end
$$;

-- The NDTP age group is optional.
insert into public.profiles (id, first_name) values ('10000000-0000-4000-8000-000000000003', 'No NDTP');
do $$
begin
  assert (select benchmark_group is null from public.profiles where id = '10000000-0000-4000-8000-000000000003'),
    'a profile has no NDTP group unless one is picked';
  assert (select benchmark_group from public.profiles where id = '10000000-0000-4000-8000-000000000001') = 'u15Women', 'a picked group stays';
end
$$;
delete from public.profiles where id = '10000000-0000-4000-8000-000000000003';

-- Can't create a profile on someone else's behalf.
do $$
declare failed boolean := false;
begin
  begin
    insert into public.profiles (first_name, created_by) values ('Nope', '00000000-0000-4000-8000-00000000000b');
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'created_by must be the caller';
end
$$;

-- A program with sessions can't be deleted out from under them.
do $$
declare failed boolean := false;
begin
  begin
    delete from public.programs where id = 'club';
  exception when foreign_key_violation then failed := true;
  end;
  assert failed, 'program with sessions is protected';
end
$$;

-- Deleting a program removes its budgets and keeps its expenses, unlinked.
insert into public.programs (profile_id, id, name, program_group, first_season, last_season)
values ('10000000-0000-4000-8000-000000000001', 'camp', 'Summer camp', 'showcases', 2026, 2026);
insert into public.program_budgets (profile_id, program_id, season, amount) values ('10000000-0000-4000-8000-000000000001', 'camp', 2026, 600);
insert into public.expenses (id, profile_id, spent_at, title, category, amount, program_id, season)
values ('50000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '2026-07-15T12:00:00Z', 'Camp deposit', 'showcases', 150, 'camp', 2026);
delete from public.programs where id = 'camp';
do $$
begin
  assert not exists (select 1 from public.program_budgets where program_id = 'camp'), 'a deleted program''s budgets go with it';
  assert (select program_id is null and season = 2026 and amount = 150 from public.expenses
          where id = '50000000-0000-4000-8000-000000000002'), 'its expenses stay, without the link';
end
$$;
delete from public.expenses where id = '50000000-0000-4000-8000-000000000002';

-- Tournament trips: a trip to a tournament with the club, and what it cost.
insert into public.season_events (id, profile_id, kind, title, starts_at, ends_at, location)
values ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'tournament', 'Fall Brawl',
        '2026-10-16T12:00:00Z', '2026-10-18T20:00:00Z', 'Baltimore, MD');
insert into public.trips (id, profile_id, name, destination, country, departs_at, returns_at, season, program_id, event_id, budget,
                          travel_mode, hotel_name, hotel_confirmation)
values ('90000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Fall Brawl', 'Baltimore, MD', 'US',
        '2026-10-15T12:00:00Z', '2026-10-18T22:00:00Z', 2026, 'club', '20000000-0000-4000-8000-000000000002', 2500, 'drive',
        'Harbour Inn', 'ABC123');
insert into public.expenses (id, profile_id, spent_at, title, category, amount, program_id, season, trip_id) values
  ('50000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', '2026-09-10T12:00:00Z', 'Entry fee', 'tournamentFees', 400, 'club', 2026, '90000000-0000-4000-8000-000000000001'),
  ('50000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', '2026-10-18T12:00:00Z', 'Hotel, 3 nights', 'lodging', 690, 'club', 2026, '90000000-0000-4000-8000-000000000001'),
  ('50000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', '2026-10-17T12:00:00Z', 'Team dinner', 'food', 85.5, null, 2026, '90000000-0000-4000-8000-000000000001'),
  ('50000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', '2026-10-15T12:00:00Z', 'Tolls', 'other', 22, null, 2026, '90000000-0000-4000-8000-000000000001');
-- The hotel was paid in US dollars: US$500 at 1.38.
update public.expenses set currency = 'USD', original_amount = 500 where id = '50000000-0000-4000-8000-000000000004';
do $$
begin
  assert (select sum(amount) from public.expenses where trip_id = '90000000-0000-4000-8000-000000000001') = 1197.5, 'A sees what the trip cost';
  assert (select currency = 'USD' and original_amount = 500 and amount = 690 from public.expenses
          where id = '50000000-0000-4000-8000-000000000004'), 'an expense keeps what was paid in US dollars and its CAD amount';
  assert (select count(*) from public.expenses where currency = 'CAD' and original_amount is null) = 4, 'expenses are CAD by default';
  assert (select usd_to_cad from public.profiles) = 1.38, 'profiles start with the built-in exchange rate';
  assert (select hotel_check_in is null and travel_details = '' and note = '' from public.trips), 'trip details default to blank';
end
$$;

-- Deleting the event keeps the trip; deleting the trip keeps its expenses. Both clear the link.
delete from public.season_events where id = '20000000-0000-4000-8000-000000000002';
do $$
begin
  assert (select event_id is null and program_id = 'club' from public.trips), 'a deleted event''s trip stays, without the link';
end
$$;
insert into public.trips (id, profile_id, name, departs_at, returns_at, season)
values ('90000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Day trip', '2026-11-01T12:00:00Z', '2026-11-01T12:00:00Z', 2026);
update public.expenses set trip_id = '90000000-0000-4000-8000-000000000002' where id = '50000000-0000-4000-8000-000000000006';
delete from public.trips where id = '90000000-0000-4000-8000-000000000002';
do $$
begin
  assert (select trip_id is null and amount = 22 from public.expenses where id = '50000000-0000-4000-8000-000000000006'),
    'a deleted trip''s expenses stay, without the link';
end
$$;
delete from public.expenses where id in ('50000000-0000-4000-8000-000000000003', '50000000-0000-4000-8000-000000000004',
                                         '50000000-0000-4000-8000-000000000005', '50000000-0000-4000-8000-000000000006');

-- Data checks.
do $$
declare failed boolean;
begin
  failed := false;
  begin
    insert into public.season_events (profile_id, kind, starts_at, ends_at)
    values ('10000000-0000-4000-8000-000000000001', 'camp', '2026-10-02T00:00:00Z', '2026-10-01T00:00:00Z');
  exception when check_violation then failed := true;
  end;
  assert failed, 'events can''t end before they start';

  failed := false;
  begin
    insert into public.season_events (profile_id, kind, starts_at, our_score)
    values ('10000000-0000-4000-8000-000000000001', 'game', '2026-10-02T00:00:00Z', 3);
  exception when check_violation then failed := true;
  end;
  assert failed, 'a score needs both sides';

  failed := false;
  begin
    insert into public.training_sessions (profile_id, program_id, started_at, category, minutes, effort)
    values ('10000000-0000-4000-8000-000000000001', 'club', now(), 'team', 60, 11);
  exception when check_violation then failed := true;
  end;
  assert failed, 'effort is 1–10';

  failed := false;
  begin
    insert into public.training_sessions (profile_id, program_id, started_at, category, minutes, effort)
    values ('10000000-0000-4000-8000-000000000001', 'no-such-program', now(), 'team', 60, 5);
  exception when foreign_key_violation then failed := true;
  end;
  assert failed, 'sessions need a program in the same profile';

  failed := false;
  begin
    insert into public.mental_docs (profile_id, title, url, folder, kind, doc_updated_at)
    values ('10000000-0000-4000-8000-000000000001', 'x', 'javascript:alert(1)', 'goals', 'link', now());
  exception when check_violation then failed := true;
  end;
  assert failed, 'doc links must be http(s)';

  failed := false;
  begin
    insert into public.body_measurements (profile_id, measured_at)
    values ('10000000-0000-4000-8000-000000000001', now());
  exception when check_violation then failed := true;
  end;
  assert failed, 'a measurement needs a height or a weight';

  failed := false;
  begin
    insert into public.body_measurements (profile_id, measured_at, height_cm)
    values ('10000000-0000-4000-8000-000000000001', now(), 5.4);
  exception when check_violation then failed := true;
  end;
  assert failed, 'heights are in centimetres';

  failed := false;
  begin
    insert into public.body_measurements (profile_id, measured_at, weight_kg)
    values ('10000000-0000-4000-8000-000000000001', now(), 400);
  exception when check_violation then failed := true;
  end;
  assert failed, 'weights are in kilograms';

  failed := false;
  begin
    update public.profiles set body_units = 'stone' where id = '10000000-0000-4000-8000-000000000001';
  exception when check_violation then failed := true;
  end;
  assert failed, 'units are imperial or metric';

  failed := false;
  begin
    insert into public.wallball_sets (session_id, profile_id, drill_id, hand, reps)
    values ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'sidearm', 'right', 0);
  exception when check_violation then failed := true;
  end;
  assert failed, 'a set has at least one rep';

  failed := false;
  begin
    insert into public.wallball_sets (session_id, profile_id, drill_id, hand, reps)
    values ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'sidearm', 'feet', 10);
  exception when check_violation then failed := true;
  end;
  assert failed, 'hands are right, left or both';

  failed := false;
  begin
    insert into public.wallball_sets (session_id, profile_id, drill_id, hand, reps)
    values ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'overhand', 'right', 10);
  exception when unique_violation then failed := true;
  end;
  assert failed, 'one set per drill and hand in a session';

  failed := false;
  begin
    insert into public.wallball_sessions (profile_id, done_at, challenge_seconds)
    values ('10000000-0000-4000-8000-000000000001', now(), 2);
  exception when check_violation then failed := true;
  end;
  assert failed, 'challenge rounds are at least 5 seconds';

  failed := false;
  begin
    insert into public.wallball_drills (profile_id, id, name, hands)
    values ('10000000-0000-4000-8000-000000000001', 'x', 'X', 'feet');
  exception when check_violation then failed := true;
  end;
  assert failed, 'drills are done with each hand or both together';

  failed := false;
  begin
    update public.programs set first_season = 2028, last_season = 2026 where id = 'club';
  exception when check_violation then failed := true;
  end;
  assert failed, 'a program can''t end before it starts';

  failed := false;
  begin
    insert into public.season_budgets (profile_id, season, amount) values ('10000000-0000-4000-8000-000000000001', 1999, 100);
  exception when check_violation then failed := true;
  end;
  assert failed, 'seasons start in 2000 or later';

  failed := false;
  begin
    insert into public.program_budgets (profile_id, program_id, season, amount) values ('10000000-0000-4000-8000-000000000001', 'club', 2028, -1);
  exception when check_violation then failed := true;
  end;
  assert failed, 'budgets aren''t negative';

  failed := false;
  begin
    insert into public.program_budgets (profile_id, program_id, season, amount) values ('10000000-0000-4000-8000-000000000001', 'club', 2026, 1);
  exception when unique_violation then failed := true;
  end;
  assert failed, 'one budget per program and season';

  failed := false;
  begin
    insert into public.program_budgets (profile_id, program_id, season, amount) values ('10000000-0000-4000-8000-000000000001', 'nope', 2026, 100);
  exception when foreign_key_violation then failed := true;
  end;
  assert failed, 'program budgets need a program';

  failed := false;
  begin
    insert into public.expenses (profile_id, spent_at, category, amount, program_id) values ('10000000-0000-4000-8000-000000000001', now(), 'travel', 10, 'nope');
  exception when foreign_key_violation then failed := true;
  end;
  assert failed, 'an expense''s program has to exist';

  failed := false;
  begin
    insert into public.expenses (profile_id, spent_at, category, amount) values ('10000000-0000-4000-8000-000000000001', now(), 'jewellery', 10);
  exception when check_violation then failed := true;
  end;
  assert failed, 'expense categories are checked';

  failed := false;
  begin
    insert into public.expenses (profile_id, spent_at, category, amount, trip_id)
    values ('10000000-0000-4000-8000-000000000001', now(), 'food', 10, '90000000-0000-4000-8000-0000000000ff');
  exception when foreign_key_violation then failed := true;
  end;
  assert failed, 'an expense''s trip has to exist';

  failed := false;
  begin
    insert into public.trips (profile_id, name, departs_at, returns_at, season)
    values ('10000000-0000-4000-8000-000000000001', 'Backwards', '2026-10-18T00:00:00Z', '2026-10-15T00:00:00Z', 2026);
  exception when check_violation then failed := true;
  end;
  assert failed, 'trips can''t end before they start';

  failed := false;
  begin
    insert into public.trips (profile_id, name, departs_at, returns_at, season, hotel_check_in, hotel_check_out)
    values ('10000000-0000-4000-8000-000000000001', 'Hotel', '2026-10-15T00:00:00Z', '2026-10-18T00:00:00Z', 2026,
            '2026-10-17T00:00:00Z', '2026-10-16T00:00:00Z');
  exception when check_violation then failed := true;
  end;
  assert failed, 'hotel check-out is after check-in';

  failed := false;
  begin
    insert into public.trips (profile_id, name, country, departs_at, returns_at, season)
    values ('10000000-0000-4000-8000-000000000001', 'Away', 'Narnia', now(), now(), 2026);
  exception when check_violation then failed := true;
  end;
  assert failed, 'trip countries are checked';

  failed := false;
  begin
    insert into public.trips (profile_id, name, departs_at, returns_at, season, travel_mode)
    values ('10000000-0000-4000-8000-000000000001', 'Away', now(), now(), 2026, 'teleport');
  exception when check_violation then failed := true;
  end;
  assert failed, 'travel modes are checked';

  failed := false;
  begin
    insert into public.expenses (profile_id, spent_at, category, amount, currency, original_amount)
    values ('10000000-0000-4000-8000-000000000001', now(), 'food', 10, 'EUR', 7);
  exception when check_violation then failed := true;
  end;
  assert failed, 'currencies are CAD or USD';

  failed := false;
  begin
    insert into public.expenses (profile_id, spent_at, category, amount, currency)
    values ('10000000-0000-4000-8000-000000000001', now(), 'food', 10, 'USD');
  exception when check_violation then failed := true;
  end;
  assert failed, 'a US-dollar expense keeps what was paid';

  failed := false;
  begin
    insert into public.expenses (profile_id, spent_at, category, amount, original_amount)
    values ('10000000-0000-4000-8000-000000000001', now(), 'food', 10, 7);
  exception when check_violation then failed := true;
  end;
  assert failed, 'a CAD expense has no other amount';

  failed := false;
  begin
    update public.profiles set usd_to_cad = 0 where id = '10000000-0000-4000-8000-000000000001';
  exception when check_violation then failed := true;
  end;
  assert failed, 'the exchange rate is in a sensible range';
end
$$;

-- ---------------------------------------------------------------------------
-- B can't see or touch A's profile
-- ---------------------------------------------------------------------------
reset role;
set request.jwt.claim.sub = '00000000-0000-4000-8000-00000000000b';
set role authenticated;

insert into public.profiles (id, first_name) values ('10000000-0000-4000-8000-000000000002', 'Alex');

do $$
declare failed boolean;
begin
  assert (select count(*) from public.profiles) = 1, 'B sees only their own profile';
  assert (select count(*) from public.programs) = 0, 'B sees none of A''s programs';
  assert (select count(*) from public.training_sessions) = 0, 'B sees none of A''s sessions';
  assert (select count(*) from public.season_events) = 0, 'B sees none of A''s events';
  assert (select count(*) from public.game_reflections) = 0, 'B sees none of A''s reflections';
  assert (select count(*) from public.body_measurements) = 0, 'B sees none of A''s height and weight';
  assert (select count(*) from public.wallball_sessions) = 0, 'B sees none of A''s wall ball';
  assert (select count(*) from public.wallball_sets) = 0, 'B sees none of A''s wall ball reps';
  assert (select count(*) from public.season_budgets) = 0, 'B sees none of A''s season budgets';
  assert (select count(*) from public.program_budgets) = 0, 'B sees none of A''s program budgets';
  assert (select count(*) from public.trips) = 0, 'B sees none of A''s trips';
  assert (select count(*) from public.profile_members) = 1, 'B sees only their own membership';

  update public.profiles set first_name = 'Hacked' where id = '10000000-0000-4000-8000-000000000001';
  delete from public.expenses where profile_id = '10000000-0000-4000-8000-000000000001';
  update public.body_measurements set weight_kg = 99 where profile_id = '10000000-0000-4000-8000-000000000001';
  update public.wallball_sets set reps = 999 where profile_id = '10000000-0000-4000-8000-000000000001';
  delete from public.wallball_drills where profile_id = '10000000-0000-4000-8000-000000000001';
  update public.season_budgets set amount = 1 where profile_id = '10000000-0000-4000-8000-000000000001';
  delete from public.program_budgets where profile_id = '10000000-0000-4000-8000-000000000001';
  update public.trips set hotel_name = 'Hacked' where profile_id = '10000000-0000-4000-8000-000000000001';

  failed := false;
  begin
    insert into public.wallball_sessions (profile_id, done_at)
    values ('10000000-0000-4000-8000-000000000001', now());
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'B can''t log wall ball for A''s profile';

  failed := false;
  begin
    insert into public.body_measurements (profile_id, measured_at, weight_kg)
    values ('10000000-0000-4000-8000-000000000001', now(), 50);
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'B can''t log height and weight for A''s profile';

  failed := false;
  begin
    insert into public.programs (profile_id, id, name, program_group)
    values ('10000000-0000-4000-8000-000000000001', 'x', 'X', 'teams');
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'B can''t add to A''s profile';

  failed := false;
  begin
    insert into public.profiles (id, first_name) values ('10000000-0000-4000-8000-000000000001', 'Taken')
    on conflict (id) do update set first_name = excluded.first_name;
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'B can''t take over A''s profile with an upsert';

  failed := false;
  begin
    -- Claims B's own profile, but points at A's event.
    insert into public.event_focus_goals (event_id, profile_id, goal)
    values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'Sneak in');
  exception when foreign_key_violation then failed := true;
  end;
  assert failed, 'child rows must match their event''s profile';

  failed := false;
  begin
    -- B's own profile, pointing at A's trip.
    insert into public.expenses (profile_id, spent_at, category, amount, trip_id)
    values ('10000000-0000-4000-8000-000000000002', now(), 'food', 10, '90000000-0000-4000-8000-000000000001');
  exception when foreign_key_violation then failed := true;
  end;
  assert failed, 'an expense can''t point at another profile''s trip';

  failed := false;
  begin
    perform public.share_profile('10000000-0000-4000-8000-000000000001', 'b@example.com', 'editor');
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'only the owner can share';

  failed := false;
  begin
    insert into public.profile_members (profile_id, user_id, role)
    values ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000b', 'owner');
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'B can''t add themselves to A''s profile';
end
$$;

reset role;
do $$
begin
  assert (select first_name from public.profiles where id = '10000000-0000-4000-8000-000000000001') = 'Sam K', 'B''s update did nothing';
  assert (select count(*) from public.expenses) = 1, 'B''s delete did nothing';
  assert (select weight_kg from public.body_measurements where id = '70000000-0000-4000-8000-000000000001') = 48.5, 'B''s weight change did nothing';
  assert (select sum(reps) from public.wallball_sets) = 171, 'B''s reps change did nothing';
  assert (select count(*) from public.wallball_drills) = 1, 'B''s drill delete did nothing';
  assert (select hotel_name from public.trips) = 'Harbour Inn', 'B''s trip change did nothing';
end
$$;

-- ---------------------------------------------------------------------------
-- A shares with B: first as viewer, then as editor
-- ---------------------------------------------------------------------------
set request.jwt.claim.sub = '00000000-0000-4000-8000-00000000000a';
set role authenticated;

do $$
declare failed boolean := false;
begin
  assert public.share_profile('10000000-0000-4000-8000-000000000001', ' B@Example.com ', 'viewer') = '00000000-0000-4000-8000-00000000000b',
    'share by email, ignoring case and spaces';
  begin
    perform public.share_profile('10000000-0000-4000-8000-000000000001', 'nobody@example.com', 'viewer');
  exception when no_data_found then failed := true;
  end;
  assert failed, 'unknown email';
end
$$;

reset role;
set request.jwt.claim.sub = '00000000-0000-4000-8000-00000000000b';
set role authenticated;

do $$
declare failed boolean := false;
begin
  assert (select count(*) from public.profiles) = 2, 'viewer B sees A''s profile and their own';
  assert (select count(*) from public.programs where profile_id = '10000000-0000-4000-8000-000000000001') = 2, 'viewer reads programs';
  assert (select count(*) from public.game_stats) = 1, 'viewer reads stats';
  assert (select count(*) from public.body_measurements) = 2, 'viewer reads height and weight';
  assert (select count(*) from public.wallball_sets) = 4, 'viewer reads wall ball reps';
  assert (select count(*) from public.program_budgets) = 2, 'viewer reads program budgets';
  assert (select count(*) from public.trips) = 1, 'viewer reads trips';
  begin
    insert into public.expenses (profile_id, spent_at, category, amount)
    values ('10000000-0000-4000-8000-000000000001', now(), 'travel', 10);
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'viewer can''t write';
end
$$;

reset role;
set request.jwt.claim.sub = '00000000-0000-4000-8000-00000000000a';
set role authenticated;
do $$ begin perform public.share_profile('10000000-0000-4000-8000-000000000001', 'b@example.com', 'editor'); end $$;

reset role;
set request.jwt.claim.sub = '00000000-0000-4000-8000-00000000000b';
set role authenticated;

insert into public.programs (profile_id, id, name, program_group, session_category)
values ('10000000-0000-4000-8000-000000000001', 'gym', 'Strength gym', 'fitness', 'fitness');
insert into public.profiles (id, first_name) values ('10000000-0000-4000-8000-000000000001', 'Sam')
on conflict (id) do update set first_name = excluded.first_name;
update public.profile_members set role = 'owner'
where profile_id = '10000000-0000-4000-8000-000000000001' and user_id = '00000000-0000-4000-8000-00000000000b';
delete from public.profiles where id = '10000000-0000-4000-8000-000000000001';

do $$
begin
  assert (select count(*) from public.programs where profile_id = '10000000-0000-4000-8000-000000000001') = 3, 'editor can add';
  assert (select first_name from public.profiles where id = '10000000-0000-4000-8000-000000000001') = 'Sam', 'editor can upsert the profile';
  assert (select created_by from public.profiles where id = '10000000-0000-4000-8000-000000000001') = '00000000-0000-4000-8000-00000000000a',
    'created_by survives an editor''s upsert';
  assert (select role from public.profile_members
          where profile_id = '10000000-0000-4000-8000-000000000001' and user_id = '00000000-0000-4000-8000-00000000000b') = 'editor',
    'editor can''t promote themselves';
  assert exists (select 1 from public.profiles where id = '10000000-0000-4000-8000-000000000001'), 'editor can''t delete the profile';
end
$$;

-- ---------------------------------------------------------------------------
-- Strangers and signed-out requests
-- ---------------------------------------------------------------------------
reset role;
set request.jwt.claim.sub = '00000000-0000-4000-8000-00000000000c';
set role authenticated;

do $$
begin
  assert (select count(*) from public.profiles) = 0, 'C sees no profiles';
  assert (select count(*) from public.expenses) = 0, 'C sees no expenses';
  assert (select count(*) from public.body_measurements) = 0, 'C sees no height and weight';
  assert (select count(*) from public.wallball_sessions) = 0, 'C sees no wall ball';
  assert (select count(*) from public.profile_members) = 0, 'C sees no memberships';
end
$$;

reset role;
set request.jwt.claim.sub = '';
set role anon;

do $$
declare failed boolean := false;
begin
  begin
    perform count(*) from public.profiles;
  exception when insufficient_privilege then failed := true;
  end;
  assert failed, 'anon has no access';
end
$$;

-- ---------------------------------------------------------------------------
-- Deleting a profile removes everything under it
-- ---------------------------------------------------------------------------
reset role;
set request.jwt.claim.sub = '00000000-0000-4000-8000-00000000000a';
set role authenticated;

update public.expenses set amount = 1900 where id = '50000000-0000-4000-8000-000000000001';
do $$
begin
  assert (select updated_at > created_at from public.expenses where id = '50000000-0000-4000-8000-000000000001')
      or (select updated_at = now() from public.expenses where id = '50000000-0000-4000-8000-000000000001'), 'updated_at is set on update';
end
$$;

-- Mental sessions with the mental performance coach are their own session category.
insert into public.programs (profile_id, id, name, program_group, session_category)
values ('10000000-0000-4000-8000-000000000001', 'mental-coach', 'Mental coach', 'mental', 'mental');
insert into public.training_sessions (profile_id, program_id, started_at, category, minutes, effort, focus)
values ('10000000-0000-4000-8000-000000000001', 'mental-coach', '2026-09-24T17:00:00Z', 'mental', 45, 4, '{"Game plan"}');
do $$
begin
  assert (select count(*) from public.training_sessions where category = 'mental') = 1, 'mental sessions are accepted';
  begin
    insert into public.training_sessions (profile_id, program_id, started_at, category, minutes, effort)
    values ('10000000-0000-4000-8000-000000000001', 'mental-coach', now(), 'yoga', 30, 3);
    raise exception 'unknown session category was accepted';
  exception when check_violation then null;
  end;
end
$$;

delete from public.profiles where id = '10000000-0000-4000-8000-000000000001';

reset role;
do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array[
    'programs', 'training_sessions', 'combine_results', 'combine_measurements', 'season_events', 'game_stats',
    'game_reflections', 'event_focus_goals', 'event_videos', 'event_checklist_items', 'expenses', 'mental_docs',
    'body_measurements', 'wallball_drills', 'wallball_sessions', 'wallball_sets', 'season_budgets', 'program_budgets',
    'trips', 'profile_members'
  ] loop
    execute format('select count(*) from public.%I where profile_id = %L', t, '10000000-0000-4000-8000-000000000001') into n;
    assert n = 0, format('%s rows remain after deleting the profile', t);
  end loop;
  assert (select count(*) from public.profiles) = 1, 'B''s own profile is untouched';
end
$$;

\echo 'All schema checks passed.'
