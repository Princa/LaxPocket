-- Hockey home practice: shooting, stickhandling and passing drills, counted in shots (and how many were on target),
-- minutes or reps; the athlete's weekly shot and stickhandling goals; and coach tasks for shots and stickhandling
-- minutes. Lacrosse keeps wall ball. See docs/multi-sport.md.
--
-- The built-in drills live in the app, so practice_drills only holds drills the athlete added and built-ins the athlete
-- changed, and practice_sets.drill_id has no foreign key. Ranges match PracticeDrill, PracticeSet, PracticeChallenge
-- and AthleteProfile in the app. Practice is part of the training section, like wall ball.
--
-- Safe to run again: tables are created if missing, and the constraints, policies and triggers it sets are dropped
-- (if there) and created afresh.

-- ---------------------------------------------------------------------------
-- Practice
-- ---------------------------------------------------------------------------

create table if not exists public.practice_drills (
  profile_id      uuid not null references public.profiles (id) on delete cascade,
  id              text not null check (length(id) between 1 and 100),
  kind            text not null check (kind in ('shooting', 'stickhandling', 'passing', 'other')),
  name            text not null check (length(name) > 0),
  detail          text not null default '',
  measure         text not null check (measure in ('shots', 'minutes', 'reps')),
  tracks_target   boolean not null default false,
  default_amount  integer not null check (default_amount between 1 and 500),
  hidden          boolean not null default false,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (profile_id, id),
  check (measure = 'shots' or not tracks_target)
);
comment on table public.practice_drills is 'Practice drills the athlete added, and built-in drills the athlete changed. IDs are per profile.';
comment on column public.practice_drills.measure is 'shots (with an on-target count if tracks_target), minutes or reps.';

create table if not exists public.practice_sessions (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles (id) on delete cascade,
  done_at            timestamptz not null,
  minutes            integer check (minutes between 1 and 1440),
  challenge_seconds  integer check (challenge_seconds between 5 and 3600),
  notes              text not null default '',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (id, profile_id)
);
create index if not exists practice_sessions_profile_idx on public.practice_sessions (profile_id, done_at desc);
comment on table public.practice_sessions is 'A day''s practice, or a timed challenge (challenge_seconds on the clock for each drill).';

create table if not exists public.practice_sets (
  session_id  uuid not null,
  profile_id  uuid not null,
  drill_id    text not null check (length(drill_id) between 1 and 100),
  amount      integer not null check (amount between 1 and 5000),
  on_target   integer,
  position    integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (session_id, drill_id),
  foreign key (session_id, profile_id) references public.practice_sessions (id, profile_id) on delete cascade,
  check (on_target is null or on_target between 0 and amount)
);
create index if not exists practice_sets_profile_idx on public.practice_sets (profile_id);
comment on table public.practice_sets is
  'One drill in a practice session: shots, minutes or reps by the drill''s measure; in a challenge, the count reached in the time.';

-- Same rules as wall ball: reading needs the training section, writing needs it and the owner or editor role.
alter table public.practice_drills enable row level security;
drop policy if exists "Members can read" on public.practice_drills;
create policy "Members can read" on public.practice_drills for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.practice_drills;
create policy "Owners and editors can add" on public.practice_drills for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.practice_drills;
create policy "Owners and editors can change" on public.practice_drills for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.practice_drills;
create policy "Owners and editors can delete" on public.practice_drills for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop trigger if exists practice_drills_set_updated_at on public.practice_drills;
create trigger practice_drills_set_updated_at before update on public.practice_drills
  for each row execute function private.set_updated_at();
revoke all on public.practice_drills from anon;
grant select, insert, update, delete on public.practice_drills to authenticated;

alter table public.practice_sessions enable row level security;
drop policy if exists "Members can read" on public.practice_sessions;
create policy "Members can read" on public.practice_sessions for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.practice_sessions;
create policy "Owners and editors can add" on public.practice_sessions for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.practice_sessions;
create policy "Owners and editors can change" on public.practice_sessions for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.practice_sessions;
create policy "Owners and editors can delete" on public.practice_sessions for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop trigger if exists practice_sessions_set_updated_at on public.practice_sessions;
create trigger practice_sessions_set_updated_at before update on public.practice_sessions
  for each row execute function private.set_updated_at();
revoke all on public.practice_sessions from anon;
grant select, insert, update, delete on public.practice_sessions to authenticated;

alter table public.practice_sets enable row level security;
drop policy if exists "Members can read" on public.practice_sets;
create policy "Members can read" on public.practice_sets for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.practice_sets;
create policy "Owners and editors can add" on public.practice_sets for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.practice_sets;
create policy "Owners and editors can change" on public.practice_sets for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.practice_sets;
create policy "Owners and editors can delete" on public.practice_sets for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop trigger if exists practice_sets_set_updated_at on public.practice_sets;
create trigger practice_sets_set_updated_at before update on public.practice_sets
  for each row execute function private.set_updated_at();
revoke all on public.practice_sets from anon;
grant select, insert, update, delete on public.practice_sets to authenticated;

-- ---------------------------------------------------------------------------
-- Weekly goals
-- ---------------------------------------------------------------------------

alter table public.profiles add column if not exists weekly_shot_goal integer not null default 1000;
alter table public.profiles drop constraint if exists profiles_weekly_shot_goal_check;
alter table public.profiles add constraint profiles_weekly_shot_goal_check check (weekly_shot_goal between 0 and 100000);
alter table public.profiles add column if not exists weekly_stickhandling_goal integer not null default 60;
alter table public.profiles drop constraint if exists profiles_weekly_stickhandling_goal_check;
alter table public.profiles add constraint profiles_weekly_stickhandling_goal_check
  check (weekly_stickhandling_goal between 0 and 10080);
comment on column public.profiles.weekly_shot_goal is 'Hockey: shots a week the athlete aims for; 0 for no goal.';
comment on column public.profiles.weekly_stickhandling_goal is 'Hockey: stickhandling minutes a week; 0 for no goal.';

-- ---------------------------------------------------------------------------
-- Coach tasks for shots and stickhandling
-- ---------------------------------------------------------------------------

-- The checks on a task's kind were unnamed in the coach tasks migration, so they're found by what they check and
-- replaced with named ones that know the new kinds.
do $$
declare
  c record;
begin
  for c in
    select con.conname from pg_constraint con
    where con.conrelid = 'public.assignments'::regclass and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ~ '\mkind\M'
  loop
    execute format('alter table public.assignments drop constraint %I', c.conname);
  end loop;
end
$$;
alter table public.assignments add constraint assignments_kind_check
  check (kind in ('wallball', 'shots', 'stickhandling', 'training', 'check'));
alter table public.assignments add constraint assignments_reps_by_kind_check
  check ((kind in ('wallball', 'shots')) = (target_reps is not null));
alter table public.assignments add constraint assignments_minutes_by_kind_check
  check ((kind in ('training', 'stickhandling')) = (target_minutes is not null));
alter table public.assignments add constraint assignments_category_by_kind_check
  check (kind = 'training' or category is null);
comment on column public.assignments.kind is
  'wallball (lacrosse) and shots (hockey) count target_reps; training and stickhandling (hockey) count target_minutes; check is ticked off.';

-- A task's kind has to suit the roster's sport: wall ball for lacrosse, shots and stickhandling for hockey.
create or replace function private.guard_assignment_sport() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_sport text;
begin
  select r.sport into v_sport from public.rosters r where r.id = new.roster_id;
  if new.kind = 'wallball' and v_sport is distinct from 'lacrosse' then
    raise exception 'Wall ball tasks are for lacrosse rosters' using errcode = '22023';
  end if;
  if new.kind in ('shots', 'stickhandling') and v_sport is distinct from 'hockey' then
    raise exception 'Shots and stickhandling tasks are for hockey rosters' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists assignments_guard_sport on public.assignments;
create trigger assignments_guard_sport before insert or update on public.assignments
  for each row execute function private.guard_assignment_sport();
