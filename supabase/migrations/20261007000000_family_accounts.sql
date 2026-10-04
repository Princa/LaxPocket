-- Family accounts: who each account is, how it's related to each athlete, invite codes for linking an athlete's or a
-- parent's own login, what each relationship can see, and mental-game documents the athlete can lock.
--
-- Relationships (profile_members.relationships) decide which sections of an athlete's data an account sees:
--
--   section    tables                                                             parent  athlete  coach  mental coach
--   training   programs, training_sessions, combine_*, wallball_*                  write   write    read   read
--   events     season_events and everything under an event                         write   write    read   read
--   health     body_measurements                                                   write   write    -      -
--   budget     expenses, trips, season_budgets, program_budgets                    write   read     -      -
--   mental     mental_docs                                                          write   write    -      read
--
-- Writing also needs the owner or editor role, as before; the owner can read and write every section. Existing
-- members become parents, so nobody loses access. Relationship values match Relationship in the app.
--
-- A mental doc is shared (everyone who sees the mental section), locked (others see that it exists, not what it is)
-- or hidden (only the athlete). Only an account linked as the athlete can lock one, and a locked or hidden doc is
-- readable only by the account that locked it, so changing who's linked as the athlete doesn't reveal it.
--
-- Safe to run again, and it doesn't depend on the policies already on a table: each one it sets is dropped (if
-- there) and created afresh. The last statement lists any other policy left on an athlete's tables; it should
-- return no rows.

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------

create table if not exists public.accounts (
  user_id       uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  display_name  text not null default '' check (length(display_name) <= 80),
  kind          text not null check (kind in ('parent', 'athlete', 'coach', 'mentalCoach')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table public.accounts is 'Who a LaxPocket account belongs to: the name others see and whether they''re a parent, athlete or coach.';

-- ---------------------------------------------------------------------------
-- Relationships
-- ---------------------------------------------------------------------------

alter table public.profile_members
  add column if not exists relationships text[] not null default '{parent}'
    check (cardinality(relationships) between 1 and 4
           and relationships <@ array['parent', 'athlete', 'coach', 'mentalCoach']);
comment on column public.profile_members.relationships is
  'How the account is related to the athlete. Decides which sections it sees; role decides whether it can change them.';

-- Owners still change roles, but relationships only change through an invite: an owner who could make any account
-- "the athlete" could read what the athlete locked.
revoke insert, update on public.profile_members from authenticated;
grant insert (profile_id, user_id, role) on public.profile_members to authenticated;
grant update (role) on public.profile_members to authenticated;

create or replace function private.readable_sections(p_relationships text[]) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(distinct s order by s), '{}')
  from unnest(p_relationships) r
  cross join lateral unnest(case r
    when 'parent'      then array['training', 'events', 'health', 'budget', 'mental']
    when 'athlete'     then array['training', 'events', 'health', 'budget', 'mental']
    when 'coach'       then array['training', 'events']
    when 'mentalCoach' then array['training', 'events', 'mental']
    else array[]::text[]
  end) s
$$;

create or replace function private.writable_sections(p_relationships text[]) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(distinct s order by s), '{}')
  from unnest(p_relationships) r
  cross join lateral unnest(case r
    when 'parent'  then array['training', 'events', 'health', 'budget', 'mental']
    when 'athlete' then array['training', 'events', 'health', 'mental']
    else array[]::text[]
  end) s
$$;

create or replace function private.can_read(p_profile_id uuid, p_section text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members m
    where m.profile_id = p_profile_id and m.user_id = (select auth.uid())
      and (m.role = 'owner' or p_section = any (private.readable_sections(m.relationships)))
  )
$$;

create or replace function private.can_write(p_profile_id uuid, p_section text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members m
    where m.profile_id = p_profile_id and m.user_id = (select auth.uid())
      and (m.role = 'owner' or (m.role = 'editor' and p_section = any (private.writable_sections(m.relationships))))
  )
$$;

create or replace function private.is_athlete(p_profile_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members m
    where m.profile_id = p_profile_id and m.user_id = (select auth.uid()) and 'athlete' = any (m.relationships)
  )
$$;

-- True when the signed-in account and p_user_id are both on some athlete.
create or replace function private.shares_an_athlete_with(p_user_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profile_members mine
    join public.profile_members theirs on theirs.profile_id = mine.profile_id
    where mine.user_id = (select auth.uid()) and theirs.user_id = p_user_id
  )
$$;

revoke all on function private.readable_sections(text[]), private.writable_sections(text[]), private.can_read(uuid, text),
  private.can_write(uuid, text), private.is_athlete(uuid), private.shares_an_athlete_with(uuid) from public, anon;
grant execute on function private.readable_sections(text[]), private.writable_sections(text[]), private.can_read(uuid, text),
  private.can_write(uuid, text), private.is_athlete(uuid), private.shares_an_athlete_with(uuid) to authenticated;

-- An account set up as an athlete that creates a profile is its athlete as well as its owner.
create or replace function private.add_profile_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.created_by is not null then
    insert into public.profile_members (profile_id, user_id, role, relationships)
    values (new.id, new.created_by, 'owner',
            case when exists (select 1 from public.accounts a where a.user_id = new.created_by and a.kind = 'athlete')
                 then '{athlete}'::text[] else '{parent}'::text[] end)
    on conflict (profile_id, user_id) do update set role = 'owner';
  end if;
  return new;
end;
$$;

-- What the signed-in account can do with each athlete it's on.
create or replace view public.my_profile_access with (security_invoker = true) as
  select m.profile_id, m.role, m.relationships
  from public.profile_members m
  where m.user_id = (select auth.uid());
comment on view public.my_profile_access is 'The signed-in account''s role and relationships for each athlete it''s on.';

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

-- The owner makes a code; whoever enters it is linked to the athlete with the invite's relationship. An accepted
-- athlete invite is the parent's consent for the athlete's own account, so invites are kept after use.
create table if not exists public.profile_invites (
  code          text primary key check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  profile_id    uuid not null references public.profiles (id) on delete cascade,
  relationship  text not null check (relationship in ('parent', 'athlete', 'coach', 'mentalCoach')),
  created_by    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '7 days',
  accepted_by   uuid references auth.users (id) on delete set null,
  accepted_at   timestamptz
);
create index if not exists profile_invites_profile_idx on public.profile_invites (profile_id, created_at desc);
comment on table public.profile_invites is 'Codes for linking an account to an athlete. Single use; expire after a week.';

-- Makes an invite code for the athlete. Owner only. Codes are 8 characters without look-alikes (no I, O, 0 or 1).
create or replace function public.create_profile_invite(p_profile_id uuid, p_relationship text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
  i int;
begin
  if private.profile_role(p_profile_id) is distinct from 'owner' then
    raise exception 'Only the athlete''s owner can invite people' using errcode = '42501';
  end if;
  if p_relationship is null or p_relationship not in ('parent', 'athlete', 'coach', 'mentalCoach') then
    raise exception 'Unknown relationship' using errcode = '22023';
  end if;
  loop
    -- Bytes 6 and 8 of a v4 UUID carry the version and variant; the rest are random.
    v_bytes := uuid_send(gen_random_uuid());
    v_code := '';
    foreach i in array array[0, 1, 2, 3, 4, 5, 10, 11] loop
      v_code := v_code || substr(v_alphabet, get_byte(v_bytes, i) % 32 + 1, 1);
    end loop;
    begin
      insert into public.profile_invites (code, profile_id, relationship, created_by)
      values (v_code, p_profile_id, p_relationship, (select auth.uid()));
      return v_code;
    exception when unique_violation then
      -- Try another code.
    end;
  end loop;
end;
$$;

-- Links the signed-in account to the invite's athlete and returns the athlete's id. Parents and athletes can change
-- the athlete's data (editor); coaches can read it (viewer). Accepting a second relationship keeps the first.
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
  values (v_invite.profile_id, v_user, v_role, array[v_invite.relationship])
  on conflict (profile_id, user_id) do update set
    relationships = array(select distinct r from unnest(m.relationships || excluded.relationships) r order by r),
    role = case when m.role = 'editor' or excluded.role = 'editor' then 'editor' else m.role end;

  update public.profile_invites set accepted_by = v_user, accepted_at = now() where code = v_invite.code;
  return v_invite.profile_id;
end;
$$;

revoke all on function public.create_profile_invite(uuid, text), public.accept_profile_invite(text) from public, anon;
grant execute on function public.create_profile_invite(uuid, text), public.accept_profile_invite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Locked mental docs
-- ---------------------------------------------------------------------------

alter table public.mental_docs
  add column if not exists visibility text not null default 'shared' check (visibility in ('shared', 'locked', 'hidden')),
  add column if not exists locked_by  uuid references auth.users (id) on delete set null;
comment on column public.mental_docs.visibility is
  'shared: everyone who sees the mental section. locked: others see it exists, not what it is. hidden: only the athlete.';
comment on column public.mental_docs.locked_by is 'The athlete account that locked or hid the doc; only it can read it or change that.';

-- Only the athlete locks or hides a doc, and only the account that did can open it up again. locked_by is always
-- set here, never by the app.
create or replace function private.guard_doc_visibility() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
begin
  if new.visibility = 'shared' then
    if tg_op = 'UPDATE' and old.visibility <> 'shared' and old.locked_by is distinct from v_user then
      raise exception 'Only the athlete who locked this document can share it' using errcode = '42501';
    end if;
    new.locked_by := null;
  elsif tg_op = 'INSERT' or old.visibility = 'shared' then
    if not private.is_athlete(new.profile_id) then
      raise exception 'Only the athlete can lock their documents' using errcode = '42501';
    end if;
    new.locked_by := v_user;
  else
    if old.locked_by is distinct from v_user then
      raise exception 'Only the athlete who locked this document can change it' using errcode = '42501';
    end if;
    new.locked_by := old.locked_by;
  end if;
  return new;
end;
$$;

drop trigger if exists mental_docs_guard_visibility on public.mental_docs;
create trigger mental_docs_guard_visibility before insert or update on public.mental_docs
  for each row execute function private.guard_doc_visibility();

drop policy if exists "Members can read" on public.mental_docs;
create policy "Members can read" on public.mental_docs for select to authenticated
  using (private.can_read(profile_id, 'mental') and (visibility = 'shared' or locked_by = (select auth.uid())));
drop policy if exists "Owners and editors can add" on public.mental_docs;
create policy "Owners and editors can add" on public.mental_docs for insert to authenticated
  with check (private.can_write(profile_id, 'mental'));
drop policy if exists "Owners and editors can change" on public.mental_docs;
create policy "Owners and editors can change" on public.mental_docs for update to authenticated
  using (private.can_write(profile_id, 'mental') and (visibility = 'shared' or locked_by = (select auth.uid())))
  with check (private.can_write(profile_id, 'mental'));
drop policy if exists "Owners and editors can delete" on public.mental_docs;
create policy "Owners and editors can delete" on public.mental_docs for delete to authenticated
  using (private.can_write(profile_id, 'mental') and (visibility = 'shared' or locked_by = (select auth.uid())));

-- What a locked doc shows everyone else on the athlete: that it's there, its folder and when it changed.
-- Runs with the view owner's rights so it can see the locked rows; the where clause does the access check.
create or replace view public.locked_mental_docs with (security_barrier = true) as
  select d.id, d.profile_id, d.folder, d.doc_updated_at
  from public.mental_docs d
  where d.visibility = 'locked'
    and d.locked_by is distinct from (select auth.uid())
    and private.can_read(d.profile_id, 'mental');
comment on view public.locked_mental_docs is 'Locked mental docs as others on the athlete see them: no title, link or note.';

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.accounts enable row level security;
drop policy if exists "People on the same athlete can see each other" on public.accounts;
create policy "People on the same athlete can see each other" on public.accounts for select to authenticated
  using (user_id = (select auth.uid()) or private.shares_an_athlete_with(user_id));
drop policy if exists "Accounts set themselves up" on public.accounts;
create policy "Accounts set themselves up" on public.accounts for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "Accounts change themselves" on public.accounts;
create policy "Accounts change themselves" on public.accounts for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop trigger if exists accounts_set_updated_at on public.accounts;
create trigger accounts_set_updated_at before update on public.accounts
  for each row execute function private.set_updated_at();
revoke all on public.accounts from anon;
grant select, insert, update on public.accounts to authenticated;

-- Invites are made and accepted through the functions above; owners can list and cancel them.
alter table public.profile_invites enable row level security;
drop policy if exists "Owners can see invites" on public.profile_invites;
create policy "Owners can see invites" on public.profile_invites for select to authenticated
  using (private.profile_role(profile_id) = 'owner');
drop policy if exists "Owners can cancel invites" on public.profile_invites;
create policy "Owners can cancel invites" on public.profile_invites for delete to authenticated
  using (private.profile_role(profile_id) = 'owner');
revoke all on public.profile_invites from anon;
revoke insert, update on public.profile_invites from authenticated;
grant select, delete on public.profile_invites to authenticated;

revoke all on public.my_profile_access, public.locked_mental_docs from anon;
revoke insert, update, delete on public.my_profile_access, public.locked_mental_docs from authenticated;
grant select on public.my_profile_access, public.locked_mental_docs to authenticated;

-- Every other athlete table: reading needs its section, writing needs the section and the owner or editor role.
-- The policies keep the names the earlier migrations gave them.

-- training
drop policy if exists "Members can read" on public.programs;
create policy "Members can read" on public.programs for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.programs;
create policy "Owners and editors can add" on public.programs for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.programs;
create policy "Owners and editors can change" on public.programs for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.programs;
create policy "Owners and editors can delete" on public.programs for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop policy if exists "Members can read" on public.training_sessions;
create policy "Members can read" on public.training_sessions for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.training_sessions;
create policy "Owners and editors can add" on public.training_sessions for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.training_sessions;
create policy "Owners and editors can change" on public.training_sessions for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.training_sessions;
create policy "Owners and editors can delete" on public.training_sessions for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop policy if exists "Members can read" on public.combine_results;
create policy "Members can read" on public.combine_results for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.combine_results;
create policy "Owners and editors can add" on public.combine_results for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.combine_results;
create policy "Owners and editors can change" on public.combine_results for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.combine_results;
create policy "Owners and editors can delete" on public.combine_results for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop policy if exists "Members can read" on public.combine_measurements;
create policy "Members can read" on public.combine_measurements for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.combine_measurements;
create policy "Owners and editors can add" on public.combine_measurements for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.combine_measurements;
create policy "Owners and editors can change" on public.combine_measurements for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.combine_measurements;
create policy "Owners and editors can delete" on public.combine_measurements for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop policy if exists "Members can read" on public.wallball_drills;
create policy "Members can read" on public.wallball_drills for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.wallball_drills;
create policy "Owners and editors can add" on public.wallball_drills for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.wallball_drills;
create policy "Owners and editors can change" on public.wallball_drills for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.wallball_drills;
create policy "Owners and editors can delete" on public.wallball_drills for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop policy if exists "Members can read" on public.wallball_sessions;
create policy "Members can read" on public.wallball_sessions for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.wallball_sessions;
create policy "Owners and editors can add" on public.wallball_sessions for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.wallball_sessions;
create policy "Owners and editors can change" on public.wallball_sessions for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.wallball_sessions;
create policy "Owners and editors can delete" on public.wallball_sessions for delete to authenticated
  using (private.can_write(profile_id, 'training'));
drop policy if exists "Members can read" on public.wallball_sets;
create policy "Members can read" on public.wallball_sets for select to authenticated
  using (private.can_read(profile_id, 'training'));
drop policy if exists "Owners and editors can add" on public.wallball_sets;
create policy "Owners and editors can add" on public.wallball_sets for insert to authenticated
  with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can change" on public.wallball_sets;
create policy "Owners and editors can change" on public.wallball_sets for update to authenticated
  using (private.can_write(profile_id, 'training')) with check (private.can_write(profile_id, 'training'));
drop policy if exists "Owners and editors can delete" on public.wallball_sets;
create policy "Owners and editors can delete" on public.wallball_sets for delete to authenticated
  using (private.can_write(profile_id, 'training'));

-- events
drop policy if exists "Members can read" on public.season_events;
create policy "Members can read" on public.season_events for select to authenticated
  using (private.can_read(profile_id, 'events'));
drop policy if exists "Owners and editors can add" on public.season_events;
create policy "Owners and editors can add" on public.season_events for insert to authenticated
  with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can change" on public.season_events;
create policy "Owners and editors can change" on public.season_events for update to authenticated
  using (private.can_write(profile_id, 'events')) with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can delete" on public.season_events;
create policy "Owners and editors can delete" on public.season_events for delete to authenticated
  using (private.can_write(profile_id, 'events'));
drop policy if exists "Members can read" on public.game_stats;
create policy "Members can read" on public.game_stats for select to authenticated
  using (private.can_read(profile_id, 'events'));
drop policy if exists "Owners and editors can add" on public.game_stats;
create policy "Owners and editors can add" on public.game_stats for insert to authenticated
  with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can change" on public.game_stats;
create policy "Owners and editors can change" on public.game_stats for update to authenticated
  using (private.can_write(profile_id, 'events')) with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can delete" on public.game_stats;
create policy "Owners and editors can delete" on public.game_stats for delete to authenticated
  using (private.can_write(profile_id, 'events'));
drop policy if exists "Members can read" on public.game_reflections;
create policy "Members can read" on public.game_reflections for select to authenticated
  using (private.can_read(profile_id, 'events'));
drop policy if exists "Owners and editors can add" on public.game_reflections;
create policy "Owners and editors can add" on public.game_reflections for insert to authenticated
  with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can change" on public.game_reflections;
create policy "Owners and editors can change" on public.game_reflections for update to authenticated
  using (private.can_write(profile_id, 'events')) with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can delete" on public.game_reflections;
create policy "Owners and editors can delete" on public.game_reflections for delete to authenticated
  using (private.can_write(profile_id, 'events'));
drop policy if exists "Members can read" on public.event_focus_goals;
create policy "Members can read" on public.event_focus_goals for select to authenticated
  using (private.can_read(profile_id, 'events'));
drop policy if exists "Owners and editors can add" on public.event_focus_goals;
create policy "Owners and editors can add" on public.event_focus_goals for insert to authenticated
  with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can change" on public.event_focus_goals;
create policy "Owners and editors can change" on public.event_focus_goals for update to authenticated
  using (private.can_write(profile_id, 'events')) with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can delete" on public.event_focus_goals;
create policy "Owners and editors can delete" on public.event_focus_goals for delete to authenticated
  using (private.can_write(profile_id, 'events'));
drop policy if exists "Members can read" on public.event_videos;
create policy "Members can read" on public.event_videos for select to authenticated
  using (private.can_read(profile_id, 'events'));
drop policy if exists "Owners and editors can add" on public.event_videos;
create policy "Owners and editors can add" on public.event_videos for insert to authenticated
  with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can change" on public.event_videos;
create policy "Owners and editors can change" on public.event_videos for update to authenticated
  using (private.can_write(profile_id, 'events')) with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can delete" on public.event_videos;
create policy "Owners and editors can delete" on public.event_videos for delete to authenticated
  using (private.can_write(profile_id, 'events'));
drop policy if exists "Members can read" on public.event_checklist_items;
create policy "Members can read" on public.event_checklist_items for select to authenticated
  using (private.can_read(profile_id, 'events'));
drop policy if exists "Owners and editors can add" on public.event_checklist_items;
create policy "Owners and editors can add" on public.event_checklist_items for insert to authenticated
  with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can change" on public.event_checklist_items;
create policy "Owners and editors can change" on public.event_checklist_items for update to authenticated
  using (private.can_write(profile_id, 'events')) with check (private.can_write(profile_id, 'events'));
drop policy if exists "Owners and editors can delete" on public.event_checklist_items;
create policy "Owners and editors can delete" on public.event_checklist_items for delete to authenticated
  using (private.can_write(profile_id, 'events'));

-- health
drop policy if exists "Members can read" on public.body_measurements;
create policy "Members can read" on public.body_measurements for select to authenticated
  using (private.can_read(profile_id, 'health'));
drop policy if exists "Owners and editors can add" on public.body_measurements;
create policy "Owners and editors can add" on public.body_measurements for insert to authenticated
  with check (private.can_write(profile_id, 'health'));
drop policy if exists "Owners and editors can change" on public.body_measurements;
create policy "Owners and editors can change" on public.body_measurements for update to authenticated
  using (private.can_write(profile_id, 'health')) with check (private.can_write(profile_id, 'health'));
drop policy if exists "Owners and editors can delete" on public.body_measurements;
create policy "Owners and editors can delete" on public.body_measurements for delete to authenticated
  using (private.can_write(profile_id, 'health'));

-- budget
drop policy if exists "Members can read" on public.expenses;
create policy "Members can read" on public.expenses for select to authenticated
  using (private.can_read(profile_id, 'budget'));
drop policy if exists "Owners and editors can add" on public.expenses;
create policy "Owners and editors can add" on public.expenses for insert to authenticated
  with check (private.can_write(profile_id, 'budget'));
drop policy if exists "Owners and editors can change" on public.expenses;
create policy "Owners and editors can change" on public.expenses for update to authenticated
  using (private.can_write(profile_id, 'budget')) with check (private.can_write(profile_id, 'budget'));
drop policy if exists "Owners and editors can delete" on public.expenses;
create policy "Owners and editors can delete" on public.expenses for delete to authenticated
  using (private.can_write(profile_id, 'budget'));
drop policy if exists "Members can read" on public.trips;
create policy "Members can read" on public.trips for select to authenticated
  using (private.can_read(profile_id, 'budget'));
drop policy if exists "Owners and editors can add" on public.trips;
create policy "Owners and editors can add" on public.trips for insert to authenticated
  with check (private.can_write(profile_id, 'budget'));
drop policy if exists "Owners and editors can change" on public.trips;
create policy "Owners and editors can change" on public.trips for update to authenticated
  using (private.can_write(profile_id, 'budget')) with check (private.can_write(profile_id, 'budget'));
drop policy if exists "Owners and editors can delete" on public.trips;
create policy "Owners and editors can delete" on public.trips for delete to authenticated
  using (private.can_write(profile_id, 'budget'));
drop policy if exists "Members can read" on public.season_budgets;
create policy "Members can read" on public.season_budgets for select to authenticated
  using (private.can_read(profile_id, 'budget'));
drop policy if exists "Owners and editors can add" on public.season_budgets;
create policy "Owners and editors can add" on public.season_budgets for insert to authenticated
  with check (private.can_write(profile_id, 'budget'));
drop policy if exists "Owners and editors can change" on public.season_budgets;
create policy "Owners and editors can change" on public.season_budgets for update to authenticated
  using (private.can_write(profile_id, 'budget')) with check (private.can_write(profile_id, 'budget'));
drop policy if exists "Owners and editors can delete" on public.season_budgets;
create policy "Owners and editors can delete" on public.season_budgets for delete to authenticated
  using (private.can_write(profile_id, 'budget'));
drop policy if exists "Members can read" on public.program_budgets;
create policy "Members can read" on public.program_budgets for select to authenticated
  using (private.can_read(profile_id, 'budget'));
drop policy if exists "Owners and editors can add" on public.program_budgets;
create policy "Owners and editors can add" on public.program_budgets for insert to authenticated
  with check (private.can_write(profile_id, 'budget'));
drop policy if exists "Owners and editors can change" on public.program_budgets;
create policy "Owners and editors can change" on public.program_budgets for update to authenticated
  using (private.can_write(profile_id, 'budget')) with check (private.can_write(profile_id, 'budget'));
drop policy if exists "Owners and editors can delete" on public.program_budgets;
create policy "Owners and editors can delete" on public.program_budgets for delete to authenticated
  using (private.can_write(profile_id, 'budget'));

-- Policies are permissive, so any other policy on these tables would let more people in than the sections above.
-- This should return no rows; drop any it lists unless you added it on purpose.
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename in (
  'programs', 'training_sessions', 'combine_results', 'combine_measurements', 'wallball_drills',
  'wallball_sessions', 'wallball_sets', 'season_events', 'game_stats', 'game_reflections',
  'event_focus_goals', 'event_videos', 'event_checklist_items', 'body_measurements', 'expenses',
  'trips', 'season_budgets', 'program_budgets', 'mental_docs')
  and policyname not in ('Members can read', 'Owners and editors can add', 'Owners and editors can change', 'Owners and editors can delete')
order by tablename, policyname;
