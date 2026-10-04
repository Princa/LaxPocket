-- Tournament trips: where and when, how the family got there, the hotel, and a budget. Expenses say which trip they're
-- for, and get categories for what a trip costs: tournament fees, hotel and lodging, food, and other.
--
-- Days in the US are worked out by the app from each trip's dates and country.

create table public.trips (
  id                  uuid primary key default gen_random_uuid(),
  profile_id          uuid not null references public.profiles (id) on delete cascade,
  name                text not null default '',
  destination         text not null default '',
  country             text not null default 'US' check (country in ('US', 'CA', 'other')),
  departs_at          timestamptz not null,
  returns_at          timestamptz not null,
  season              integer not null check (season between 2000 and 2100),
  program_id          text,
  event_id            uuid,
  budget              numeric(10, 2) not null default 0 check (budget >= 0),
  travel_mode         text not null default 'drive' check (travel_mode in ('drive', 'fly', 'bus', 'train', 'other')),
  travel_details      text not null default '',
  hotel_name          text not null default '',
  hotel_address       text not null default '',
  hotel_confirmation  text not null default '',
  hotel_check_in      timestamptz,
  hotel_check_out     timestamptz,
  note                text not null default '',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (id, profile_id),
  check (returns_at >= departs_at),
  check (hotel_check_in is null or hotel_check_out is null or hotel_check_out >= hotel_check_in),
  -- Deleting the program or the event keeps the trip and clears the link.
  foreign key (profile_id, program_id) references public.programs (profile_id, id) on delete set null (program_id),
  foreign key (event_id, profile_id) references public.season_events (id, profile_id) on delete set null (event_id)
);
create index trips_profile_season_idx on public.trips (profile_id, season);
comment on table public.trips is 'A trip to a tournament, showcase or camp. Its costs are the expenses with its trip_id.';
comment on column public.trips.season is 'Season the trip counts toward, as the year it starts (2026 = 2026/27).';
comment on column public.trips.hotel_check_in is 'Null: the trip''s dates.';

-- Deleting a trip keeps its expenses and clears the link.
alter table public.expenses
  add column trip_id uuid,
  add constraint expenses_trip_fkey foreign key (trip_id, profile_id)
    references public.trips (id, profile_id) on delete set null (trip_id);
create index expenses_profile_trip_idx on public.expenses (profile_id, trip_id);
comment on column public.expenses.trip_id is 'The tournament trip the expense was for, if any.';

alter table public.expenses drop constraint expenses_category_check;
alter table public.expenses add constraint expenses_category_check
  check (category in ('teamFees', 'tournamentFees', 'coaching', 'fitness', 'travel', 'lodging', 'food', 'showcases', 'equipment',
                      'facility', 'other'));

-- Same rules as every other profile table: members read, owners and editors write.
alter table public.trips enable row level security;
create policy "Members can read" on public.trips for select to authenticated
  using (private.can_read_profile(profile_id));
create policy "Owners and editors can add" on public.trips for insert to authenticated
  with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can change" on public.trips for update to authenticated
  using (private.can_edit_profile(profile_id)) with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can delete" on public.trips for delete to authenticated
  using (private.can_edit_profile(profile_id));
create trigger trips_set_updated_at before update on public.trips
  for each row execute function private.set_updated_at();
revoke all on public.trips from anon;
grant select, insert, update, delete on public.trips to authenticated;
