-- Mental training: sessions with the mental performance coach (going over the game plan,
-- pre-game preparation, visualisation) are logged as their own session category.
--
-- Matches SessionCategory in the app. Mental hours count toward weekly hours but not the
-- workload ratio, which the app works out from team, skills and fitness hours only.

alter table public.programs drop constraint programs_session_category_check;
alter table public.programs
  add constraint programs_session_category_check check (session_category in ('team', 'skills', 'fitness', 'mental'));

alter table public.training_sessions drop constraint training_sessions_category_check;
alter table public.training_sessions
  add constraint training_sessions_category_check check (category in ('team', 'skills', 'fitness', 'mental'));

comment on table public.training_sessions is 'Logged practices, lessons, workouts and mental sessions. effort is session RPE 1–10.';
