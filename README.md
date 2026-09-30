<p align="center"><img src="docs/app-icon.png" width="128" alt="LaxPocket app icon: a lacrosse head with a growth arrow in the pocket"></p>

# LaxPocket

An iPhone app for tracking a lacrosse athlete's season in one place: training volume, combine results against the national standards, games and reflections, the season budget, and documents shared with a mental coach.

Built with SwiftUI for iOS 17+.

## What's in it

| Tab / screen | What it does |
|---|---|
| **Athletes** | One profile per athlete, each with its own sessions, results, events, budget, docs, height and weight log and theme. Switch from the Home header or **Theme & settings → Athletes**. |
| **Athlete profile** | **Home → Edit profile** (also in the athlete menu and Theme & settings). Name, class year, positions, NDTP group and mental coach; every club and team the athlete plays for (club, school, box, provincial), with games and hours for each; and height and weight. |
| **Home** | This week's hours split into Team / Skills / Fitness against a weekly goal, a load ratio, season totals, what's up next, and showcase prep. |
| **Training** | Weekly and season hours by category (Swift Charts), an acute : chronic workload gauge, and a session log. **Log session** captures program, duration, effort (RPE 1–10), focus tags and notes. |
| **Metrics** | Combine results scored against the **NDTP 2026 Fitness Standards** (Developing / Competitive / Elite) with the gap to the next tier, a comparison against the next age group, and a left-vs-right balance check. |
| **Events** | Season record and totals, upcoming games and showcases, past events waiting for a score, and results. **Add / edit event** covers the score, stat line, video links, pre-game goals (hit / partly / missed), the post-game reflection with coach feedback, and a prep checklist. |
| **Budget** | Spend against the season budget, by category, plus recent expenses. |
| **Programs** | Teams, coaches and facilities, with hours logged at each. Add, edit or remove them here. |
| **Health** | Height and weight over time, from **Home → Health** or the athlete profile. Latest height and weight, the growth rate (flagged at growth-spurt pace, about 0.6 cm a month), height and weight charts over 3 months to all time, and a log with the change since the last height. Shown in ft/in and lb or cm and kg, per athlete. |
| **Mental game** | Google Drive documents shared with the mental performance coach, a "to review" queue, folders, and link-a-doc. Docs open in Google Docs or Word for editing. |
| **Cloud sync** | Optional. Sign in to back up every athlete to Supabase and keep phones in sync; share an athlete with a parent's or coach's account. See [docs/supabase.md](docs/supabase.md). |
| **Theme & settings** | 11 colour themes (the original plus the final 2026 D1 women's top 10), each with a matching alternate app icon. Also the athletes list, the active athlete's profile, weekly goal, budget, and a blank-season reset. |

## Getting started

You need a Mac with **Xcode 16** and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/Princa/LaxPocket.git
cd LaxPocket
xcodegen generate
open LaxPocket.xcodeproj
```

Choose your team under **Signing & Capabilities**, pick your iPhone or a simulator, and press **Run**. On first launch the app asks you to create an athlete profile, then walks you through adding the programs they train with.

## Project layout

```
project.yml               XcodeGen spec (the .xcodeproj is generated, not committed)
Core/                     LaxPocketCore Swift package: models and logic, no UI
  Sources/LaxPocketCore/
    Benchmarks.swift      NDTP tier cut-offs, tier + gap calculations
    Workload.swift        weekly totals, acute:chronic ratio, zones
    Season.swift          events, game stats, season record
    Budget.swift          expenses and budget summary
    Health.swift          height and weight log, units, growth rate
    MentalDocs.swift      Drive document links, type detection
    Themes.swift          11 palettes + WCAG contrast maths
    Profiles.swift        athlete profile list + one JSON file per athlete
    Cloud/                Supabase rows, three-way merge, REST client, sync
  Tests/                  XCTest suite (runs on macOS and Linux)
supabase/                 Supabase project: schema migration, CLI config, schema + sync tests
LaxPocket/                SwiftUI app
  App/                    app entry, store (per-athlete JSON files), tabs
  Theme/  Components/     colours, logo mark, shared views
  Features/               one folder per screen
  Resources/Assets.xcassets  app icon + 10 alternate theme icons
```

Cloud sync is off until you add your Supabase project's URL and key. [docs/supabase.md](docs/supabase.md) walks through creating the **LaxPocket** project, applying the schema and connecting the app.

The logic lives in `LaxPocketCore` so it can be unit-tested without a simulator:

```bash
cd Core && swift test
```

CI (GitHub Actions) runs the Core tests on Linux and macOS, builds the app for the iOS Simulator, and checks the Supabase schema, access rules and sync against a real PostgREST on every push.

## Data and privacy

- Each athlete's data is stored in its own JSON file in the app's Application Support folder (`LaxPocket/profiles/<id>.json`, with `profiles.json` listing them), with iOS file protection turned on. There are no analytics.
- Cloud sync is opt-in and goes only to your own Supabase project. Row-level security limits each account to the athletes it owns or that were shared with it. The sign-in session is kept in the iOS Keychain.
- The repository holds **no personal data** and the app ships with no sample data. Test fixtures use made-up numbers. The athlete's real results are entered in the app and stay on the phone.
- Upgrading from 0.1 moves the old `season.json` into a profile. The built-in sample season is dropped rather than imported.
- Mental-game documents stay in Google Drive. The app only stores the link, title and folder.

## Standards and themes

- Tier cut-offs come from the *NDTP 2026 Fitness Standards Guide v1.0 (July 2026)*, from Lacrosse Canada's Future Track Athlete Evaluation Framework. Women's testing in 2026 had no 20 m sprint.
- The themes are inspired by the colours of the programs in the final 2026 IWLCA Division I coaches poll. Shades are tuned so text passes WCAG AA contrast, which the test suite checks. No school logos or marks are used.

## Roadmap

- [ ] Google Drive picker (Drive API) instead of pasting share links
- [x] Sync between the athlete's and a parent's phone (Supabase)
- [ ] Sign in with Apple
- [ ] Combine re-test trend charts once there are several testing days
- [ ] Home-screen widget: this week's hours and the next event
- [ ] Season review export (PDF) for end-of-year meetings
- [ ] Dark mode

## License

[GPL-3.0](LICENSE).
