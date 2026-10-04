-- Wall ball: daily reps by drill and hand, timed challenges, and the athlete's own drills.
--
-- The built-in routine (overhand, quick sticks, …) lives in the app, so wallball_drills only
-- holds drills the athlete added and built-ins the athlete changed (renamed, hid, new default
-- reps). That's why wallball_sets.drill_id has no foreign key: it can name a built-in drill.
-- Ranges match WallballDrill, WallballSet and WallballChallenge in the app.

create table public.wallball_drills (
  profile_id    uuid not null references public.profiles (id) on delete cascade,
  id            text not null check (length(id) between 1 and 100),
  name          text not null check (length(name) > 0),
  detail        text not null default '',
  hands         text not null default 'each' check (hands in ('each', 'together')),
  default_reps  integer not null default 25 check (default_reps between 1 and 500),
  hidden        boolean not null default false,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (profile_id, id)
);
comment on table public.wallball_drills is 'Wall ball drills the athlete added, and built-in drills the athlete changed. IDs are per profile.';
comment on column public.wallball_drills.hands is 'each: right and left reps are counted separately. together: both hands at once or switching every rep, one count.';

create table public.wallball_sessions (
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
create index wallball_sessions_profile_idx on public.wallball_sessions (profile_id, done_at desc);
comment on table public.wallball_sessions is 'A day''s wall ball, or a timed challenge (challenge_seconds on the clock for each drill and hand).';

create table public.wallball_sets (
  session_id  uuid not null,
  profile_id  uuid not null,
  drill_id    text not null check (length(drill_id) between 1 and 100),
  hand        text not null check (hand in ('right', 'left', 'both')),
  reps        integer not null check (reps between 1 and 5000),
  position    integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (session_id, drill_id, hand),
  foreign key (session_id, profile_id) references public.wallball_sessions (id, profile_id) on delete cascade
);
create index wallball_sets_profile_idx on public.wallball_sets (profile_id);
comment on table public.wallball_sets is 'Reps of one drill with one hand in a wall ball session.';

-- Same rules as every other profile table: members read, owners and editors write.
-- Written out per table (no do-block) so the file runs as-is in the Supabase SQL Editor.

alter table public.wallball_drills enable row level security;
create policy "Members can read" on public.wallball_drills for select to authenticated
  using (private.can_read_profile(profile_id));
create policy "Owners and editors can add" on public.wallball_drills for insert to authenticated
  with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can change" on public.wallball_drills for update to authenticated
  using (private.can_edit_profile(profile_id)) with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can delete" on public.wallball_drills for delete to authenticated
  using (private.can_edit_profile(profile_id));
create trigger wallball_drills_set_updated_at before update on public.wallball_drills
  for each row execute function private.set_updated_at();
revoke all on public.wallball_drills from anon;
grant select, insert, update, delete on public.wallball_drills to authenticated;

alter table public.wallball_sessions enable row level security;
create policy "Members can read" on public.wallball_sessions for select to authenticated
  using (private.can_read_profile(profile_id));
create policy "Owners and editors can add" on public.wallball_sessions for insert to authenticated
  with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can change" on public.wallball_sessions for update to authenticated
  using (private.can_edit_profile(profile_id)) with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can delete" on public.wallball_sessions for delete to authenticated
  using (private.can_edit_profile(profile_id));
create trigger wallball_sessions_set_updated_at before update on public.wallball_sessions
  for each row execute function private.set_updated_at();
revoke all on public.wallball_sessions from anon;
grant select, insert, update, delete on public.wallball_sessions to authenticated;

alter table public.wallball_sets enable row level security;
create policy "Members can read" on public.wallball_sets for select to authenticated
  using (private.can_read_profile(profile_id));
create policy "Owners and editors can add" on public.wallball_sets for insert to authenticated
  with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can change" on public.wallball_sets for update to authenticated
  using (private.can_edit_profile(profile_id)) with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can delete" on public.wallball_sets for delete to authenticated
  using (private.can_edit_profile(profile_id));
create trigger wallball_sets_set_updated_at before update on public.wallball_sets
  for each row execute function private.set_updated_at();
revoke all on public.wallball_sets from anon;
grant select, insert, update, delete on public.wallball_sets to authenticated;
