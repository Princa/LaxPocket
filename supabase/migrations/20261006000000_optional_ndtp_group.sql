-- The NDTP age group is optional: an athlete who isn't on an NDTP team has none. Combine results are scored against
-- the group's standards only when there is one.
alter table public.profiles
  alter column benchmark_group drop not null,
  alter column benchmark_group drop default;
comment on column public.profiles.benchmark_group is 'NDTP age group for scoring combine results. Null: not on an NDTP team.';
