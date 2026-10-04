<p align="center"><img src="docs/app-icon.png" width="128" alt="LaxPocket app icon: a lacrosse head with a growth arrow in the pocket"></p>

# LaxPocket

An iPhone app for tracking a lacrosse athlete's season in one place: training volume, combine results against the national standards, games and reflections, the season budget, and documents shared with a mental coach.

Built with SwiftUI for iOS 17+.

## What's in it

| Tab / screen | What it does |
|---|---|
| **Athletes** | One profile per athlete, each with its own sessions, results, events, budget, docs, height and weight log and theme. Switch from the Home header or **Theme & settings → Athletes**. |
| **Athlete profile** | **Home → Edit profile** (also in the athlete menu and Theme & settings). Name, class year, positions and mental coach; every club and team the athlete plays for (club, school, box, provincial), with games and hours for each; and height and weight. **NDTP team** is optional (None by default): picking an age group adds NDTP as one of their teams and scores combine results against that group's standards. |
| **Home** | This week's hours split into Team / Skills / Fitness against a weekly goal, a load ratio, season totals, what's up next, and showcase prep. |
| **Training** | Weekly and season hours by category — team, skills, fitness and mental (Swift Charts), an acute : chronic workload gauge, and a session log. **Log session** captures program, duration, effort (RPE 1–10), focus tags and notes. Mental sessions (game plan, pre-game preparation, visualisation with the mental coach) have their own focus tags and count toward weekly hours but not the workload gauge, which tracks physical load. |
| **Wall ball** | **Training → Wall ball**. Log each day's reps by drill and hand: the 15-drill routine (overhand, quick sticks, one-handed, cross-hand, behind the back, catch and switch…) is built in, and you can add your own, rename, hide or change default reps. **Pick all** with one number for every drill and hand, or set each one; **Same as last time** repeats the previous day. The dashboard shows today, the week, the streak and best day, reps per day or week stacked by hand, right-vs-left balance (flagged when one hand drops under 40%), reps by drill, and the log. A **timed challenge** runs picked drills against the clock (30 s to 2 min per drill and hand, right & left or one hand), with a countdown, optional tap-to-count, and bests per drill and hand for each round length. |
| **Metrics** | Combine results scored against the **NDTP 2026 Fitness Standards** for the athlete's NDTP age group (or a group picked on the screen for an athlete not on an NDTP team) (Developing / Competitive / Elite) with the gap to the next tier, a comparison against the next age group, and a left-vs-right balance check. |
| **Events** | Season record and totals, upcoming games and showcases, past events waiting for a score, and results. **Add / edit event** covers the score, stat line, video links, pre-game goals (hit / partly / missed), the post-game reflection with coach feedback, and a prep checklist. Tournaments, showcases and camps open their own page with the prep checklist and a **Trip & costs** card: the trip's total, days, hotel and costs by category, with a link to the trip, or **Plan the trip** to start one from the event. Events with a trip show its cost in the list. |
| **Budget** | One season at a time (pick 2026/27, 2027/28…): spend against the season budget, by program and by category, and every expense. Each program (team, coach, camp…) gets its own budget per season, so a club team that runs three seasons has three budgets. Expenses say which program and season they're for; tap one to change it or add notes. Programs list the seasons they run. **Tournament trips** keep a trip's costs together — tournament fee, travel, hotel, food and other — with the dates, destination, how you got there, the hotel (address, confirmation number, check-in and check-out) and an optional trip budget. Each trip shows days and nights away, the hotel cost per night and food per day; the Budget screen adds up days in the US for the season and each calendar year. Pick an event from the Events tab to link the trip to it (one trip per event): the trip takes the event's name, dates and place, links back to the event, and moves with it when the event's dates change, keeping any travel days before or after. Any expense can be paid in **CAD or USD**: a US-dollar amount is converted to CAD at the athlete's exchange rate (built in at 1 USD = 1.38 CAD; set your own from the currency menu next to the season), and every budget and total adds up in CAD. The same menu shows the whole budget in US dollars instead. Expenses on a trip to the US start in USD. |
| **Programs** | Teams, coaches and facilities, with hours logged at each. Add, edit or remove them here. |
| **Health** | Height and weight over time, from **Home → Health** or the athlete profile. Latest height and weight, the growth rate (flagged at growth-spurt pace, about 0.6 cm a month), height and weight charts over 3 months to all time, and a log with the change since the last height. Shown in ft/in and lb or cm and kg, per athlete. |
| **Mental game** | Recent sessions with the mental performance coach and a shortcut to log one, plus Google Drive documents shared with the coach, a "to review" queue, folders, and link-a-doc. Docs open in Google Docs or Word for editing. |
| **Cloud sync** | Optional. Sign in to back up every athlete to Supabase and keep phones in sync; share an athlete with a parent's or coach's account. See [docs/supabase.md](docs/supabase.md). |
| **Theme & settings** | 11 colour themes (the original plus the final 2026 D1 women's top 10), each with a matching alternate app icon. Also the athletes list, the active athlete's profile, weekly goal, budget, and a blank-season reset. |

## Getting started

You need a Mac with **Xcode 16** and [Homebrew](https://brew.sh).

```bash
git clone https://github.com/Princa/LaxPocket.git
cd LaxPocket
scripts/setup-mac.sh
open LaxPocket.xcodeproj
```

Pick your iPhone or a simulator and press **Run**. On first launch the app asks you to create an athlete profile, then walks you through adding the programs they train with.

`scripts/setup-mac.sh` is a one-time step. It installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed, generates the Xcode project from `project.yml`, saves your signing team in `Config/Local.xcconfig` (not committed; it reads the team from your Apple Development certificate, or pass it: `scripts/setup-mac.sh ABCDE12345`), and turns on git hooks that regenerate the project after every pull, checkout or rebase. After that:

- **Pulling changes:** `git pull`, then build. The project updates itself and keeps your signing team; if Xcode asks, choose **Revert** to reload it.
- **Making changes here and pushing:** edit in Xcode or run Claude Code in this folder, then commit and push. After adding or removing files, run `scripts/xcodegen-if-needed.sh` (Claude Code does this itself; see `CLAUDE.md`).

## Project layout

```
project.yml               XcodeGen spec (the .xcodeproj is generated, not committed)
Config/                   signing: Signing.xcconfig includes your Local.xcconfig (team ID, not committed)
.githooks/                regenerate the Xcode project after pull / checkout / rebase (scripts/setup-mac.sh turns them on)
Core/                     LaxPocketCore Swift package: models and logic, no UI
  Sources/LaxPocketCore/
    Benchmarks.swift      NDTP tier cut-offs, tier + gap calculations
    Workload.swift        weekly totals, acute:chronic ratio, zones
    Season.swift          events, game stats, season record
    Budget.swift          expenses and budget summary
    Trips.swift           tournament trips, trip costs, days in the US
    Currency.swift        CAD / USD, exchange rate, conversion
    Health.swift          height and weight log, units, growth rate
    Wallball.swift        wall ball drills, reps by hand, streaks, trends, challenge bests
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
