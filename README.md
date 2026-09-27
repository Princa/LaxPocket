<p align="center"><img src="docs/app-icon.png" width="128" alt="LaxPocket app icon: a lacrosse head with a growth arrow in the pocket"></p>

# LaxPocket

An iPhone app for tracking a lacrosse athlete's season in one place: training volume, combine results against the national standards, games and reflections, the season budget, and documents shared with a mental coach.

Built with SwiftUI for iOS 17+.

## What's in it

| Tab / screen | What it does |
|---|---|
| **Home** | This week's hours split into Team / Skills / Fitness against a weekly goal, a load ratio, season totals, what's up next, and showcase prep. |
| **Training** | Weekly and season hours by category (Swift Charts), an acute : chronic workload gauge, and a session log. **Log session** captures program, duration, effort (RPE 1–10), focus tags and notes. |
| **Metrics** | Combine results scored against the **NDTP 2026 Fitness Standards** (Developing / Competitive / Elite) with the gap to the next tier, a comparison against the next age group, and a left-vs-right balance check. |
| **Events** | Season record and totals, upcoming games and showcases, and results. **Game detail** has the stat line, video links, pre-game goals (hit / partly / missed) and the post-game reflection with coach feedback. |
| **Budget** | Spend against the season budget, by category, plus recent expenses. |
| **Programs** | Teams, coaches and facilities, with hours logged at each. |
| **Mental game** | Google Drive documents shared with the mental performance coach, a "to review" queue, folders, and link-a-doc. Docs open in Google Docs or Word for editing. |
| **Theme & settings** | 11 colour themes (the original plus the final 2026 D1 women's top 10), each with a matching alternate app icon. Also the athlete profile, weekly goal, budget, and data reset. |

## Getting started

You need a Mac with **Xcode 16** and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/Princa/LaxPocket.git
cd LaxPocket
xcodegen generate
open LaxPocket.xcodeproj
```

Choose your team under **Signing & Capabilities**, pick your iPhone or a simulator, and press **Run**. The app opens with a sample season. Go to **Theme & settings → Start a blank season** to begin logging real data.

## Project layout

```
project.yml               XcodeGen spec (the .xcodeproj is generated, not committed)
Core/                     LaxPocketCore Swift package: models and logic, no UI
  Sources/LaxPocketCore/
    Benchmarks.swift      NDTP tier cut-offs, tier + gap calculations
    Workload.swift        weekly totals, acute:chronic ratio, zones
    Season.swift          events, game stats, season record
    Budget.swift          expenses and budget summary
    MentalDocs.swift      Drive document links, type detection
    Themes.swift          11 palettes + WCAG contrast maths
    SampleData.swift      the demo season
  Tests/                  XCTest suite (runs on macOS and Linux)
LaxPocket/                SwiftUI app
  App/                    app entry, store (JSON persistence), tabs
  Theme/  Components/     colours, logo mark, shared views
  Features/               one folder per screen
  Resources/Assets.xcassets  app icon + 10 alternate theme icons
```

The logic lives in `LaxPocketCore` so it can be unit-tested without a simulator:

```bash
cd Core && swift test
```

CI (GitHub Actions) runs the Core tests on Linux and macOS, and builds the app for the iOS Simulator on every push.

## Data and privacy

- Everything is stored in one JSON file in the app's Application Support folder, with iOS file protection turned on. There's no account, server or analytics.
- The repository holds **no personal data**. The sample season uses made-up numbers. The athlete's real results are entered in the app and stay on the phone.
- Mental-game documents stay in Google Drive. The app only stores the link, title and folder.

## Standards and themes

- Tier cut-offs come from the *NDTP 2026 Fitness Standards Guide v1.0 (July 2026)*, from Lacrosse Canada's Future Track Athlete Evaluation Framework. Women's testing in 2026 had no 20 m sprint.
- The themes are inspired by the colours of the programs in the final 2026 IWLCA Division I coaches poll. Shades are tuned so text passes WCAG AA contrast, which the test suite checks. No school logos or marks are used.

## Roadmap

- [ ] Google Drive picker (Drive API) instead of pasting share links
- [ ] iCloud sync between the athlete's and a parent's phone
- [ ] Combine re-test trend charts once there are several testing days
- [ ] Home-screen widget: this week's hours and the next event
- [ ] Season review export (PDF) for end-of-year meetings
- [ ] Dark mode

## License

[GPL-3.0](LICENSE).
