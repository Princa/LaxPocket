# SportsPocket: hockey alongside lacrosse

Design for making the app work for more than one sport, starting with hockey. Status: **design, with the review
decisions of 2026-10-06**. The rename, the new logo, phase 1 (sport profiles) and phase 2 (hockey practice) are built; phases 3 and 4
aren't yet.

## Decisions

1. **The app is called SportsPocket**, with logo C: a stitched pocket holding a ball drawn as the weekly-goal ring.
   Internal names stay LaxPocket (see [Rename](#rename)).
2. **A coach sees one sport.** A hockey coach sees hockey and nothing of the athlete's lacrosse, and the other way round.
3. **Hockey testing is scored against the NHL Scouting Combine** (see [Hockey testing](#hockey-testing)).
4. **Sports are completely separate.** An athlete who plays two or more sports has one **sport profile** per sport.
   Each has its own hours and weekly goal, load, practice, events, testing, budget, health, mental game and coaches.
   Switching sport switches to a completely different view. Nothing is ever added up across sports.
5. **The family is the same in every sport.** It's the same athlete, so the parents and the athlete's own login see
   all of the athlete's sports without being invited again. Only a new person goes through an invite.

## One profile per athlete per sport

Today each athlete is one profile: one `AppData` file on the phone and one `profiles` row in the cloud, with its own
members and rosters. That becomes a **sport profile**. It gains a `sport`, fixed when it's made, and an athlete key
that groups an athlete's sport profiles together in the switcher. Everything else stays per profile, so the sports are
separate by construction.

```
Maya                  family: parents and Maya's own login, the same in every sport
├── Maya · Lacrosse   sessions, wall ball, NDTP testing, games, budget, health, mental game, lacrosse coaches
└── Maya · Hockey     sessions, shooting & stickhandling, NHL Combine testing, games, budget, health, mental game, hockey coaches
Ben
└── Ben · Hockey
```

- **Adding a sport** ("Add hockey for Maya") makes a new sport profile with the same athlete key and copies only the
  name, class year, height and weight units, and exchange rate. After that the profiles' data has nothing in common.
  The family comes along (see [People](#people)).
- **Each sport profile has its own theme**, so hockey and lacrosse can look different. The second sport suggests a
  different theme from the first.
- **Existing athletes are lacrosse.** A file or cloud row without a sport reads as lacrosse, and the athlete key
  defaults to the profile's own ID, so nothing has to be converted.

### Switching

- The Home header's athlete menu lists athletes, each with their sports. An athlete with two sports also gets a sport
  switch beside the name. Switching opens the other sport profile with the existing `switchProfile`, and every tab
  rebuilds, as `RootView` already does with `.id(store.data.id)`.
- **Theme & settings → Athletes** groups sport profiles by athlete and has **Add a sport** per athlete. Removing a
  sport removes that sport profile only.
- The phone remembers the last sport shown, the same way it remembers the active athlete today.

```
┌─────────────────────────────────────┐
│ SPORTSPOCKET              ◉ Maya ▾ 🎨 ▦│
│ Tue Oct 6 · Week 10                 │
│ MAYA'S HOCKEY SEASON  [🏒 Hockey ⇄] │
├─────────────────────────────────────┤
│ This week            9.5 / 12 h     │
│ ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▁▁▁▁▁  Load 1.1   │
├─────────────────────────────────────┤
│ Up next                             │
│ Sat  vs Jr. Kings U15 AA            │
└─────────────────────────────────────┘
```

## What each sport changes

The tabs and screens are the same for every sport. These parts depend on the profile's sport:

| Screen | Lacrosse | Hockey |
|---|---|---|
| New profile, Athlete profile | Positions, NDTP team | Position, shoots left or right, plays goal, level (e.g. U15 AA) |
| Training | Wall ball card and screens | Shooting & stickhandling card and screens |
| Log session | Lacrosse focus tags | Skating, Edges, Shooting, Stickhandling, Passing, Battles, Positioning, Faceoffs, Conditioning, Strength (goalies: Crease movement, Tracking, Rebounds, Butterfly) |
| Metrics | NDTP tests with tiers | NHL Combine tests against the NHL top 25 and top 10 lines |
| Events | Lacrosse stat line, W–L–T | Skater or goalie stat line, W–L–T–OTL |
| Coaching | Wall ball and lagging-hand flag | Shots and shot-mix flag |

Home, Budget, Programs, Health, Mental game, People and Cloud sync work the same in every sport, each on its own
profile's data.

## Core model (`LaxPocketCore`)

```swift
public enum Sport: String, Codable, CaseIterable, Identifiable, Sendable {
    case lacrosse
    case hockey
    // title, symbolName ("figure.lacrosse", "figure.hockey"), practiceTitle, positionsPrompt,
    // focusOptions, combineMetrics, eventGoalExamples
}

public struct AthleteProfile {
    // …existing fields; positions and benchmarkGroup (NDTP, lacrosse only) stay…
    public var sport: Sport              // fixed once the profile is made; missing → .lacrosse
    public var athleteID: UUID?          // groups an athlete's sport profiles; nil → the profile's own ID
    public var shoots: Handedness?       // hockey
    public var playsGoal: Bool           // hockey: goalie stat sheet by default
    public var level: String             // hockey: "U15 AA"
}
```

- Everything that differs by sport in wording or catalogs hangs off `Sport`, so screens ask the sport instead of
  switching on it themselves.
- `ProfileSummary` gains `sport` and `athleteID` so the switcher can group without loading every profile.
- `AppData.addingSport(_:)` makes the new sport profile for the same athlete, copying only the fields listed above.
- New hockey data on `AppData`: `practiceDrills` and `practiceSessions` (phase 2), the weekly shot and stickhandling
  goals on the profile, and `SeasonEvent.hockeyStats` (phase 3).
  A lacrosse profile never has them; a hockey profile never has wall ball or an NDTP group.
- No schema version bump is needed: every new field has a default when it's missing.

## Hockey home practice

Built in phase 2 (`Practice.swift`, `LaxPocket/Features/Practice/`, `20261011000000_hockey_practice.sql`).

Wall ball counts reps by hand. Hockey practice counts **shots, minutes or reps**, with no hands, and shooting drills can
also count how many shots were on target. It's a general **practice** model that a later sport (basketball makes and
attempts, soccer touches) can reuse; wall ball stays as it is.

```swift
public enum PracticeKind: String { case shooting, stickhandling, passing, other }
public enum PracticeMeasure: String { case shots, minutes, reps }

public struct PracticeDrill {          // built-in from PracticeCatalog for the profile's sport, or the athlete's own
    var id: String; var name: String; var detail: String; var kind: PracticeKind
    var measure: PracticeMeasure; var tracksTarget: Bool; var defaultAmount: Int; var isHidden: Bool
}
public struct PracticeSet { var drillID: String; var amount: Int; var onTarget: Int? }
public struct PracticeSession {         // a day's practice, or a timed challenge
    var id: UUID; var date: Date; var sets: [PracticeSet]
    var minutes: Int?; var challengeSeconds: Int?; var notes: String
}
// On the hockey profile: weeklyShotGoal (1,000 to start) and weeklyStickhandlingGoal (60 minutes); 0 for no goal.
```

- `PracticeStats` gives totals by kind and drill, days and weeks for charts, the streak, the best shot day, accuracy,
  the backhand share, pace toward the weekly goals, and challenge bests. Wall ball and practice count streaks with the
  same `DailyStreak`.
- A drill's measure decides what it adds to: shots (and on target) toward the shot goal, minutes on stickhandling
  drills toward the stickhandling goal, reps for passing. Once something is logged with a drill, its measure is fixed.
- In a timed challenge the count is what was done in the time (touches, shots, passes). Shots count as shots; a
  stickhandling round adds its time on the clock to the minutes, not its touches.

### Built-in hockey drills

| Kind | Drills | Counts |
|---|---|---|
| Shooting | Wrist shot, Snap shot, Backhand, Slap shot, One-timer, Catch and release, Toe drag and shoot | Shots, optional on target |
| Stickhandling | Wide dribble, Quick hands, Figure eights, Toe drags, Top hand only, Head up, Dangle course | Minutes |
| Passing | Forehand passes, Backhand passes, Saucer passes | Reps |

As with wall ball, the athlete can rename, hide or change defaults and add their own drills.

### Screens (`LaxPocket/Features/Practice/`)

- **Practice card** on Training: shots today, the streak, and the week against both goals.
- **Dashboard**: the week against the shot and stickhandling goals with pace ("on pace for 1,150 by Sunday"); shots
  and stickhandling today, the streak and the most shots in a day; shots (on target solid, the rest faded) or
  stickhandling minutes per day or week; shooting, stickhandling and passing by drill, with accuracy and the backhand
  share; challenge bests; the log.
- **Log practice**: drills by kind, quick amounts that pick a kind's drills or set them all, **Same as last time**,
  and an optional on-target count per shooting drill.
- **Drills**: change, hide, reset or add drills, by kind.
- **Timed challenge**: touches, shots or passes in 30 s to 2 min per drill, with tap-to-count and bests.
- **Weekly goals**: shots and stickhandling minutes, set by the athlete.

Where lacrosse warns about a lagging hand, hockey warns about the **shot mix**: backhand under 15% of 50 or more
shots. Coaches see it as a "Backhand behind" flag, with the week's shots and stickhandling minutes.

**Coach tasks** for hockey rosters: **Shots** (e.g. 1,000 a week) and **Stickhandling minutes**, which tick themselves
off from the practice log, alongside training minutes and tick-off tasks. Wall ball tasks are only for lacrosse
rosters; the database checks a task's kind against the roster's sport.

## Hockey games

A hockey profile's events use `hockeyStats: HockeyGameStats?` instead of the lacrosse `stats`:

```swift
public struct HockeyGameStats {
    public var playedAs: HockeyRole        // .skater or .goalie, defaulted from the profile, changeable per game
    // skater
    public var goals, assists, shots, plusMinus, penaltyMinutes, faceoffWins, faceoffLosses, blockedShots, hits: Int
    // goalie
    public var shotsAgainst, saves, minutesPlayed: Int
    // points, faceoff %, save %, goals against, GAA and shutouts are computed
}
```

- Summary line: skater "1G · 2A · 3P · +1", goalie "24 SV · .923".
- A hockey game can say how it was decided (regulation, overtime, shootout), so the record reads W–L–T–OTL.
- Pre-game goal examples follow the sport ("Win 60% of faceoffs").

## Hockey testing

A **standard** is a published table that says, for each test, which results count as Developing, Competitive or
Elite. The two numbers that split the three tiers are its **cut-offs**. Lacrosse uses the NDTP guide: for U15
women's 10 m sprint, 2.00 s or faster is Competitive and under 1.92 s is Elite, so a 1.97 s run shows as
Competitive, 0.05 s from Elite.

Hockey uses the **NHL Scouting Combine**. The NHL doesn't publish tiers or averages: after each combine it publishes
the **top 25 results in each test** (the latest is the
[June 6, 2026 release](https://media.nhl.com/site/vasset/public/attachments/2026/06/19913/FitnessResults_060626___FINAL.pdf),
about 100 draft prospects). The cut-offs come from those lists, so no number is invented:

| Tier | Cut-off | Shown as |
|---|---|---|
| Elite | the 10th-best result at the combine | **NHL top 10** |
| Competitive | the 25th-best result | **NHL top 25** |
| Developing | anything short of the 25th | **Developing** |

For example, in the 2025 horizontal jump the 10th-best was 112.0 in and the 25th-best 107.3 in, so a 95.0 in jump
reads "Developing · 12.3 in to the NHL top 25 (107.3 in)".

The tests, as the NHL reports them:

| Test | Unit | Better | Needs |
|---|---|---|---|
| Horizontal jump | in | higher | a tape |
| Vertical jump, no-arm jump | in | higher | a force plate or jump mat |
| Left-hand grip, right-hand grip | lb | higher | a hand dynamometer |
| Pull-ups (consecutive) | reps | higher | a bar |
| Pro agility, left and right | s | lower | cones and a timer |
| Bench press at 50% of body weight, power | W/kg | higher | a bar-speed sensor |
| Wingate peak power, mean power | W/kg | higher | a lab bike |
| Wingate fatigue index | % | lower | a lab bike |
| VO2max | ml/kg/min | higher | a lab test |
| Wing span | in | (not scored) | a tape |

- A testing day records whichever tests the athlete did; most families will have horizontal jump, grip, pull-ups and
  pro agility.
- Grip is entered in lb for hockey, as the NHL reports it. Lacrosse's NDTP grip stays in newtons.
- The left-versus-right balance check works for grip and pro agility as it does in lacrosse. There's no "next age
  group" comparison: the combine is one group.
- `NHLCombineStandards` holds the 10th and 25th results per test with their source line, like `NDTPStandards`. The NHL
  publishes its tables as images, so they're typed in from the PDF and checked by tests. Updating each June is one
  table.
- **Men and boys first.** The combine is male draft prospects, so the NHL lines are for boys' and men's hockey; a
  standard for girls and women can come later.
- **Who's at the combine:** draft-eligible players, mostly 17 and 18, the best of their year. A younger player will
  read Developing on most tests for years; the screen leads with the gap and progress since the last testing day, and
  says who the lines come from.
- `CombineMetric` gains the sport each test belongs to, and hockey's metrics are new cases (`horizontalJump`,
  `pullUps`, `wingatePeakPower`, …).

## Cloud

One new migration per phase, each safe to run again and not depending on objects already being there, as `CLAUDE.md`
asks. Phase 1's `supabase/migrations/20261010000000_sport_profiles.sql`:

```sql
alter table public.profiles add column if not exists sport      text not null default 'lacrosse';
alter table public.profiles add column if not exists athlete_id uuid;   -- null: the profile's own id
alter table public.profiles add column if not exists shoots     text;   -- 'left' | 'right', hockey
alter table public.profiles add column if not exists plays_goal boolean not null default false;
alter table public.profiles add column if not exists level      text not null default '';
alter table public.rosters  add column if not exists sport      text not null default 'lacrosse';
```

- `sport` checks are **named** constraints, dropped if there and added again, so a later sport widens them the same
  way.
- A trigger keeps `profiles.sport` from changing after insert, like `keep_created_by`, so lacrosse data can never end
  up in a hockey profile.
- `join_roster` is recreated (`create or replace`) to refuse an athlete whose sport isn't the roster's: "This is a
  hockey team. Pick Maya's hockey profile." The app's **Join with a code** only offers sport profiles that match.
- `create_roster` takes the sport; `roster_athlete_profiles` gets `sport` appended (`create or replace view` can add
  columns at the end).
- `share_profile`'s "No LaxPocket account…" message is recreated to say SportsPocket.

A coach only ever reads the sport profile a parent put on their roster, and a roster holds one sport. So "a coach sees
one sport" needs no change to the access rules: `private.readable_sections` / `writable_sections`,
`private.roster_sections`, `Relationship` and `RosterKind` stay as they are.

### People

The family belongs to the athlete; coaches belong to a sport.

- **Adding a sport brings the family.** The new sport profile gets every parent and the athlete's own login from the
  athlete's other sport profile, with the same roles. Nobody is invited again. Coaches don't come along; they join
  through a roster for that sport.
- **A new person is invited once.** An invite for a parent or the athlete's login, made from any of the athlete's
  sports, gives them all of them, including sports added later.
- **Taking a family member off** takes them off every sport. Taking a coach off is per sport, as today.
- Only the owner adds a sport, since it decides who sees the new profile.

In the cloud: `public.add_family_to_sport(p_from, p_to)` copies the parent and athlete members of `p_from` onto `p_to`.
It works only for the owner of both, only when both have the same athlete key, and it never copies coach or mental
coach members. The app calls it right after the new sport profile's first upload. `accept_profile_invite` is
recreated so a parent or athlete invite adds the person to every profile with that athlete key. Mental coach trust
(`mental_coach_trust`) stays per sport profile.

Later phases add `practice_drills`, `practice_sessions`, `practice_sets` and the profile's two weekly goals (phase 2), and
`hockey_game_stats` and `season_events.decided_in` (phase 3). They're shaped like the wall ball and `game_stats`
tables, with `(id, profile_id)` foreign keys, and use the training and events sections. Phase 4 widens the
`combine_measurements.metric` check.

### Sync

- `ProfileRow` gains `sport`, `athlete_id`, `shoots`, `plays_goal` and `level`; `RosterRow` and
  `CoachAthleteProfileRow` gain `sport`. New row types for the practice tables and hockey stats are added to
  `ProfileSnapshot`, decoded with `decodeIfPresent` so existing sync records still load.
- `ProfileMerge`: a practice session merges as one unit with its sets, like wall ball; hockey stats travel inside
  `EventBundle`.
- `CloudSync.snapshot`, `push` and `coachWorkspace` read and write the new tables.
- **Older app versions** only write the columns they know, so they never change a profile's sport. Until a phone
  updates, it shows a hockey profile as if it were lacrosse. Everyone on the athlete should update.

## Rename

Done in this change: the name on the home screen (`CFBundleDisplayName` in `project.yml`), the header wordmark, the
account wording in Cloud sync, and the invite and roster messages people send.

Kept as LaxPocket on purpose:

- **Bundle ID `com.princa.laxpocket`.** A new one installs as a separate app, without the athletes saved on the phone or
  the sign-in.
- **URL scheme `laxpocket://`.** Supabase's confirmation emails link to it.
- **Xcode project, target, scheme, the `LaxPocketCore` package and the storage folder.** Renaming them would make Xcode
  reopen a different project and move the data on the phone, for nothing anyone sees.
- **The Supabase project and the GitHub repository.** Both can be renamed later in their dashboards if wanted.

### Logo

**Logo C, the goal ring** (built): a stitched pocket holding a ball drawn as the weekly-goal ring, three quarters
done. The pocket stands for the app's name, the ball for any sport, and the ring for the goal on Home. It's white
with the ring in the theme's icon accent, like the old icon.

`docs/app-icon.svg` is the source. `MarkPaths` in `LaxPocketMark.swift` draws the same shapes for the header and the
Theme screen preview, and the main icon and the 10 theme icons (1024 px, no transparency) were drawn from the same
shapes in each theme's primary and icon-accent colours.

## Phases

Each phase is one PR and leaves the app shippable. Anything stored on the phone has to sync in the same phase; if it
didn't, the next sync would replace it with the cloud's copy.

0. **Rename and logo.** Done.
1. **Sport profiles.** Done (`20261010000000_sport_profiles.sql`). `Sport`; sport, athlete key and hockey fields on the profile; **Add a sport** with the family
   brought along; grouped athletes and the sport switch; family invites and removals that cover every sport; hockey
   focus tags and profile fields; a hockey profile hides wall ball and NDTP, and its games take a score but no stat
   sheet yet; roster sport and matching on join; phase 1 migration. After this, a hockey athlete can use everything
   except hockey practice, stats and testing.
2. **Hockey practice.** Done (`20261011000000_hockey_practice.sql`). Practice model and catalog, dashboard, log, drills,
   timed challenge, weekly shot and stickhandling goals; the shared streak helper; coaches see hockey practice; shots
   and stickhandling coach tasks.
3. **Hockey games.** Skater and goalie stat sheets, W–L–T–OTL; hockey stats migration.
4. **Testing and finish.** NHL Combine tests and `NHLCombineStandards` from the 2026 release; README. The made-up demo
   hockey profile for Maya is done (`DemoHockey.swift`): her own teams, season, budget, mental-game docs and practice,
   with a hockey team roster and a hockey mental-game roster to preview coaching. Give it combine results with the
   standards.

### Tests per phase

- Core: a profile without a sport reads as lacrosse; `addingSport` copies only the listed fields; athletes group
  correctly in the index; practice stats (streak, pace, accuracy, shot mix); hockey stat maths (points, save %, GAA,
  record with OTL); row round-trips and merges for every new table.
- `supabase/tests/rls_test.sql`: a profile's sport can't change; a hockey roster refuses a lacrosse profile; a coach
  on Maya's hockey roster can't read her lacrosse profile; `add_family_to_sport` copies parents and the athlete but
  not coaches, only for the owner of both and only within one athlete; a parent invite accepted on lacrosse also
  gives hockey; the migration run twice, and against a database missing an earlier object.
- Core: tiers against the NHL top 10 and top 25 lines, for higher- and lower-is-better tests.
- App build for the simulator, and a look at a lacrosse-only, a hockey-only and a two-sport athlete.

## Later

- **Hockey season.** Seasons start in August for every sport for now. Hockey families often count spring tryouts and
  spring hockey toward the next season; when hockey's season is defined, the start can become per sport.
- **Girls' and women's hockey testing.** No tiers for them until there's a standard to score against.
