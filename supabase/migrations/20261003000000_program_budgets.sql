-- Budgets by season and program: an overall budget for each season, what's set aside for each program in each
-- season, and expenses that say which program and season they're for.
--
-- Seasons are stored as the year they start (2026 = the 2026/27 season, which starts in August). A program can
-- run over several seasons (first_season to last_season, either end open) and has one budget per season.

alter table public.programs
  add column first_season integer check (first_season between 2000 and 2100),
  add column last_season  integer check (last_season between 2000 and 2100),
  add constraint programs_season_range_check check (first_season is null or last_season is null or last_season >= first_season);
comment on column public.programs.first_season is 'First season the program runs, as the year it starts (2026 = 2026/27). Null: no start.';
comment on column public.programs.last_season is 'Last season the program runs, as the year it starts. Null: ongoing.';

-- season is null on rows written before this migration (or by an older build); the app counts those toward the
-- season of spent_at. Deleting a program keeps its expenses and clears the link.
alter table public.expenses
  add column program_id text,
  add column season     integer check (season between 2000 and 2100),
  add constraint expenses_program_fkey foreign key (profile_id, program_id)
    references public.programs (profile_id, id) on delete set null (program_id);
create index expenses_profile_season_idx on public.expenses (profile_id, season);
comment on column public.expenses.program_id is 'The program the expense was for, if any.';
comment on column public.expenses.season is 'Season the expense counts toward, as the year it starts. Null: the season of spent_at.';

create table public.season_budgets (
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  season      integer not null check (season between 2000 and 2100),
  amount      numeric(10, 2) not null check (amount >= 0),
  note        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (profile_id, season)
);
comment on table public.season_budgets is 'Overall budget for each season, in the profile''s currency.';

create table public.program_budgets (
  profile_id  uuid not null,
  program_id  text not null,
  season      integer not null check (season between 2000 and 2100),
  amount      numeric(10, 2) not null check (amount >= 0),
  note        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (profile_id, program_id, season),
  foreign key (profile_id, program_id) references public.programs (profile_id, id) on delete cascade
);
comment on table public.program_budgets is 'What''s set aside for a program in a season. A program running several seasons has one row per season.';

-- The single budget each profile had becomes the budget for the season the profile is set to.
-- profiles.season_budget stays for older builds; the app no longer reads it.
insert into public.season_budgets (profile_id, season, amount)
select id, left(season_label, 4)::integer, season_budget
from public.profiles
where season_budget > 0 and season_label ~ '^(20[0-9]{2}|2100)'
on conflict do nothing;

-- Same rules as every other profile table: members read, owners and editors write.
-- Written out per table (no do-block) so the file runs as-is in the Supabase SQL Editor.

alter table public.season_budgets enable row level security;
create policy "Members can read" on public.season_budgets for select to authenticated
  using (private.can_read_profile(profile_id));
create policy "Owners and editors can add" on public.season_budgets for insert to authenticated
  with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can change" on public.season_budgets for update to authenticated
  using (private.can_edit_profile(profile_id)) with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can delete" on public.season_budgets for delete to authenticated
  using (private.can_edit_profile(profile_id));
create trigger season_budgets_set_updated_at before update on public.season_budgets
  for each row execute function private.set_updated_at();
revoke all on public.season_budgets from anon;
grant select, insert, update, delete on public.season_budgets to authenticated;

alter table public.program_budgets enable row level security;
create policy "Members can read" on public.program_budgets for select to authenticated
  using (private.can_read_profile(profile_id));
create policy "Owners and editors can add" on public.program_budgets for insert to authenticated
  with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can change" on public.program_budgets for update to authenticated
  using (private.can_edit_profile(profile_id)) with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can delete" on public.program_budgets for delete to authenticated
  using (private.can_edit_profile(profile_id));
create trigger program_budgets_set_updated_at before update on public.program_budgets
  for each row execute function private.set_updated_at();
revoke all on public.program_budgets from anon;
grant select, insert, update, delete on public.program_budgets to authenticated;
