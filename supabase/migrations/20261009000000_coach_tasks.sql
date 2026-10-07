-- Coach tasks and game notes.
--
-- A coach assigns a task to everyone on a roster (including athletes who join later) or to one athlete on it:
-- wall ball reps or training minutes, which the app ticks off from what the athlete logs, or something to tick off
-- by hand. The coach picks how often: every day, every week, or once by a due date. Only coaches assign; the athlete
-- or a parent can mark a task done for a day, a week or for good (assignment_completions), and the coach sees it.
--
-- Coaches can also leave a note on an athlete's game (event_coach_notes). It's kept apart from the family's own
-- reflection, so an edit made offline on a family phone can never overwrite it.
--
-- Families read tasks and notes with the coach's name through athlete_assignments and athlete_coach_notes.
--
-- Safe to run again; policies it sets are dropped (if there) and created afresh.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.assignments (
  id              uuid primary key default gen_random_uuid(),
  roster_id       uuid not null references public.rosters (id) on delete cascade,
  profile_id      uuid references public.profiles (id) on delete cascade,
  coach_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind            text not null check (kind in ('wallball', 'training', 'check')),
  title           text not null check (length(btrim(title)) between 1 and 120),
  notes           text not null default '' check (length(notes) <= 2000),
  schedule        text not null check (schedule in ('once', 'daily', 'weekly')),
  starts_on       date not null default current_date,
  due_on          date,
  ends_on         date,
  target_reps     integer check (target_reps between 1 and 10000),
  target_minutes  integer check (target_minutes between 1 and 10080),
  category        text check (category in ('team', 'skills', 'fitness', 'mental')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check ((schedule = 'once') = (due_on is not null)),
  check (schedule = 'once' or ends_on is null or ends_on >= starts_on),
  check (schedule <> 'once' or ends_on is null),
  check (due_on is null or due_on >= starts_on),
  check ((kind = 'wallball') = (target_reps is not null)),
  check ((kind = 'training') = (target_minutes is not null)),
  check (kind = 'training' or category is null)
);
create index if not exists assignments_roster_idx on public.assignments (roster_id);
create index if not exists assignments_profile_idx on public.assignments (profile_id) where profile_id is not null;
comment on table public.assignments is 'Tasks a coach gives a roster (profile_id null) or one athlete on it.';
comment on column public.assignments.schedule is 'once: by due_on. daily or weekly (Monday to Sunday): from starts_on, until ends_on if set.';

create table if not exists public.assignment_completions (
  assignment_id  uuid not null references public.assignments (id) on delete cascade,
  profile_id     uuid not null references public.profiles (id) on delete cascade,
  period_start   date not null,
  done_by        uuid default auth.uid() references auth.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (assignment_id, profile_id, period_start)
);
create index if not exists assignment_completions_profile_idx on public.assignment_completions (profile_id);
comment on table public.assignment_completions is 'A task marked done by hand for one day (daily), week (weekly, its Monday) or for good (once, its starts_on).';

create table if not exists public.event_coach_notes (
  event_id    uuid not null,
  profile_id  uuid not null,
  coach_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  note        text not null check (length(btrim(note)) between 1 and 2000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (event_id, coach_id),
  foreign key (event_id, profile_id) references public.season_events (id, profile_id) on delete cascade
);
create index if not exists event_coach_notes_profile_idx on public.event_coach_notes (profile_id);
comment on table public.event_coach_notes is 'A coach''s note on an athlete''s game, kept apart from the family''s reflection.';

-- ---------------------------------------------------------------------------
-- Access helpers
-- ---------------------------------------------------------------------------

create or replace function private.coaches_roster(p_roster_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.rosters r where r.id = p_roster_id and r.coach_id = (select auth.uid()))
$$;

-- True when the signed-in account coaches the athlete on any of its rosters.
create or replace function private.coaches_athlete(p_profile_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.roster_athletes ra join public.rosters r on r.id = ra.roster_id
    where ra.profile_id = p_profile_id and r.coach_id = (select auth.uid())
  )
$$;

-- What a coach may put in a task: their own roster, an athlete on it, and mental minutes only from a mental coach
-- (a team coach doesn't see mental sessions).
create or replace function private.valid_assignment(p_roster_id uuid, p_profile_id uuid, p_category text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.rosters r
    where r.id = p_roster_id and r.coach_id = (select auth.uid())
      and (p_category is distinct from 'mental' or r.kind = 'mental')
      and (p_profile_id is null or exists (
        select 1 from public.roster_athletes ra where ra.roster_id = r.id and ra.profile_id = p_profile_id))
  )
$$;

-- True when the task is for this athlete: given to them, or to a roster they're on.
create or replace function private.assignment_applies(p_assignment_id uuid, p_profile_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.assignments a
    where a.id = p_assignment_id
      and (a.profile_id = p_profile_id or (a.profile_id is null and exists (
        select 1 from public.roster_athletes ra where ra.roster_id = a.roster_id and ra.profile_id = p_profile_id)))
  )
$$;

revoke all on function private.coaches_roster(uuid), private.coaches_athlete(uuid), private.valid_assignment(uuid, uuid, text),
  private.assignment_applies(uuid, uuid) from public, anon;
grant execute on function private.coaches_roster(uuid), private.coaches_athlete(uuid), private.valid_assignment(uuid, uuid, text),
  private.assignment_applies(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Views for families
-- ---------------------------------------------------------------------------

-- Each task once per athlete it's for, with the roster and coach names. Families read their athletes' tasks here;
-- coaches read and write the assignments table. Runs with the view owner's rights; the where clause does the
-- access check. An athlete taken off a roster stops seeing its tasks.
create or replace view public.athlete_assignments with (security_barrier = true) as
  select a.id, ra.profile_id as athlete_id, a.roster_id, r.name as roster_name, coalesce(acc.display_name, '') as coach_name,
         a.kind, a.title, a.notes, a.schedule, a.starts_on, a.due_on, a.ends_on, a.target_reps, a.target_minutes, a.category,
         a.created_at
  from public.assignments a
  join public.rosters r on r.id = a.roster_id
  join public.roster_athletes ra on ra.roster_id = a.roster_id and (a.profile_id is null or a.profile_id = ra.profile_id)
  left join public.accounts acc on acc.user_id = r.coach_id
  where private.can_read_profile(ra.profile_id) or r.coach_id = (select auth.uid());
comment on view public.athlete_assignments is 'Tasks for each athlete the signed-in account is on (or coaches), with roster and coach names.';

create or replace view public.athlete_coach_notes with (security_barrier = true) as
  select n.event_id, n.profile_id, n.coach_id, coalesce(acc.display_name, '') as coach_name, n.note, n.updated_at
  from public.event_coach_notes n
  left join public.accounts acc on acc.user_id = n.coach_id
  where private.can_read(n.profile_id, 'events') or n.coach_id = (select auth.uid());
comment on view public.athlete_coach_notes is 'Coaches'' notes on games, with the coach''s name.';

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.assignments enable row level security;
drop policy if exists "Coaches see their roster's tasks" on public.assignments;
create policy "Coaches see their roster's tasks" on public.assignments for select to authenticated
  using (private.coaches_roster(roster_id));
drop policy if exists "Coaches give tasks" on public.assignments;
create policy "Coaches give tasks" on public.assignments for insert to authenticated
  with check (coach_id = (select auth.uid()) and private.valid_assignment(roster_id, profile_id, category));
drop policy if exists "Coaches change their tasks" on public.assignments;
create policy "Coaches change their tasks" on public.assignments for update to authenticated
  using (private.coaches_roster(roster_id))
  with check (coach_id = (select auth.uid()) and private.valid_assignment(roster_id, profile_id, category));
drop policy if exists "Coaches remove their tasks" on public.assignments;
create policy "Coaches remove their tasks" on public.assignments for delete to authenticated
  using (private.coaches_roster(roster_id));
drop trigger if exists assignments_set_updated_at on public.assignments;
create trigger assignments_set_updated_at before update on public.assignments
  for each row execute function private.set_updated_at();
revoke all on public.assignments from anon;
grant select, insert, update, delete on public.assignments to authenticated;

-- The athlete or a parent marks a task done; its coach sees that.
alter table public.assignment_completions enable row level security;
drop policy if exists "Families and coaches see what's done" on public.assignment_completions;
create policy "Families and coaches see what's done" on public.assignment_completions for select to authenticated
  using (private.can_read_profile(profile_id)
         or exists (select 1 from public.assignments a where a.id = assignment_id and private.coaches_roster(a.roster_id)));
drop policy if exists "Families mark tasks done" on public.assignment_completions;
create policy "Families mark tasks done" on public.assignment_completions for insert to authenticated
  with check (private.can_write(profile_id, 'training') and private.assignment_applies(assignment_id, profile_id));
drop policy if exists "Families change what's done" on public.assignment_completions;
create policy "Families change what's done" on public.assignment_completions for update to authenticated
  using (private.can_write(profile_id, 'training'))
  with check (private.can_write(profile_id, 'training') and private.assignment_applies(assignment_id, profile_id));
drop policy if exists "Families unmark tasks" on public.assignment_completions;
create policy "Families unmark tasks" on public.assignment_completions for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop trigger if exists assignment_completions_set_updated_at on public.assignment_completions;
create trigger assignment_completions_set_updated_at before update on public.assignment_completions
  for each row execute function private.set_updated_at();
revoke all on public.assignment_completions from anon;
grant select, insert, update, delete on public.assignment_completions to authenticated;

-- A coach writes notes on the games of athletes they coach; families read them.
alter table public.event_coach_notes enable row level security;
drop policy if exists "Coaches and families see game notes" on public.event_coach_notes;
create policy "Coaches and families see game notes" on public.event_coach_notes for select to authenticated
  using (coach_id = (select auth.uid()) or private.can_read(profile_id, 'events'));
drop policy if exists "Coaches write game notes" on public.event_coach_notes;
create policy "Coaches write game notes" on public.event_coach_notes for insert to authenticated
  with check (coach_id = (select auth.uid()) and private.coaches_athlete(profile_id));
drop policy if exists "Coaches change their game notes" on public.event_coach_notes;
create policy "Coaches change their game notes" on public.event_coach_notes for update to authenticated
  using (coach_id = (select auth.uid()) and private.coaches_athlete(profile_id))
  with check (coach_id = (select auth.uid()) and private.coaches_athlete(profile_id));
drop policy if exists "Coaches remove their game notes" on public.event_coach_notes;
create policy "Coaches remove their game notes" on public.event_coach_notes for delete to authenticated
  using (coach_id = (select auth.uid()));
drop trigger if exists event_coach_notes_set_updated_at on public.event_coach_notes;
create trigger event_coach_notes_set_updated_at before update on public.event_coach_notes
  for each row execute function private.set_updated_at();
revoke all on public.event_coach_notes from anon;
grant select, insert, update, delete on public.event_coach_notes to authenticated;

revoke all on public.athlete_assignments, public.athlete_coach_notes from anon;
revoke insert, update, delete on public.athlete_assignments, public.athlete_coach_notes from authenticated;
grant select on public.athlete_assignments, public.athlete_coach_notes to authenticated;
