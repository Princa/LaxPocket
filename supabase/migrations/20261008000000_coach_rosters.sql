-- Coach rosters: a coach's team, or a mental coach's clients. The coach shares the roster's code; a parent enters it
-- and picks which athlete to add, which is their consent. A coach reads the athletes on their rosters straight from
-- the cloud (a team coach their training and events, a mental coach their mental game as well); taking an athlete
-- off the roster ends it. Coaches never change an athlete's data here.
--
-- The athlete's own login can let a mental coach open the docs it locked (mental_coach_trust). Parents can't, and a
-- hidden doc stays the athlete's alone.
--
-- Mental sessions (training_sessions with category 'mental') now belong to the mental section, so a team coach
-- doesn't see them.
--
-- Safe to run again; policies it sets are dropped (if there) and created afresh.

-- ---------------------------------------------------------------------------
-- Rosters
-- ---------------------------------------------------------------------------

-- An 8-character code without look-alikes (no I, O, 0 or 1). Bytes 6 and 8 of a v4 UUID carry the version and
-- variant; the rest are random.
create or replace function private.new_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := uuid_send(gen_random_uuid());
  v_code text := '';
  i int;
begin
  foreach i in array array[0, 1, 2, 3, 4, 5, 10, 11] loop
    v_code := v_code || substr(v_alphabet, get_byte(v_bytes, i) % 32 + 1, 1);
  end loop;
  return v_code;
end;
$$;

create table if not exists public.rosters (
  id          uuid primary key default gen_random_uuid(),
  coach_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind        text not null check (kind in ('team', 'mental')),
  name        text not null check (length(btrim(name)) between 1 and 80),
  join_code   text unique default private.new_code() check (join_code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists rosters_coach_idx on public.rosters (coach_id);
comment on table public.rosters is 'A coach''s team (kind team) or a mental coach''s clients (kind mental).';
comment on column public.rosters.join_code is 'What a parent enters to add their athlete. Null: closed to new athletes.';

create table if not exists public.roster_athletes (
  roster_id   uuid not null references public.rosters (id) on delete cascade,
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  added_by    uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (roster_id, profile_id)
);
create index if not exists roster_athletes_profile_idx on public.roster_athletes (profile_id);
comment on table public.roster_athletes is 'Athletes on a roster. added_by is the parent who entered the code.';

create table if not exists public.mental_coach_trust (
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  athlete_id  uuid not null references auth.users (id) on delete cascade,
  coach_id    uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (profile_id, athlete_id, coach_id)
);
comment on table public.mental_coach_trust is 'Mental coaches the athlete''s login lets open the docs it locked.';

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------

-- Sections the signed-in account reads through its rosters: a team roster as a coach, a mental roster as a mental coach.
create or replace function private.roster_sections(p_profile_id uuid) returns text[]
language sql stable security definer set search_path = '' as $$
  select private.readable_sections(coalesce(
    array_agg(distinct case r.kind when 'team' then 'coach' else 'mentalCoach' end), '{}'))
  from public.roster_athletes ra
  join public.rosters r on r.id = ra.roster_id
  where ra.profile_id = p_profile_id and r.coach_id = (select auth.uid())
$$;

-- As before, plus what the account's rosters give it.
create or replace function private.can_read(p_profile_id uuid, p_section text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members m
    where m.profile_id = p_profile_id and m.user_id = (select auth.uid())
      and (m.role = 'owner' or p_section = any (private.readable_sections(m.relationships)))
  ) or p_section = any (private.roster_sections(p_profile_id))
$$;

-- The owner, or someone linked as a parent: who can add the athlete to a roster or take them off one.
create or replace function private.is_parent(p_profile_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members m
    where m.profile_id = p_profile_id and m.user_id = (select auth.uid())
      and (m.role = 'owner' or 'parent' = any (m.relationships))
  )
$$;

-- True when p_user_id can read the athlete's mental game as a mental coach, by invite or by roster.
create or replace function private.is_mental_coach(p_user_id uuid, p_profile_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members m
    where m.profile_id = p_profile_id and m.user_id = p_user_id and 'mentalCoach' = any (m.relationships)
  ) or exists (
    select 1 from public.roster_athletes ra join public.rosters r on r.id = ra.roster_id
    where ra.profile_id = p_profile_id and r.coach_id = p_user_id and r.kind = 'mental'
  )
$$;

-- True when the signed-in account may open a doc locked by p_locked_by.
create or replace function private.trusted_with_locked_docs(p_profile_id uuid, p_locked_by uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.mental_coach_trust t
    where t.profile_id = p_profile_id and t.athlete_id = p_locked_by and t.coach_id = (select auth.uid())
  ) and private.is_mental_coach((select auth.uid()), p_profile_id)
$$;

revoke all on function private.new_code(), private.roster_sections(uuid), private.is_parent(uuid),
  private.is_mental_coach(uuid, uuid), private.trusted_with_locked_docs(uuid, uuid) from public, anon;
grant execute on function private.new_code(), private.roster_sections(uuid), private.is_parent(uuid),
  private.is_mental_coach(uuid, uuid), private.trusted_with_locked_docs(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Functions the app calls
-- ---------------------------------------------------------------------------

create or replace function public.create_roster(p_name text, p_kind text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  insert into public.rosters (coach_id, kind, name) values ((select auth.uid()), p_kind, btrim(coalesce(p_name, '')))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.rename_roster(p_roster_id uuid, p_name text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.rosters set name = btrim(coalesce(p_name, ''))
  where id = p_roster_id and coach_id = (select auth.uid());
  if not found then
    raise exception 'Only the roster''s coach can rename it' using errcode = '42501';
  end if;
end;
$$;

-- A new code for the roster (the old one stops working), or none when p_open is false. Returns the code.
create or replace function public.reset_roster_code(p_roster_id uuid, p_open boolean default true) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
begin
  loop
    v_code := case when p_open then private.new_code() end;
    begin
      update public.rosters set join_code = v_code where id = p_roster_id and coach_id = (select auth.uid());
      if not found then
        raise exception 'Only the roster''s coach can change its code' using errcode = '42501';
      end if;
      return v_code;
    exception when unique_violation then
      -- Try another code.
    end;
  end loop;
end;
$$;

-- What a code is for, before it's used: an invite to an athlete, or a coach's roster.
create or replace function public.describe_code(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  select jsonb_build_object('type', 'invite', 'athlete', p.first_name, 'relationship', i.relationship)
  into v_result
  from public.profile_invites i join public.profiles p on p.id = i.profile_id
  where i.code = v_code and i.accepted_at is null and i.expires_at >= now();
  if v_result is not null then
    return v_result;
  end if;
  select jsonb_build_object('type', 'roster', 'roster', r.name, 'kind', r.kind, 'coach', coalesce(a.display_name, ''))
  into v_result
  from public.rosters r left join public.accounts a on a.user_id = r.coach_id
  where r.join_code = v_code;
  if v_result is null then
    raise exception 'That code isn''t valid. Ask for a new one.' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- Adds an athlete to the roster with this code. Only the athlete's owner or a parent can. Returns the roster's id.
create or replace function public.join_roster(p_code text, p_profile_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_roster uuid;
begin
  if not private.is_parent(p_profile_id) then
    raise exception 'Only a parent can add the athlete to a coach''s roster' using errcode = '42501';
  end if;
  select id into v_roster from public.rosters
  where join_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_roster is null then
    raise exception 'That code isn''t valid. Ask the coach for a new one.' using errcode = 'P0002';
  end if;
  insert into public.roster_athletes (roster_id, profile_id, added_by) values (v_roster, p_profile_id, (select auth.uid()))
  on conflict (roster_id, profile_id) do nothing;
  return v_roster;
end;
$$;

-- The rosters an athlete is on and their coaches, for the family's People list. can_open_locked says whether the
-- signed-in account (the athlete's login) lets that coach open the docs it locked.
create or replace function public.athlete_coaches(p_profile_id uuid)
returns table (roster_id uuid, roster_name text, kind text, coach_id uuid, coach_name text, can_open_locked boolean)
language sql stable security definer set search_path = '' as $$
  select r.id, r.name, r.kind, r.coach_id, coalesce(a.display_name, ''),
         exists (select 1 from public.mental_coach_trust t
                 where t.profile_id = p_profile_id and t.coach_id = r.coach_id and t.athlete_id = (select auth.uid()))
  from public.roster_athletes ra
  join public.rosters r on r.id = ra.roster_id
  left join public.accounts a on a.user_id = r.coach_id
  where ra.profile_id = p_profile_id and private.can_read_profile(p_profile_id)
  order by r.kind desc, r.name
$$;

-- The athlete's login lets a mental coach open the docs it locked, or stops letting them.
create or replace function public.set_mental_coach_trust(p_profile_id uuid, p_coach_id uuid, p_trusted boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_athlete(p_profile_id) then
    raise exception 'Only the athlete can choose who opens their locked documents' using errcode = '42501';
  end if;
  if p_trusted then
    if not private.is_mental_coach(p_coach_id, p_profile_id) then
      raise exception 'That account isn''t this athlete''s mental coach' using errcode = '22023';
    end if;
    insert into public.mental_coach_trust (profile_id, athlete_id, coach_id)
    values (p_profile_id, (select auth.uid()), p_coach_id)
    on conflict do nothing;
  else
    delete from public.mental_coach_trust
    where profile_id = p_profile_id and athlete_id = (select auth.uid()) and coach_id = p_coach_id;
  end if;
end;
$$;

revoke all on function public.create_roster(text, text), public.rename_roster(uuid, text), public.reset_roster_code(uuid, boolean),
  public.describe_code(text), public.join_roster(text, uuid), public.athlete_coaches(uuid),
  public.set_mental_coach_trust(uuid, uuid, boolean) from public, anon;
grant execute on function public.create_roster(text, text), public.rename_roster(uuid, text), public.reset_roster_code(uuid, boolean),
  public.describe_code(text), public.join_roster(text, uuid), public.athlete_coaches(uuid),
  public.set_mental_coach_trust(uuid, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Views for coaches
-- ---------------------------------------------------------------------------

-- The athletes on the signed-in coach's rosters: name and the details a coach needs, nothing about the budget.
-- Runs with the view owner's rights; the where clause does the access check.
create or replace view public.roster_athlete_profiles with (security_barrier = true) as
  select p.id, p.first_name, p.class_year, p.positions, p.benchmark_group, p.weekly_goal_hours, p.theme_id
  from public.profiles p
  where exists (
    select 1 from public.roster_athletes ra join public.rosters r on r.id = ra.roster_id
    where ra.profile_id = p.id and r.coach_id = (select auth.uid())
  );
comment on view public.roster_athlete_profiles is 'Athletes on the signed-in coach''s rosters.';

-- Placeholders for locked docs, now leaving out the ones this account may open.
create or replace view public.locked_mental_docs with (security_barrier = true) as
  select d.id, d.profile_id, d.folder, d.doc_updated_at
  from public.mental_docs d
  where d.visibility = 'locked'
    and d.locked_by is distinct from (select auth.uid())
    and private.can_read(d.profile_id, 'mental')
    and not private.trusted_with_locked_docs(d.profile_id, d.locked_by);

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.rosters enable row level security;
drop policy if exists "Coaches see their rosters" on public.rosters;
create policy "Coaches see their rosters" on public.rosters for select to authenticated
  using (coach_id = (select auth.uid()));
drop policy if exists "Coaches delete their rosters" on public.rosters;
create policy "Coaches delete their rosters" on public.rosters for delete to authenticated
  using (coach_id = (select auth.uid()));
drop trigger if exists rosters_set_updated_at on public.rosters;
create trigger rosters_set_updated_at before update on public.rosters
  for each row execute function private.set_updated_at();
revoke all on public.rosters from anon;
revoke insert, update on public.rosters from authenticated;
grant select, delete on public.rosters to authenticated;

-- Athletes join through join_roster. The coach or a parent can take an athlete off.
alter table public.roster_athletes enable row level security;
drop policy if exists "Coaches and families see roster places" on public.roster_athletes;
create policy "Coaches and families see roster places" on public.roster_athletes for select to authenticated
  using (private.can_read_profile(profile_id)
         or exists (select 1 from public.rosters r where r.id = roster_id and r.coach_id = (select auth.uid())));
drop policy if exists "Coaches and parents take athletes off" on public.roster_athletes;
create policy "Coaches and parents take athletes off" on public.roster_athletes for delete to authenticated
  using (private.is_parent(profile_id)
         or exists (select 1 from public.rosters r where r.id = roster_id and r.coach_id = (select auth.uid())));
revoke all on public.roster_athletes from anon;
revoke insert, update on public.roster_athletes from authenticated;
grant select, delete on public.roster_athletes to authenticated;

-- Changed through set_mental_coach_trust; the athlete and the coach can see it.
alter table public.mental_coach_trust enable row level security;
drop policy if exists "Athletes and their coaches see trust" on public.mental_coach_trust;
create policy "Athletes and their coaches see trust" on public.mental_coach_trust for select to authenticated
  using (athlete_id = (select auth.uid()) or coach_id = (select auth.uid()));
revoke all on public.mental_coach_trust from anon;
revoke insert, update, delete on public.mental_coach_trust from authenticated;
grant select on public.mental_coach_trust to authenticated;

revoke all on public.roster_athlete_profiles from anon;
revoke insert, update, delete on public.roster_athlete_profiles from authenticated;
grant select on public.roster_athlete_profiles to authenticated;

-- A locked doc opens for the athlete who locked it and the mental coaches they trust.
drop policy if exists "Members can read" on public.mental_docs;
create policy "Members can read" on public.mental_docs for select to authenticated
  using (private.can_read(profile_id, 'mental')
         and (visibility = 'shared' or locked_by = (select auth.uid())
              or (visibility = 'locked' and private.trusted_with_locked_docs(profile_id, locked_by))));

-- Mental sessions are part of the mental section.
drop policy if exists "Members can read" on public.training_sessions;
create policy "Members can read" on public.training_sessions for select to authenticated
  using (private.can_read(profile_id, 'training') and (category <> 'mental' or private.can_read(profile_id, 'mental')));
