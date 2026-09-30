-- Height and weight tracking: a log of height and weight checks for each athlete, and the
-- units each athlete's height and weight are shown in.
--
-- Values are stored in centimetres and kilograms whatever units the app shows. The ranges
-- match BodyMeasurement.heightRangeCm and weightRangeKg in the app.

alter table public.profiles
  add column body_units text not null default 'imperial' check (body_units in ('imperial', 'metric'));
comment on column public.profiles.body_units is 'How the app shows height and weight: imperial (ft, in, lb) or metric (cm, kg).';

create table public.body_measurements (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles (id) on delete cascade,
  measured_at  timestamptz not null,
  height_cm    numeric(4, 1) check (height_cm between 50 and 250),
  weight_kg    numeric(5, 2) check (weight_kg between 10 and 250),
  note         text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (height_cm is not null or weight_kg is not null)
);
create index body_measurements_profile_idx on public.body_measurements (profile_id, measured_at desc);
comment on table public.body_measurements is 'Height and weight checks, in centimetres and kilograms. Either can be left out.';

-- Same rules as every other profile table: members read, owners and editors write.
alter table public.body_measurements enable row level security;
create policy "Members can read" on public.body_measurements for select to authenticated
  using (private.can_read_profile(profile_id));
create policy "Owners and editors can add" on public.body_measurements for insert to authenticated
  with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can change" on public.body_measurements for update to authenticated
  using (private.can_edit_profile(profile_id)) with check (private.can_edit_profile(profile_id));
create policy "Owners and editors can delete" on public.body_measurements for delete to authenticated
  using (private.can_edit_profile(profile_id));
create trigger body_measurements_set_updated_at before update on public.body_measurements
  for each row execute function private.set_updated_at();

revoke all on public.body_measurements from anon;
grant select, insert, update, delete on public.body_measurements to authenticated;
