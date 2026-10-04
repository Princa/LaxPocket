# LaxPocket

iPhone app (SwiftUI, iOS 17) with its logic in the `LaxPocketCore` Swift package (`Core/`) and an optional Supabase
backend (`supabase/`). See README.md for what each screen does.

## Working on it

- The Xcode project is generated from `project.yml` by XcodeGen and isn't committed. After adding, removing or
  renaming files, or editing `project.yml`, run `scripts/xcodegen-if-needed.sh` so Xcode sees the change. Pulls,
  checkouts and rebases do this through `.githooks` once `scripts/setup-mac.sh` has been run.
- Signing comes from `Config/Local.xcconfig` (the developer's team ID, not committed) via `Config/Signing.xcconfig`.
  Never put a team ID in `project.yml` or commit `Local.xcconfig`.
- Logic and models go in `Core/Sources/LaxPocketCore` with tests in `Core/Tests`; keep views in `LaxPocket/Features`.
- Check before pushing:
  - `cd Core && swift test`
  - `supabase/tests/run-local.sh` when a migration or `supabase/tests/rls_test.sql` changes (needs a local Postgres)
  - On a Mac, build the app: `xcodebuild -project LaxPocket.xcodeproj -scheme LaxPocket -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- Schema changes are a new file in `supabase/migrations` (never edit an applied one), with matching row types in
  `Core/Sources/LaxPocketCore/Cloud/CloudRows.swift`, checks in `supabase/tests/rls_test.sql`, and a note in
  `docs/supabase.md`.
- The repo holds no personal data; test fixtures use made-up numbers.
