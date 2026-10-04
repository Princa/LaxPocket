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
- The repo holds no personal data; test fixtures use made-up numbers.
