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
end
$$;

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
  assert (select count(*) from public.profile_members) = 1, 'B sees only their own membership';

  update public.profiles set first_name = 'Hacked' where id = '10000000-0000-4000-8000-000000000001';
  delete from public.expenses where profile_id = '10000000-0000-4000-8000-000000000001';
  update public.body_measurements set weight_kg = 99 where profile_id = '10000000-0000-4000-8000-000000000001';
  update public.wallball_sets set reps = 999 where profile_id = '10000000-0000-4000-8000-000000000001';
  delete from public.wallball_drills where profile_id = '10000000-0000-4000-8000-000000000001';

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
    'body_measurements', 'wallball_drills', 'wallball_sessions', 'wallball_sets', 'profile_members'
  ] loop
    execute format('select count(*) from public.%I where profile_id = %L', t, '10000000-0000-4000-8000-000000000001') into n;
    assert n = 0, format('%s rows remain after deleting the profile', t);
  end loop;
  assert (select count(*) from public.profiles) = 1, 'B''s own profile is untouched';
end
$$;

\echo 'All schema checks passed.'
