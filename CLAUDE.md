# SportsPocket (LaxPocket in code)

iPhone app (SwiftUI, iOS 17) with its logic in the `LaxPocketCore` Swift package (`Core/`) and an optional Supabase
backend (`supabase/`). See README.md for what each screen does.

## Working on it

- The user keeps the project open in Xcode and expects changes to show up there without regenerating the project
  or picking the signing team again. Keep it that way:
  - The Xcode project is generated from `project.yml` by XcodeGen and isn't committed. `LaxPocket/` is a
    synchronized folder (`type: syncedFolder`, Xcode 16+) and `Core/` is a local Swift package, so files added,
    renamed or removed in either appear in Xcode by themselves. Don't regenerate for them, and don't turn the app's
    sources back into ordinary groups.
  - Only after editing `project.yml`, run `scripts/xcodegen-if-needed.sh`. It regenerates only when `project.yml` or
    the XcodeGen version changed, so an open Xcode isn't asked to reload for nothing. Don't run plain
    `xcodegen generate` in the repo. The git hooks in `.githooks` run the script after pulls, checkouts and rebases
    once `scripts/setup-mac.sh` has been run.
  - `LaxPocket/Info.plist` is generated from `info.properties` in `project.yml`; change it there.
  - Signing comes from `Config/Local.xcconfig` (the developer's team ID, not committed) through
    `Config/Signing.xcconfig`, which `configFiles` in `project.yml` points at, so regenerating keeps the team. Never
    put a team ID in `project.yml`, never commit `Local.xcconfig`, and keep `configFiles` as it is.
- Logic and models go in `Core/Sources/LaxPocketCore` with tests in `Core/Tests`; keep views in `LaxPocket/Features`.
- The app is going multi-sport (lacrosse and hockey, more later) as planned in `docs/multi-sport.md`. Sports are
  completely separate: an athlete has one sport profile per sport, their data is never added up across sports, and a
  coach only sees the one sport their roster is for. The family (parents and the athlete's own login) is the same in
  every sport: adding a sport brings them along, and only a new person is invited. Update the doc when the plan
  changes.
- In the cloud, a profile's `sport` and `athlete_id` never change after it's created. Keeping the family the same
  across an athlete's sports is done in three functions (sport profiles migration): `add_family_to_sport`,
  `accept_profile_invite` and `remove_from_athlete`. A change to how members are added or removed goes in all three.
- The app is called SportsPocket on the phone; the bundle ID (`com.princa.laxpocket`), URL scheme, Xcode project,
  `LaxPocketCore` and the storage folder keep the LaxPocket name. Never change the bundle ID or the storage folder:
  phones would lose the athletes saved on them.
- Several Claude sessions can work in this one checkout. Don't stash, reset or switch branches over changes you didn't
  make, and commit your own work to its branch at each milestone: another session once stashed half-done work and
  switched branches under it.
- Check before pushing:
  - `cd Core && swift test`
  - `supabase/tests/run-local.sh` when a migration or `supabase/tests/rls_test.sql` changes (needs a local Postgres)
  - On a Mac, build the app: `xcodebuild -project LaxPocket.xcodeproj -scheme LaxPocket -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- Before adding a migration, fetch `origin/main` and give the file a timestamp after the newest one there: two branches
  once both added a `20261009000000_…` migration.
- Schema changes are a new file in `supabase/migrations` (never edit an applied one), with matching row types in
  `Core/Sources/LaxPocketCore/Cloud/CloudRows.swift`, checks in `supabase/tests/rls_test.sql`, and a note in
  `docs/supabase.md`.
- Migrations are pasted into the Supabase SQL Editor, and the live project can differ from what the earlier migrations
  create (a policy removed in the dashboard, say). So a migration must not depend on objects already being there:
  replace a policy with `drop policy if exists` + `create policy`, never `alter policy`; use `if not exists` and
  `create or replace`, so the file can be run again after a failed attempt. Test it against a database with an
  earlier object missing, not just a fresh one.
- The user wants migrations run for them. Apply one with the Supabase CLI's own sign-in (no database password):
  `supabase db query --linked --project-ref xoepfhvesnttrggakfbf --file supabase/migrations/<file>.sql`. First check
  read-only that the migrations it builds on are there (`to_regclass('public.<table>')`), apply in date order, then
  check the result. Don't use `supabase db push`: earlier migrations were pasted into the SQL Editor, so the remote
  migration history is empty and it would try to run them all again. If the CLI can't be used, put the file on the
  user's clipboard with `pbcopy < <file>` (checked with `pbpaste | cmp - <file>`), never ask them to copy it by hand:
  a hand-copied file once lost its closing `);` line.
- Who sees what is defined twice and must change together: `private.readable_sections` / `writable_sections` (family
  accounts migration) and `private.roster_sections` (coach rosters migration), and `Relationship` / `RosterKind` in
  `Core/Sources/LaxPocketCore/Access.swift` and `Coaching.swift`. A locked mental doc is readable only by the
  account in `locked_by` and the mental coaches that account trusts, never by relationship, because the owner
  controls who's linked. Mental sessions are in the mental section, so a team coach never sees them.
- Coaches read athletes live through `CloudSync.coachWorkspace`; never sync a coached athlete onto the coach's phone.
- What coaches write (`assignments`, `event_coach_notes`) lives in its own tables and reaches family phones read only,
  like `lockedDocs`; never give coaches write access to a table families sync, or a family's offline edit will
  overwrite the coach's (or the other way round). Only coaches assign tasks.
- The repo holds no personal data; test fixtures use made-up numbers.

## Keeping this file current

When something goes wrong that a rule here would have prevented, or the user states how they want things done, add
or update a line here in the same change.
