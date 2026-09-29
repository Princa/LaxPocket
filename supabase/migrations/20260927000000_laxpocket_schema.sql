-- LaxPocket schema: athlete profiles and everything logged for them.
--
-- Every row belongs to one athlete profile (profile_id). Who can see or change a
-- profile is decided by profile_members: owners and editors can change its data,
-- viewers can only read it. The user who creates a profile becomes its owner.
--
-- Enum-like columns store the app's Swift enum raw values ('u15Women', 'teamFees',
-- 'toReview', …) and are checked against the known values.
--
-- Child rows of an event or a testing day carry profile_id too, and their foreign
-- key is (parent id, profile_id), so a row can't be attached to another profile's
-- event while claiming to be yours.

create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Profiles and members
-- ---------------------------------------------------------------------------

create table public.profiles (
  id                 uuid primary key default gen_random_uuid(),
  created_by         uuid default auth.uid() references auth.users (id) on delete set null,
  first_name         text not null default '',
  class_year         smallint check (class_year between 2000 and 2100),
  positions          text not null default '',
  benchmark_group    text not null default 'u15Women'
                       check (benchmark_group in ('u15Women', 'u17Women', 'u19Women', 'u15Men', 'u17Men', 'u19Men')),
  mental_coach_name  text not null default '',
  weekly_goal_hours  numeric(4, 1) not null default 12 check (weekly_goal_hours > 0 and weekly_goal_hours <= 60),
  season_label       text not null default '',
  season_budget      numeric(10, 2) not null default 0 check (season_budget >= 0),
  currency           text not null default 'CAD' check (currency ~ '^[A-Z]{3}$'),
  theme_id           text not null default 'original',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
comment on table public.profiles is 'One athlete. Everything else in the app belongs to a profile.';

create table public.profile_members (
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  role        text not null default 'viewer' check (role in ('owner', 'editor', 'viewer')),
  created_at  timestamptz not null default now(),
  primary key (profile_id, user_id)
);
create index profile_members_user_id_idx on public.profile_members (user_id);
comment on table public.profile_members is 'Accounts that can see a profile: owner and editor can change it, viewer can read it.';

-- ---------------------------------------------------------------------------
-- Programs and training
-- ---------------------------------------------------------------------------

create table public.programs (
  profile_id        uuid not null references public.profiles (id) on delete cascade,
  id                text not null check (length(id) between 1 and 100),
  name              text not null check (length(name) > 0),
  detail            text not null default '',
  program_group     text not null check (program_group in ('teams', 'skills', 'fitness', 'showcases', 'mental', 'combine')),
  session_category  text check (session_category in ('team', 'skills', 'fitness')),
  monogram          text not null default '',
  sort_order        integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (profile_id, id)
);
comment on table public.programs is 'Teams, coaches, facilities and events the athlete trains with. IDs are per profile.';

create table public.training_sessions (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  program_id  text not null,
  started_at  timestamptz not null,
  category    text not null check (category in ('team', 'skills', 'fitness')),
  minutes     integer not null check (minutes between 1 and 1440),
  effort      smallint not null check (effort between 1 and 10),
  focus       text[] not null default '{}',
  notes       text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  foreign key (profile_id, program_id) references public.programs (profile_id, id)
);
create index training_sessions_profile_started_idx on public.training_sessions (profile_id, started_at desc);
create index training_sessions_program_idx on public.training_sessions (profile_id, program_id);
comment on table public.training_sessions is 'Logged practices, lessons and workouts. effort is session RPE 1–10.';

-- ---------------------------------------------------------------------------
-- Combine testing
-- ---------------------------------------------------------------------------

create table public.combine_results (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles (id) on delete cascade,
  tested_at    timestamptz not null,
  event_name   text not null default '',
  height_text  text not null default '',
  weight_text  text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (id, profile_id)
);
create index combine_results_profile_idx on public.combine_results (profile_id, tested_at desc);
comment on table public.combine_results is 'A testing day (baseline, re-test, …).';

create table public.combine_measurements (
  result_id   uuid not null,
  profile_id  uuid not null,
  metric      text not null check (metric in ('gripLeft', 'gripRight', 'squatJump', 'countermovementJump',
                                              'sprint10m', 'sprint20m', 'proAgilityLeft', 'proAgilityRight')),
  value       double precision not null check (value > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (result_id, metric),
  foreign key (result_id, profile_id) references public.combine_results (id, profile_id) on delete cascade
);
create index combine_measurements_profile_idx on public.combine_measurements (profile_id);
comment on table public.combine_measurements is 'One result from a testing day: grip in N, jumps in inches, sprints and agility in seconds.';

-- ---------------------------------------------------------------------------
-- Season events
-- ---------------------------------------------------------------------------

create table public.season_events (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles (id) on delete cascade,
  kind               text not null check (kind in ('game', 'tournament', 'showcase', 'camp')),
  title              text not null default '',
  team               text not null default '',
  opponent           text,
  starts_at          timestamptz not null,
  ends_at            timestamptz,
  date_is_tentative  boolean not null default false,
  location           text not null default '',
  our_score          smallint check (our_score >= 0),
  their_score        smallint check (their_score >= 0),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (id, profile_id),
  check (ends_at is null or ends_at >= starts_at),
  check ((our_score is null) = (their_score is null))
);
create index season_events_profile_starts_idx on public.season_events (profile_id, starts_at);
comment on table public.season_events is 'Games, tournaments, showcases and camps. A score means the event has a result.';

create table public.game_stats (
  event_id          uuid primary key,
  profile_id        uuid not null,
  goals             smallint not null default 0 check (goals >= 0),
  assists           smallint not null default 0 check (assists >= 0),
  shots             smallint not null default 0 check (shots >= 0),
  ground_balls      smallint not null default 0 check (ground_balls >= 0),
  draw_controls     smallint not null default 0 check (draw_controls >= 0),
  caused_turnovers  smallint not null default 0 check (caused_turnovers >= 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  foreign key (event_id, profile_id) references public.season_events (id, profile_id) on delete cascade
);
create index game_stats_profile_idx on public.game_stats (profile_id);
comment on table public.game_stats is 'The athlete''s stat line for a game.';

create table public.game_reflections (
  event_id           uuid primary key,
  profile_id         uuid not null,
  self_rating        smallint check (self_rating between 1 and 10),
  went_well          text not null default '',
  work_on            text not null default '',
  coach_feedback     text not null default '',
  coach_feedback_at  timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  foreign key (event_id, profile_id) references public.season_events (id, profile_id) on delete cascade
);
create index game_reflections_profile_idx on public.game_reflections (profile_id);
comment on table public.game_reflections is 'Post-game reflection and coach feedback.';

create table public.event_focus_goals (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null,
  profile_id  uuid not null,
  position    smallint not null default 0,
  goal        text not null,
  outcome     text not null default 'pending' check (outcome in ('pending', 'hit', 'partly', 'missed')),
  note        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  foreign key (event_id, profile_id) references public.season_events (id, profile_id) on delete cascade
);
create index event_focus_goals_event_idx on public.event_focus_goals (event_id, position);
create index event_focus_goals_profile_idx on public.event_focus_goals (profile_id);
comment on table public.event_focus_goals is 'Pre-game goals and how each went.';

create table public.event_videos (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null,
  profile_id     uuid not null,
  position       smallint not null default 0,
  title          text not null default '',
  url            text not null check (url ~* '^https?://'),
  duration_text  text not null default '',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  foreign key (event_id, profile_id) references public.season_events (id, profile_id) on delete cascade
);
create index event_videos_event_idx on public.event_videos (event_id, position);
create index event_videos_profile_idx on public.event_videos (profile_id);
comment on table public.event_videos is 'Links to game film or highlights.';

create table public.event_checklist_items (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null,
  profile_id  uuid not null,
  position    smallint not null default 0,
  title       text not null,
  done        boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  foreign key (event_id, profile_id) references public.season_events (id, profile_id) on delete cascade
);
create index event_checklist_items_event_idx on public.event_checklist_items (event_id, position);
create index event_checklist_items_profile_idx on public.event_checklist_items (profile_id);
comment on table public.event_checklist_items is 'Prep checklist for a showcase or trip.';

-- ---------------------------------------------------------------------------
-- Budget and mental game
-- ---------------------------------------------------------------------------

create table public.expenses (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  spent_at    timestamptz not null,
  title       text not null default '',
  category    text not null check (category in ('teamFees', 'coaching', 'fitness', 'travel', 'showcases', 'equipment', 'facility')),
  amount      numeric(10, 2) not null check (amount >= 0),
  note        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index expenses_profile_spent_idx on public.expenses (profile_id, spent_at desc);
comment on table public.expenses is 'Season spending, in the profile''s currency.';

create table public.mental_docs (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles (id) on delete cascade,
  title           text not null default '',
  url             text not null check (url ~* '^https?://'),
  folder          text not null check (folder in ('routines', 'sessionNotes', 'journal', 'goals')),
  kind            text not null check (kind in ('word', 'googleDoc', 'pdf', 'link')),
  status          text not null default 'new' check (status in ('new', 'toReview', 'reviewed')),
  doc_updated_at  timestamptz not null,
  doc_updated_by  text not null default '',
  note            text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index mental_docs_profile_idx on public.mental_docs (profile_id, doc_updated_at desc);
comment on table public.mental_docs is 'Links to documents shared with the mental performance coach. The files stay in Google Drive.';

-- ---------------------------------------------------------------------------
-- Access helpers (in the private schema, so they aren't exposed through the API)
-- ---------------------------------------------------------------------------

create function private.profile_role(p_profile_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select m.role from public.profile_members m
  where m.profile_id = p_profile_id and m.user_id = (select auth.uid())
$$;

create function private.can_read_profile(p_profile_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members m
    where m.profile_id = p_profile_id and m.user_id = (select auth.uid())
  )
$$;

create function private.can_edit_profile(p_profile_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members m
    where m.profile_id = p_profile_id and m.user_id = (select auth.uid()) and m.role in ('owner', 'editor')
  )
$$;

revoke all on function private.profile_role(uuid), private.can_read_profile(uuid), private.can_edit_profile(uuid) from public, anon;
grant execute on function private.profile_role(uuid), private.can_read_profile(uuid), private.can_edit_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create function private.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- The creator of a profile becomes its owner.
create function private.add_profile_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.created_by is not null then
    insert into public.profile_members (profile_id, user_id, role)
    values (new.id, new.created_by, 'owner')
    on conflict (profile_id, user_id) do update set role = 'owner';
  end if;
  return new;
end;
$$;

-- created_by never changes after insert, whoever updates the row.
create function private.keep_created_by() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.created_by := old.created_by;
  return new;
end;
$$;

create trigger profiles_add_owner after insert on public.profiles
  for each row execute function private.add_profile_owner();
create trigger profiles_keep_created_by before update on public.profiles
  for each row execute function private.keep_created_by();
create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;

-- created_by is included so an insert … on conflict / returning can see the row
-- before the owner membership (added by the trigger above) exists.
create policy "Members can read profiles" on public.profiles
  for select to authenticated
  using (created_by = (select auth.uid()) or private.can_read_profile(id));
create policy "Signed-in users can create profiles" on public.profiles
  for insert to authenticated
  with check (created_by = (select auth.uid()));
create policy "Owners and editors can update profiles" on public.profiles
  for update to authenticated
  using (private.can_edit_profile(id))
  with check (private.can_edit_profile(id));
create policy "Owners can delete profiles" on public.profiles
  for delete to authenticated
  using (private.profile_role(id) = 'owner');

alter table public.profile_members enable row level security;

create policy "Members can see who else is on their profiles" on public.profile_members
  for select to authenticated
  using (user_id = (select auth.uid()) or private.can_read_profile(profile_id));
create policy "Owners can add members" on public.profile_members
  for insert to authenticated
  with check (private.profile_role(profile_id) = 'owner');
create policy "Owners can change other members' roles" on public.profile_members
  for update to authenticated
  using (private.profile_role(profile_id) = 'owner' and user_id <> (select auth.uid()))
  with check (private.profile_role(profile_id) = 'owner' and user_id <> (select auth.uid()));
create policy "Owners can remove members; members can leave" on public.profile_members
  for delete to authenticated
  using (
    (private.profile_role(profile_id) = 'owner' and user_id <> (select auth.uid()))
    or (user_id = (select auth.uid()) and role <> 'owner')
  );

-- Every table below is scoped by profile_id with the same rules:
-- members read, owners and editors write.
do $$
declare
  t text;
begin
  foreach t in array array[
    'programs', 'training_sessions', 'combine_results', 'combine_measurements',
    'season_events', 'game_stats', 'game_reflections', 'event_focus_goals',
    'event_videos', 'event_checklist_items', 'expenses', 'mental_docs'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "Members can read" on public.%I for select to authenticated
                      using (private.can_read_profile(profile_id))', t);
    execute format('create policy "Owners and editors can add" on public.%I for insert to authenticated
                      with check (private.can_edit_profile(profile_id))', t);
    execute format('create policy "Owners and editors can change" on public.%I for update to authenticated
                      using (private.can_edit_profile(profile_id)) with check (private.can_edit_profile(profile_id))', t);
    execute format('create policy "Owners and editors can delete" on public.%I for delete to authenticated
                      using (private.can_edit_profile(profile_id))', t);
    execute format('create trigger %I before update on public.%I
                      for each row execute function private.set_updated_at()', t || '_set_updated_at', t);
  end loop;
end
$$;

-- Nothing is readable without signing in.
do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'profile_members', 'programs', 'training_sessions', 'combine_results', 'combine_measurements',
    'season_events', 'game_stats', 'game_reflections', 'event_focus_goals',
    'event_videos', 'event_checklist_items', 'expenses', 'mental_docs'
  ] loop
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Sharing
-- ---------------------------------------------------------------------------

-- Gives another account access to a profile, e.g. a parent's phone or a coach.
-- Only the profile's owner can call it; the other person must have signed up already.
create function public.share_profile(p_profile_id uuid, p_email text, p_role text default 'editor')
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid;
begin
  if private.profile_role(p_profile_id) is distinct from 'owner' then
    raise exception 'Only the profile''s owner can share it' using errcode = '42501';
  end if;
  if p_role not in ('editor', 'viewer') then
    raise exception 'Role must be editor or viewer' using errcode = '22023';
  end if;
  select u.id into v_user_id from auth.users u where lower(u.email) = lower(trim(p_email));
  if v_user_id is null then
    raise exception 'No LaxPocket account uses that email yet' using errcode = 'P0002';
  end if;
  if v_user_id = (select auth.uid()) then
    raise exception 'You already own this profile' using errcode = '22023';
  end if;
  insert into public.profile_members (profile_id, user_id, role)
  values (p_profile_id, v_user_id, p_role)
  on conflict (profile_id, user_id) do update set role = excluded.role;
  return v_user_id;
end;
$$;

revoke all on function public.share_profile(uuid, text, text) from public, anon;
grant execute on function public.share_profile(uuid, text, text) to authenticated;
