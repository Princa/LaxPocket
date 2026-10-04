# LaxPocket

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
- Check before pushing:
  - `cd Core && swift test`
  - `supabase/tests/run-local.sh` when a migration or `supabase/tests/rls_test.sql` changes (needs a local Postgres)
  - On a Mac, build the app: `xcodebuild -project LaxPocket.xcodeproj -scheme LaxPocket -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- Schema changes are a new file in `supabase/migrations` (never edit an applied one), with matching row types in
  `Core/Sources/LaxPocketCore/Cloud/CloudRows.swift`, checks in `supabase/tests/rls_test.sql`, and a note in
  `docs/supabase.md`.
- Migrations are pasted into the Supabase SQL Editor, and the live project can differ from what the earlier migrations
  create (a policy removed in the dashboard, say). So a migration must not depend on objects already being there:
  replace a policy with `drop policy if exists` + `create policy`, never `alter policy`; use `if not exists` and
  `create or replace`, so the file can be run again after a failed attempt. Test it against a database with an
  earlier object missing, not just a fresh one.
- When the user needs to apply a migration, put it on their clipboard with `pbcopy < supabase/migrations/<file>.sql`
  (and check it with `pbpaste | cmp - <file>`) instead of asking them to copy it by hand: a hand-copied file once lost
  its closing `);` line.
- Who sees what is defined twice and must change together: `private.readable_sections` / `writable_sections` (family
  accounts migration) and `private.roster_sections` (coach rosters migration), and `Relationship` / `RosterKind` in
  `Core/Sources/LaxPocketCore/Access.swift` and `Coaching.swift`. A locked mental doc is readable only by the
  account in `locked_by` and the mental coaches that account trusts, never by relationship, because the owner
  controls who's linked. Mental sessions are in the mental section, so a team coach never sees them.
- Coaches read athletes live through `CloudSync.coachWorkspace`; never sync a coached athlete onto the coach's phone.
- The repo holds no personal data; test fixtures use made-up numbers.

## Keeping this file current

When something goes wrong that a rule here would have prevented, or the user states how they want things done, add
or update a line here in the same change.
