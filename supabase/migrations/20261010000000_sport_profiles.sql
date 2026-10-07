-- Sport profiles: an athlete who plays several sports has one profile per sport (profiles.sport), grouped by
-- profiles.athlete_id, which points at the athlete's first profile (null on that first profile). Nothing is shared
-- between an athlete's sport profiles but the family: parents and the athlete's own login are on every one of them
-- without being invited again. Coaches belong to one sport: a roster has a sport, and only the athlete's profile for
-- that sport can join it, so a coach never sees the athlete's other sports. See docs/multi-sport.md.
--
-- A profile's sport and athlete_id are set when it's created and never change. Only the owner of an athlete's
-- profile can add a sport for them.
--
-- Safe to run again; constraints, functions and the view it sets are dropped (if there) or replaced.

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

alter table public.profiles add column if not exists sport text not null default 'lacrosse';
alter table public.profiles drop constraint if exists profiles_sport_check;
alter table public.profiles add constraint profiles_sport_check check (sport in ('lacrosse', 'hockey'));

alter table public.profiles add column if not exists athlete_id uuid;
alter table public.profiles add column if not exists shoots text;
alter table public.profiles drop constraint if exists profiles_shoots_check;
alter table public.profiles add constraint profiles_shoots_check check (shoots in ('left', 'right'));
alter table public.profiles add column if not exists plays_goal boolean not null default false;
alter table public.profiles add column if not exists level text not null default '';
alter table public.profiles drop constraint if exists profiles_level_check;
alter table public.profiles add constraint profiles_level_check check (length(level) <= 40);

create index if not exists profiles_athlete_idx on public.profiles ((coalesce(athlete_id, id)));

comment on column public.profiles.sport is 'The sport this profile is for. Set when the profile is created.';
comment on column public.profiles.athlete_id is
  'The athlete''s first profile, for a profile added for another sport. Null on the first one. Set when created.';
comment on column public.profiles.shoots is 'Hockey: left or right.';
comment on column public.profiles.plays_goal is 'Hockey: a goalie.';
comment on column public.profiles.level is 'Hockey: age group and tier, e.g. U15 AA.';

-- The athlete a profile belongs to: its athlete_id, or its own id for the athlete's first profile.
create or replace function private.athlete_key(p_profile_id uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select coalesce(p.athlete_id, p.id) from public.profiles p where p.id = p_profile_id
$$;

-- Every sport profile of the athlete a profile belongs to, itself included.
create or replace function private.athlete_profiles(p_profile_id uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p where coalesce(p.athlete_id, p.id) = private.athlete_key(p_profile_id)
$$;

-- A new profile for another sport has to belong to an athlete the signed-in account owns, and an athlete has one
-- profile per sport. Sport and athlete_id never change afterwards.
create or replace function private.guard_sport_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.sport := old.sport;
    new.athlete_id := old.athlete_id;
    return new;
  end if;
  -- An upsert of a profile that's already there carries on as the update above.
  if exists (select 1 from public.profiles p where p.id = new.id) then
    return new;
  end if;
  if new.athlete_id = new.id then
    new.athlete_id := null;
  end if;
  if new.athlete_id is not null and not exists (
    select 1 from public.profiles p
    where coalesce(p.athlete_id, p.id) = new.athlete_id and private.profile_role(p.id) = 'owner'
  ) then
    raise exception 'Only the athlete''s owner can add a sport for them' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.profiles p
    where coalesce(p.athlete_id, p.id) = coalesce(new.athlete_id, new.id) and p.sport = new.sport
  ) then
    raise exception 'This athlete already has a % profile', new.sport using errcode = '23505';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_sport on public.profiles;
create trigger profiles_guard_sport before insert or update on public.profiles
  for each row execute function private.guard_sport_profile();

revoke all on function private.athlete_key(uuid), private.athlete_profiles(uuid) from public, anon;
grant execute on function private.athlete_key(uuid), private.athlete_profiles(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- The family is on every sport
-- ---------------------------------------------------------------------------

-- Gives a sport profile the family on the athlete's other sports: every parent and the athlete's own login, with
-- their relationships, never coaches. The owner calls it after adding the sport. Returns how many people it added
-- or updated.
create or replace function public.add_family_to_sport(p_profile_id uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  if private.profile_role(p_profile_id) is distinct from 'owner' then
    raise exception 'Only the athlete''s owner can bring the family to a sport' using errcode = '42501';
  end if;
  with family as (
    select m.user_id, m.role, r
    from public.profile_members m
    cross join lateral unnest(m.relationships) r
    where m.profile_id in (select private.athlete_profiles(p_profile_id))
      and m.profile_id <> p_profile_id
      and m.user_id <> (select auth.uid())
      and r in ('parent', 'athlete')
  )
  insert into public.profile_members as m (profile_id, user_id, role, relationships)
  select p_profile_id, f.user_id, case when bool_or(f.role <> 'viewer') then 'editor' else 'viewer' end,
         array_agg(distinct f.r order by f.r)
  from family f
  group by f.user_id
  on conflict (profile_id, user_id) do update set
    relationships = array(select distinct r from unnest(m.relationships || excluded.relationships) r order by r),
    role = case when m.role = 'editor' or excluded.role = 'editor' then 'editor' else m.role end;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- As before, and a parent or athlete invite also puts the person on the athlete's other sports.
create or replace function public.accept_profile_invite(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_invite public.profile_invites;
  v_user uuid := (select auth.uid());
  v_role text;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  select * into v_invite from public.profile_invites
  where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
  for update;
  if not found or v_invite.accepted_at is not null or v_invite.expires_at < now() then
    raise exception 'That code isn''t valid. Codes work once and expire after a week.' using errcode = 'P0002';
  end if;
  if private.profile_role(v_invite.profile_id) = 'owner' then
    raise exception 'You already own this athlete' using errcode = '22023';
  end if;
  if v_invite.relationship = 'athlete' and exists (
    select 1 from public.profile_members m
    where m.profile_id = v_invite.profile_id and m.user_id <> v_user and 'athlete' = any (m.relationships)
  ) then
    raise exception 'This athlete already has their own account linked' using errcode = '23505';
  end if;

  v_role := case when v_invite.relationship in ('parent', 'athlete') then 'editor' else 'viewer' end;
  insert into public.profile_members as m (profile_id, user_id, role, relationships)
  select s, v_user, v_role, array[v_invite.relationship]
  from (select v_invite.profile_id as s
        union
        select a from private.athlete_profiles(v_invite.profile_id) a where v_invite.relationship in ('parent', 'athlete')) targets
  on conflict (profile_id, user_id) do update set
    relationships = array(select distinct r from unnest(m.relationships || excluded.relationships) r order by r),
    role = case when m.role = 'editor' or excluded.role = 'editor' then 'editor' else m.role end;

  update public.profile_invites set accepted_by = v_user, accepted_at = now() where code = v_invite.code;
  return v_invite.profile_id;
end;
$$;

-- As before, with the app's new name, and the person is shared on the athlete's other sports the owner owns.
create or replace function public.share_profile(p_profile_id uuid, p_email text, p_role text default 'editor')
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
    raise exception 'No SportsPocket account uses that email yet' using errcode = 'P0002';
  end if;
  if v_user_id = (select auth.uid()) then
    raise exception 'You already own this profile' using errcode = '22023';
  end if;
  insert into public.profile_members (profile_id, user_id, role)
  select s, v_user_id, p_role from private.athlete_profiles(p_profile_id) s where private.profile_role(s) = 'owner'
  on conflict (profile_id, user_id) do update set role = excluded.role;
  return v_user_id;
end;
$$;

-- Takes someone off an athlete: the owner removes anyone else, and anyone but the owner can leave. A parent or the
-- athlete's own login comes off every sport the athlete has (that the owner owns, when the owner removes them); anyone
-- else only off this profile. Returns the profiles they came off.
create or replace function public.remove_from_athlete(p_profile_id uuid, p_user_id uuid) returns setof uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := (select auth.uid());
  v_family boolean;
begin
  if v_me is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if p_user_id = v_me then
    if private.profile_role(p_profile_id) = 'owner' then
      raise exception 'The owner can''t leave the athlete' using errcode = '42501';
    end if;
  elsif private.profile_role(p_profile_id) is distinct from 'owner' then
    raise exception 'Only the athlete''s owner can remove people' using errcode = '42501';
  end if;
  select m.relationships && array['parent', 'athlete'] into v_family
  from public.profile_members m where m.profile_id = p_profile_id and m.user_id = p_user_id;

  return query
    delete from public.profile_members m
    where m.user_id = p_user_id and m.role <> 'owner'
      and (m.profile_id = p_profile_id
           or (coalesce(v_family, false)
               and m.profile_id in (select private.athlete_profiles(p_profile_id))
               and (p_user_id = v_me or private.profile_role(m.profile_id) = 'owner')))
    returning m.profile_id;
end;
$$;

revoke all on function public.add_family_to_sport(uuid), public.remove_from_athlete(uuid, uuid) from public, anon;
grant execute on function public.add_family_to_sport(uuid), public.remove_from_athlete(uuid, uuid) to authenticated;
revoke all on function public.accept_profile_invite(text), public.share_profile(uuid, text, text) from public, anon;
grant execute on function public.accept_profile_invite(text), public.share_profile(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Coaches belong to one sport
-- ---------------------------------------------------------------------------

alter table public.rosters add column if not exists sport text not null default 'lacrosse';
alter table public.rosters drop constraint if exists rosters_sport_check;
alter table public.rosters add constraint rosters_sport_check check (sport in ('lacrosse', 'hockey'));
comment on column public.rosters.sport is 'Only athletes'' profiles for this sport can join.';

drop function if exists public.create_roster(text, text);
create or replace function public.create_roster(p_name text, p_kind text, p_sport text default 'lacrosse') returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  insert into public.rosters (coach_id, kind, name, sport)
  values ((select auth.uid()), p_kind, btrim(coalesce(p_name, '')), coalesce(p_sport, 'lacrosse'))
  returning id into v_id;
  return v_id;
end;
$$;

-- As before, with the roster's sport.
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
  select jsonb_build_object('type', 'roster', 'roster', r.name, 'kind', r.kind, 'coach', coalesce(a.display_name, ''),
                            'sport', r.sport)
  into v_result
  from public.rosters r left join public.accounts a on a.user_id = r.coach_id
  where r.join_code = v_code;
  if v_result is null then
    raise exception 'That code isn''t valid. Ask for a new one.' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- As before, and only the athlete's profile for the roster's sport can join.
create or replace function public.join_roster(p_code text, p_profile_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_roster uuid;
  v_sport text;
begin
  if not private.is_parent(p_profile_id) then
    raise exception 'Only a parent can add the athlete to a coach''s roster' using errcode = '42501';
  end if;
  select r.id, r.sport into v_roster, v_sport from public.rosters r
  where r.join_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_roster is null then
    raise exception 'That code isn''t valid. Ask the coach for a new one.' using errcode = 'P0002';
  end if;
  if v_sport is distinct from (select p.sport from public.profiles p where p.id = p_profile_id) then
    raise exception 'This is a % roster. Pick the athlete''s % profile.', v_sport, v_sport using errcode = '22023';
  end if;
  insert into public.roster_athletes (roster_id, profile_id, added_by) values (v_roster, p_profile_id, (select auth.uid()))
  on conflict (roster_id, profile_id) do nothing;
  return v_roster;
end;
$$;

revoke all on function public.create_roster(text, text, text), public.describe_code(text), public.join_roster(text, uuid)
  from public, anon;
grant execute on function public.create_roster(text, text, text), public.describe_code(text), public.join_roster(text, uuid)
  to authenticated;

-- The athletes on the signed-in coach's rosters, now with their sport and hockey details.
create or replace view public.roster_athlete_profiles with (security_barrier = true) as
  select p.id, p.first_name, p.class_year, p.positions, p.benchmark_group, p.weekly_goal_hours, p.theme_id,
         p.sport, p.shoots, p.plays_goal, p.level
  from public.profiles p
  where exists (
    select 1 from public.roster_athletes ra join public.rosters r on r.id = ra.roster_id
    where ra.profile_id = p.id and r.coach_id = (select auth.uid())
  );
comment on view public.roster_athlete_profiles is 'Athletes on the signed-in coach''s rosters.';
revoke all on public.roster_athlete_profiles from anon;
revoke insert, update, delete on public.roster_athlete_profiles from authenticated;
grant select on public.roster_athlete_profiles to authenticated;
