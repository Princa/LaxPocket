import Foundation

/// A made-up athlete with a full season around `now`, for demoing the app in the simulator. Debug builds load it from
/// **Theme & settings → Demo data** or the `-demo` launch argument; release builds never do. Names, places, links and
/// numbers are invented.
///
/// Maya plays lacrosse and hockey, so she has a profile for each (the hockey one is in DemoHockey.swift). The season is
/// built relative to `now`, so the Home screen always has this week's hours, a wall ball or practice streak, games
/// waiting for a score and events coming up. The same `now` always gives the same data.
public enum DemoSeason {
    /// The demo athlete's lacrosse profile ID, which her hockey profile shares as its athlete ID. Loading the demo again
    /// replaces her profiles, and cloud sync leaves them alone.
    public static let profileID = UUID(uuidString: "DE300000-0000-4000-8000-00000000DE30")!
    /// Her hockey profile.
    public static let hockeyProfileID = UUID(uuidString: "DE300000-0000-4000-8000-00000000DE31")!

    /// The sports she plays, in the order her profiles are listed.
    public static let sports: [Sport] = [.lacrosse, .hockey]

    public static func make(sport: Sport = .lacrosse, now: Date = Date(), calendar: Calendar = .laxWeek) -> AppData {
        make(sport: sport, now: now, calendar: calendar, salt: 0)
    }

    /// `salt` gives a different but still repeatable season, for the made-up teammates on a demo roster.
    static func make(sport: Sport, now: Date, calendar: Calendar, salt: UInt64) -> AppData {
        switch sport {
        case .lacrosse:
            var builder = DemoBuilder(now: now, calendar: calendar, salt: salt)
            return builder.build()
        case .hockey:
            // Its own seed, so her hockey weeks don't mirror her lacrosse ones.
            var builder = DemoBuilder(now: now, calendar: calendar, salt: salt &+ 100)
            return builder.buildHockey()
        }
    }
}

extension ProfileSummary {
    /// The demo athlete, in any sport added for them. It stays on this phone and never syncs.
    public var isDemo: Bool { athleteKey == DemoSeason.profileID }
}

extension AppData {
    /// See `ProfileSummary.isDemo`.
    public var isDemo: Bool { athleteKey == DemoSeason.profileID }
}

/// SplitMix64: a small seeded generator, so the demo is the same every time for the same day.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct DemoBuilder {
    let now: Date
    let calendar: Calendar
    let today: Date
    let season: Int
    var rng: SeededGenerator

    init(now: Date, calendar: Calendar, salt: UInt64 = 0) {
        self.now = now
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        season = AthleteProfile.seasonStart(for: now, calendar: calendar)
        rng = SeededGenerator(seed: UInt64(max(0, today.timeIntervalSince1970)) &+ salt &* 0x9E37_79B9)
    }

    // MARK: - Dates

    /// `offset` days from today at `hour`:`minute`.
    func day(_ offset: Int, hour: Int = 18, minute: Int = 0) -> Date {
        let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    /// A date in this season (seasons start in August), or now if that date hasn't come yet.
    func seasonDay(month: Int, day: Int) -> Date {
        let year = month >= 8 ? season : season + 1
        return min(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? today, now)
    }

    mutating func jitter(_ value: Int, by spread: Int) -> Int {
        value + Int.random(in: -spread...spread, using: &rng)
    }

    mutating func chance(_ p: Double) -> Bool {
        Double.random(in: 0..<1, using: &rng) < p
    }

    // MARK: - Season

    mutating func build() -> AppData {
        let profile = AthleteProfile(firstName: "Maya", classYear: 2031, positions: "Midfield, Draw",
                                     mentalCoachName: "Coach Rivera", weeklyGoalHours: 12, season: AthleteProfile.seasonLabel(start: season),
                                     bodyUnits: .imperial)
        var data = AppData(id: DemoSeason.profileID, profile: profile, programs: programs, themeID: "north-carolina")
        data.setNDTPGroup(.u15Women)
        data.sessions = sessions()
        data.combineResults = combineResults()
        let events = events()
        data.events = events
        let trips = trips(events: events)
        data.trips = trips
        data.expenses = expenses(trips: trips)
        data.seasonBudgets = [SeasonBudget(season: season, amount: 12_000), SeasonBudget(season: season - 1, amount: 9_500)]
        data.programBudgets = [
            ProgramBudget(programID: "club", season: season, amount: 2_600),
            ProgramBudget(programID: "school", season: season, amount: 300),
            ProgramBudget(programID: "box", season: season, amount: 700),
            ProgramBudget(programID: AppData.ndtpProgramID, season: season, amount: 1_500),
            ProgramBudget(programID: "skills", season: season, amount: 1_800, note: "Two 4-packs a term"),
            ProgramBudget(programID: "gym", season: season, amount: 1_100),
            ProgramBudget(programID: "mental", season: season, amount: 1_000),
            ProgramBudget(programID: "club", season: season - 1, amount: 2_400)
        ]
        data.docs = docs()
        data.bodyMeasurements = bodyMeasurements()
        data.wallballDrills = [
            WallballDrill(id: "demo-twister", name: "Twister", detail: "Spin out of the catch, throw on the turn.", defaultReps: 15)
        ]
        data.wallballSessions = wallballSessions()
        return data
    }

    var programs: [Program] {
        [
            Program(id: "club", name: "Lakeshore Storm U15", detail: "Club team · spring and fall", group: .teams, sessionCategory: .team,
                    monogram: "LS", firstSeason: season - 1, lastSeason: season + 1),
            Program(id: "school", name: "Westbrook High", detail: "School team · junior varsity", group: .teams, sessionCategory: .team,
                    monogram: "WH"),
            Program(id: "box", name: "Riverside Box", detail: "Box lacrosse · winter league", group: .teams, sessionCategory: .team,
                    monogram: "RB"),
            Program(id: "skills", name: "Stick Lab", detail: "Private shooting and stick skills", group: .skills, sessionCategory: .skills,
                    monogram: "SL"),
            Program(id: "gym", name: "Northside Performance", detail: "Strength & speed, 2× a week", group: .fitness, sessionCategory: .fitness,
                    monogram: "NP"),
            Program(id: "mental", name: "Coach Rivera", detail: "Mental performance coach", group: .mental, sessionCategory: .mental,
                    monogram: "CR"),
            Program(id: "showcases", name: "Showcase circuit", detail: "Recruiting showcases and camps", group: .showcases,
                    sessionCategory: nil, monogram: "SC"),
            Program(id: "combine", name: "NDTP testing", detail: "Combine testing days", group: .combine, sessionCategory: nil, monogram: "NT")
        ]
    }

    // MARK: - Training

    /// Ten weeks of a weekly routine, building toward this week, up to now.
    mutating func sessions() -> [TrainingSession] {
        let skillTags = ["Stick skills", "Shooting", "Dodging", "Draw controls"]
        let teamTags = ["Defence", "Ground balls", "Dodging", "Conditioning", "Draw controls"]
        var sessions: [TrainingSession] = []
        for offset in -69...0 {
            let date = day(offset)
            let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
            // Later weeks run a little longer, so the load ratio climbs.
            let build = offset > -14 ? 10 : 0
            var planned: [(String, SessionCategory, Int, Int, Int, [String], String)] = []
            switch weekday {
            case 2: planned.append(("gym", .fitness, 60, 7, 7, ["Strength"], ""))
            case 3: planned.append(("club", .team, 90 + build, 7, 19, [teamTags.randomElement(using: &rng)!, "Conditioning"], ""))
            case 4:
                planned.append(("skills", .skills, 60, 6, 17, [skillTags.randomElement(using: &rng)!, "Shooting"], ""))
                planned.append(("school", .team, 75, 6, 15, ["Ground balls"], ""))
            case 5: planned.append(("club", .team, 90 + build, 8, 19, ["Dodging", "Defence"], ""))
            case 6:
                if offset > -7 || chance(0.6) {
                    planned.append(("mental", .mental, 45, 3, 17, ["Game plan", "Visualisation"], "Walked through the draw routine"))
                }
            case 7:
                planned.append(("gym", .fitness, 60 + build, 8, 9, ["Strength", "Conditioning"], ""))
                planned.append(("skills", .skills, 45, 6, 11, ["Shooting"], ""))
            default: planned.append(("box", .team, 60, 7, 10, ["Stick skills"], ""))
            }
            // A missed session now and then, but none this week, so Home shows a full week.
            for (programID, category, minutes, effort, hour, focus, notes) in planned where offset > -7 || chance(0.9) {
                let start = day(offset, hour: hour)
                guard start <= now else { continue }
                sessions.append(TrainingSession(date: start, programID: programID, category: category,
                                                minutes: jitter(minutes, by: 2) / 5 * 5, effort: min(10, max(1, jitter(effort, by: 1))),
                                                focus: Array(Set(focus)).sorted(),
                                                notes: notes.isEmpty && chance(0.12) ? "Felt sharp, good energy" : notes))
            }
        }
        return sessions
    }

    func combineResults() -> [CombineResult] {
        [
            CombineResult(date: day(-130, hour: 9), event: "Spring baseline", measurements: [
                .init(metric: .gripLeft, value: 262), .init(metric: .gripRight, value: 284),
                .init(metric: .squatJump, value: 8.8), .init(metric: .countermovementJump, value: 9.9),
                .init(metric: .sprint10m, value: 2.052),
                .init(metric: .proAgilityLeft, value: 5.18), .init(metric: .proAgilityRight, value: 5.09)
            ], heightText: "5′2″", weightText: "101 lb"),
            CombineResult(date: day(-18, hour: 9), event: "NDTP fall testing", measurements: [
                .init(metric: .gripLeft, value: 279), .init(metric: .gripRight, value: 309),
                .init(metric: .squatJump, value: 9.7), .init(metric: .countermovementJump, value: 10.9),
                .init(metric: .sprint10m, value: 1.968),
                .init(metric: .proAgilityLeft, value: 5.06), .init(metric: .proAgilityRight, value: 4.94)
            ], heightText: "5′3½″", weightText: "107 lb")
        ]
    }

    // MARK: - Events

    mutating func events() -> [SeasonEvent] {
        let video = { (title: String, n: Int) in
            VideoLink(title: title, url: URL(string: "https://example.com/laxpocket-demo/video-\(n)")!, durationText: "\(n + 1):\(10 + n * 7)")
        }
        let games: [(Int, String, String, String, Int, Int, GameStats, Int)] = [
            (-45, "Lakeshore Storm U15", "Harbour Hawks", "Lakeshore Fields", 12, 8, GameStats(goals: 2, assists: 1, shots: 5, groundBalls: 4, drawControls: 6, causedTurnovers: 1), 7),
            (-38, "Westbrook High", "St. Anne's", "Westbrook HS turf", 9, 10, GameStats(goals: 1, assists: 0, shots: 4, groundBalls: 3, drawControls: 4, causedTurnovers: 2), 6),
            (-31, "Lakeshore Storm U15", "Valley Vipers", "Valley Park", 14, 6, GameStats(goals: 3, assists: 2, shots: 6, groundBalls: 5, drawControls: 8, causedTurnovers: 1), 9),
            (-17, "Westbrook High", "Central Tech", "Central Tech field", 11, 11, GameStats(goals: 1, assists: 2, shots: 3, groundBalls: 6, drawControls: 5, causedTurnovers: 3), 7),
            (-10, "Lakeshore Storm U15", "Eastside Eagles", "Lakeshore Fields", 8, 9, GameStats(goals: 0, assists: 1, shots: 4, groundBalls: 2, drawControls: 3, causedTurnovers: 0), 5),
            (-6, "Lakeshore Storm U15", "North Shore", "North Shore Dome", 13, 7, GameStats(goals: 2, assists: 3, shots: 5, groundBalls: 4, drawControls: 7, causedTurnovers: 2), 8)
        ]
        var events: [SeasonEvent] = []
        for (index, game) in games.enumerated() {
            let (offset, team, opponent, location, us, them, stats, rating) = game
            let won = us > them
            events.append(SeasonEvent(
                kind: .game, title: "vs \(opponent)", team: team, opponent: opponent, date: day(offset, hour: 13), location: location,
                ourScore: us, theirScore: them, stats: stats,
                focus: [
                    FocusGoal(text: "Win 5+ draws", outcome: stats.drawControls >= 5 ? .hit : stats.drawControls >= 3 ? .partly : .missed,
                              note: "\(stats.drawControls) draw controls"),
                    FocusGoal(text: "Shoot left-handed at least once", outcome: index % 2 == 0 ? .hit : .missed),
                    FocusGoal(text: "Talk on defence the whole game", outcome: rating >= 7 ? .hit : .partly)
                ],
                reflection: Reflection(selfRating: rating,
                                       wentWell: won ? "Pushed transition after the draw, quick ball movement" : "Kept fighting, won ground balls late",
                                       workOn: index % 2 == 0 ? "Off-hand shooting under pressure" : "Slide timing on defence",
                                       coachFeedback: index % 3 == 0 ? "Great energy on the circle. Keep the stick protected on the dodge." : "",
                                       coachFeedbackDate: index % 3 == 0 ? day(offset + 2) : nil),
                videos: index % 2 == 0 ? [video("Highlights", index)] : []
            ))
        }
        // Played, waiting for a score.
        events.append(SeasonEvent(kind: .game, title: "vs Bayview Blaze", team: "Westbrook High", opponent: "Bayview Blaze",
                                  date: day(-2, hour: 16), location: "Bayview Collegiate",
                                  focus: [FocusGoal(text: "Two clean ground balls a half")]))
        // Past tournament with results and a trip.
        events.append(SeasonEvent(kind: .tournament, title: "Niagara Fall Classic", team: "Lakeshore Storm U15",
                                  date: day(-25, hour: 8), endDate: day(-24, hour: 17), location: "Buffalo, NY",
                                  ourScore: 3, theirScore: 1,
                                  stats: GameStats(goals: 6, assists: 4, shots: 15, groundBalls: 11, drawControls: 17, causedTurnovers: 4),
                                  reflection: Reflection(selfRating: 8, wentWell: "Draw circle all weekend", workOn: "Fitness in game four"),
                                  videos: [video("Semi-final", 4)],
                                  checklist: [ChecklistItem(title: "Registration", done: true), ChecklistItem(title: "Hotel", done: true),
                                              ChecklistItem(title: "Passport", done: true), ChecklistItem(title: "Team jacket", done: true)]))
        // Coming up.
        events.append(SeasonEvent(kind: .game, title: "vs Harbour Hawks", team: "Lakeshore Storm U15", opponent: "Harbour Hawks",
                                  date: day(3, hour: 18, minute: 30), location: "Harbour Park",
                                  focus: [FocusGoal(text: "Win 5+ draws"), FocusGoal(text: "Two left-hand shots")]))
        events.append(SeasonEvent(kind: .game, title: "vs St. Anne's", team: "Westbrook High", opponent: "St. Anne's",
                                  date: day(6, hour: 16), location: "St. Anne's field"))
        events.append(SeasonEvent(kind: .game, title: "vs Valley Vipers", team: "Lakeshore Storm U15", opponent: "Valley Vipers",
                                  date: day(12, hour: 11), location: "Lakeshore Fields"))
        events.append(SeasonEvent(kind: .camp, title: "NDTP regional camp", team: "NDTP", date: day(20, hour: 9), endDate: day(21, hour: 16),
                                  location: "Oakville, ON",
                                  checklist: [ChecklistItem(title: "Medical form", done: true), ChecklistItem(title: "Camp fee paid", done: true),
                                              ChecklistItem(title: "Pack mouthguard and goggles")]))
        events.append(SeasonEvent(kind: .showcase, title: "Philly Elite Showcase", team: "Showcase circuit", date: day(37, hour: 8),
                                  endDate: day(38, hour: 17), location: "Philadelphia, PA",
                                  checklist: [ChecklistItem(title: "Registration", done: true), ChecklistItem(title: "Flights", done: true),
                                              ChecklistItem(title: "Hotel", done: true), ChecklistItem(title: "Email college coaches"),
                                              ChecklistItem(title: "Update highlight video"), ChecklistItem(title: "Passport check")]))
        events.append(SeasonEvent(kind: .tournament, title: "Winter Box Cup", team: "Riverside Box", date: day(68, hour: 9),
                                  endDate: day(69, hour: 18), dateIsTentative: true, location: "Ottawa, ON",
                                  checklist: [ChecklistItem(title: "Registration"), ChecklistItem(title: "Book hotel")]))
        return events
    }

    // MARK: - Budget

    func trips(events: [SeasonEvent]) -> [Trip] {
        var trips: [Trip] = []
        if let niagara = events.first(where: { $0.title == "Niagara Fall Classic" }) {
            var trip = Trip(event: niagara, programID: "club")
            trip.departureDate = day(-26, hour: 15)
            trip.returnDate = day(-24, hour: 21)
            trip.travelMode = .drive
            trip.travelDetails = "Carpool with the Chens"
            trip.hotelName = "Lakeside Suites"
            trip.hotelAddress = "100 Example Ave, Buffalo, NY"
            trip.hotelConfirmation = "DEMO-4821"
            trip.hotelCheckIn = day(-26, hour: 16)
            trip.hotelCheckOut = day(-24, hour: 11)
            trip.budget = 1_400
            trips.append(trip)
        }
        if let philly = events.first(where: { $0.title == "Philly Elite Showcase" }) {
            var trip = Trip(event: philly, programID: "showcases")
            trip.departureDate = day(36, hour: 10)
            trip.returnDate = day(38, hour: 22)
            trip.travelMode = .fly
            trip.travelDetails = "YYZ → PHL, morning flight"
            trip.hotelName = "Center City Inn"
            trip.hotelAddress = "200 Sample St, Philadelphia, PA"
            trip.hotelConfirmation = "DEMO-7730"
            trip.hotelCheckIn = day(36, hour: 15)
            trip.hotelCheckOut = day(38, hour: 11)
            trip.budget = 2_800
            trip.note = "Bring the highlight reel on a USB stick"
            trips.append(trip)
        }
        return trips
    }

    func expenses(trips: [Trip]) -> [Expense] {
        let rate = ExchangeRate.defaultUSDToCAD
        func usd(_ date: Date, _ title: String, _ category: ExpenseCategory, _ amount: Double, program: String? = nil, trip: UUID? = nil, note: String = "") -> Expense {
            Expense(date: date, title: title, category: category, amount: ExchangeRate.cad(amount, in: .usd, rate: rate), note: note,
                    programID: program, season: season, tripID: trip, currency: .usd, originalAmount: amount)
        }
        func cad(_ date: Date, _ title: String, _ category: ExpenseCategory, _ amount: Double, program: String? = nil, trip: UUID? = nil, note: String = "") -> Expense {
            Expense(date: date, title: title, category: category, amount: amount, note: note, programID: program, season: season, tripID: trip)
        }
        var expenses = [
            cad(seasonDay(month: 8, day: 15), "Lakeshore Storm · season fee", .teamFees, 1_850, program: "club"),
            cad(seasonDay(month: 9, day: 5), "Westbrook High · athletic fee", .teamFees, 250, program: "school"),
            cad(seasonDay(month: 8, day: 28), "NDTP · program fee", .teamFees, 950, program: AppData.ndtpProgramID),
            cad(day(-40), "Stick Lab · 4-pack", .coaching, 340, program: "skills"),
            cad(day(-12), "Stick Lab · 4-pack", .coaching, 340, program: "skills", note: "Focus on off-hand shooting"),
            cad(day(-35), "Northside · monthly", .fitness, 129, program: "gym"),
            cad(day(-5), "Northside · monthly", .fitness, 129, program: "gym"),
            cad(day(-28), "Coach Rivera · 2 sessions", .coaching, 240, program: "mental"),
            cad(day(-4), "Coach Rivera · session", .coaching, 120, program: "mental"),
            cad(day(-50), "New stick head + stringing", .equipment, 265),
            cad(day(-22), "Turf cleats", .equipment, 145),
            cad(day(-15), "Indoor field rental · team skills night", .facility, 60, program: "club"),
            usd(day(-48), "Elite Showcase · registration", .showcases, 395, program: "showcases")
        ]
        if let niagara = trips.first(where: { $0.name == "Niagara Fall Classic" }) {
            let id = niagara.id
            expenses += [
                usd(day(-40), "Fall Classic · team entry share", .tournamentFees, 175, program: "club", trip: id),
                usd(day(-26), "Lakeside Suites · 2 nights", .lodging, 338, program: "club", trip: id),
                usd(day(-25), "Team dinner", .food, 64, program: "club", trip: id),
                usd(day(-24), "Groceries and snacks", .food, 41, program: "club", trip: id),
                cad(day(-26), "Gas and bridge toll", .travel, 92, program: "club", trip: id)
            ]
        }
        if let philly = trips.first(where: { $0.name == "Philly Elite Showcase" }) {
            let id = philly.id
            expenses += [
                cad(day(-9), "Flights YYZ–PHL", .travel, 612, program: "showcases", trip: id),
                usd(day(-8), "Center City Inn · 2 nights (deposit)", .lodging, 180, program: "showcases", trip: id)
            ]
        }
        return expenses
    }

    // MARK: - Mental game, health, wall ball

    func docs() -> [MentalDoc] {
        func doc(_ slug: String) -> URL { URL(string: "https://docs.google.com/document/d/laxpocket-demo-\(slug)/edit")! }
        return [
            MentalDoc(title: "Game-day routine", url: doc("routine"), folder: .routines, status: .toReview, updatedAt: day(-1, hour: 20),
                      updatedBy: "Coach Rivera", note: "2 new comments"),
            MentalDoc(title: "Draw circle visualisation script", url: doc("visualisation"), folder: .routines, status: .reviewed,
                      updatedAt: day(-12, hour: 19), updatedBy: "Maya"),
            MentalDoc(title: "Session notes · reset after mistakes", url: doc("notes-reset"), folder: .sessionNotes, status: .new,
                      updatedAt: day(-3, hour: 18), updatedBy: "Coach Rivera"),
            MentalDoc(title: "Season goals", url: doc("goals"), folder: .goals, status: .reviewed, updatedAt: day(-40, hour: 21), updatedBy: "Maya"),
            MentalDoc(title: "Game journal", url: doc("journal"), folder: .journal, status: .toReview, updatedAt: day(-6, hour: 21),
                      updatedBy: "Maya", note: "After North Shore")
        ]
    }

    /// Monthly checks over a year and a half, with a growth spurt in the last few months.
    func bodyMeasurements() -> [BodyMeasurement] {
        let heights: [Double] = [151.0, 151.4, 151.9, 152.3, 152.6, 153.0, 153.5, 153.9, 154.2, 154.6, 155.0, 155.5, 156.1, 156.9, 157.8, 158.6, 159.3, 160.1]
        let weights: [Double] = [40.6, 41.0, 41.1, 41.6, 42.0, 42.2, 42.8, 43.1, 43.3, 43.9, 44.4, 44.6, 45.3, 46.0, 46.7, 47.4, 48.0, 48.6]
        return heights.indices.map { index in
            let monthsAgo = heights.count - 1 - index
            return BodyMeasurement(date: day(-monthsAgo * 30 - 2, hour: 8), heightCm: heights[index], weightKg: weights[index],
                            note: monthsAgo == 6 ? "Check-up with the doctor" : "")
        }
    }

    /// Most days over six weeks, every day for the last week, left hand a bit behind the right.
    mutating func wallballSessions() -> [WallballSession] {
        let routine: [(String, Int)] = [("overhand", 50), ("quick-sticks", 50), ("one-handed", 25), ("cross-hand", 25), ("sidearm", 25)]
        var sessions: [WallballSession] = []
        for offset in -41...0 {
            let date = day(offset, hour: 7, minute: 15)
            guard date <= now, offset >= -6 || chance(0.7) else { continue }
            var sets: [WallballSet] = []
            for (drillID, reps) in routine where drillID == "overhand" || drillID == "quick-sticks" || chance(0.6) {
                let right = jitter(reps, by: 5)
                sets.append(WallballSet(drillID: drillID, hand: .right, reps: right))
                sets.append(WallballSet(drillID: drillID, hand: .left, reps: max(5, right - Int.random(in: 5...15, using: &rng))))
            }
            sets.append(WallballSet(drillID: "switch-hands", hand: .both, reps: 30))
            if chance(0.3) { sets.append(WallballSet(drillID: "demo-twister", hand: .right, reps: 15)) }
            sessions.append(WallballSession(date: date, sets: sets, minutes: jitter(22, by: 4)))
            // A timed challenge once a week.
            if offset % 7 == 0 {
                let base = 30 + (offset + 41) / 7
                sessions.append(WallballSession(date: day(offset, hour: 7, minute: 45), sets: [
                    WallballSet(drillID: "quick-sticks", hand: .right, reps: base + 10),
                    WallballSet(drillID: "quick-sticks", hand: .left, reps: base + 2)
                ], challengeSeconds: 30, notes: offset == 0 ? "New best on the left" : ""))
            }
        }
        return sessions.filter { $0.date <= now }
    }
}

// MARK: - Previewing each role

extension DemoSeason {
    /// Maya as an account with the given relationship would see her once she's in the cloud, to preview each role's
    /// screens without signing in. A parent owns her and sees a placeholder for the journal she locked; her own login
    /// can lock docs (the journal is locked, her goals hidden) and only reads the budget. For a coach she's their own
    /// athlete (a parent who coaches); their rosters come from `coachRosters`.
    public static func make(sport: Sport = .lacrosse, now: Date = Date(), calendar: Calendar = .laxWeek, viewer: Relationship) -> AppData {
        var data = make(sport: sport, now: now, calendar: calendar)
        switch viewer {
        case .athlete:
            data.access = ProfileAccess(role: .editor, relationships: [.athlete])
            for index in data.docs.indices {
                switch data.docs[index].folder {
                case .journal: data.docs[index].visibility = .locked
                case .goals: data.docs[index].visibility = .hidden
                default: break
                }
            }
        case .parent, .coach, .mentalCoach:
            data.access = ProfileAccess(role: .owner, relationships: [.parent])
            if let journal = data.docs.first(where: { $0.folder == .journal }) {
                data.docs.removeAll { $0.id == journal.id }
                data.lockedDocs = [LockedMentalDoc(id: journal.id, folder: journal.folder, updatedAt: journal.updatedAt)]
            }
        }
        // Her coaches' tasks for this sport and a note on her last game, as the cloud would send them.
        data.assignments = (DemoTasks.make(kind: .team, sport: sport, now: now, calendar: calendar)
                            + DemoTasks.make(kind: .mental, sport: sport, now: now, calendar: calendar))
            .filter { $0.profileID == nil }
            .map { var task = $0; task.profileID = data.id; return task }
        if let game = Season.results(data.events).first {
            let coach = DemoTasks.teamCoach(for: sport)
            let note = sport == .hockey
                ? "Won your faceoffs and back-checked hard. Next: get pucks to the net from the half-wall."
                : "Won 4 of 6 draws and kept your stick up on D. Next: ride the ball carrier to the sideline."
            data.coachNotes = [CoachNote(eventID: game.id, coachID: coach.id, coachName: coach.name, note: note,
                                         updatedAt: game.date.addingTimeInterval(86_400))]
        }
        return data
    }

    /// Maya in each of her sports, lacrosse first, as `viewer` would see her (nil: just this phone).
    public static func profiles(now: Date = Date(), calendar: Calendar = .laxWeek, viewer: Relationship? = nil) -> [AppData] {
        sports.map { sport in
            viewer.map { make(sport: sport, now: now, calendar: calendar, viewer: $0) } ?? make(sport: sport, now: now, calendar: calendar)
        }
    }

    /// The made-up roster a coach of `kind` has for `sport`.
    static func roster(kind: RosterKind, sport: Sport) -> RosterRow {
        switch (kind, sport) {
        case (.team, .lacrosse):
            return RosterRow(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000000B1")!, kind: .team, name: "Lakeshore Storm U15", joinCode: "DEMQ4826")
        case (.mental, .lacrosse):
            return RosterRow(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000000B2")!, kind: .mental, name: "Mental-game clients", joinCode: "DEMR7359")
        case (.team, .hockey):
            return RosterRow(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000100B1")!, kind: .team, name: "Lakeshore Lynx U15 AA",
                             joinCode: "DEMH5713", sport: .hockey)
        case (.mental, .hockey):
            return RosterRow(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000100B2")!, kind: .mental, name: "Hockey mental-game clients",
                             joinCode: "DEMK2948", sport: .hockey)
        }
    }

    /// A made-up roster for one sport, read the way a coach reads one from the cloud: a team coach sees training (not
    /// mental sessions), home practice and events; a mental coach also sees mental sessions and shared docs, one doc an
    /// athlete trusted them with, and a placeholder for one they didn't. Each athlete shows something to notice: a load
    /// spike, a left hand (lacrosse) or backhand (hockey) falling behind, a quiet week.
    public static func coachRosters(kind: RosterKind, sport: Sport = .lacrosse, now: Date = Date(), calendar: Calendar = .laxWeek) -> [CoachRoster] {
        let since = CoachRoster.since(now: now, calendar: calendar)
        let eventsSince = calendar.date(byAdding: .day, value: -CoachRoster.recentEventDays, to: now) ?? now
        let everyone = DemoTeammate.roster(for: sport)
        let teammates = kind == .team ? everyone : Array(everyone.prefix(3))

        var rows = CoachWorkspace.Rows()
        for (index, teammate) in teammates.enumerated() {
            var data = make(sport: sport, now: now, calendar: calendar, salt: UInt64(index + 1))
            teammate.apply(to: &data, now: now, calendar: calendar)
            let snapshot = ProfileSnapshot(data)
            let p = data.profile
            rows.profiles.append(CoachAthleteProfileRow(id: data.id, firstName: p.firstName, classYear: p.classYear, positions: p.positions,
                                                        benchmarkGroup: p.benchmarkGroup, weeklyGoalHours: p.weeklyGoalHours, themeID: data.themeID,
                                                        sport: p.sport, shoots: p.shoots, playsGoal: p.playsGoal, level: p.level))
            rows.programs += snapshot.programs
            rows.sessions += snapshot.sessions.filter { $0.startedAt.date >= since && (kind == .mental || $0.category != .mental) }
            rows.wallballDrills += snapshot.wallballDrills
            let wallball = snapshot.wallballSessions.filter { $0.session.doneAt.date >= since }
            rows.wallballSessions += wallball.map(\.session)
            rows.wallballSets += wallball.flatMap(\.sets)
            rows.practiceDrills += snapshot.practiceDrills
            let practice = snapshot.practiceSessions.filter { $0.session.doneAt.date >= since }
            rows.practiceSessions += practice.map(\.session)
            rows.practiceSets += practice.flatMap(\.sets)
            let events = snapshot.events.filter { $0.event.startsAt.date >= eventsSince }
            rows.events += events.map(\.event)
            rows.stats += events.compactMap(\.stats)
            rows.reflections += events.compactMap(\.reflection)
            rows.focus += events.flatMap(\.focus)
            guard kind == .mental else { continue }
            for doc in snapshot.docs {
                if doc.folder != .journal {
                    rows.docs.append(doc)
                } else if index == 0 {
                    // The first athlete let her mental coach open the journal she locked.
                    var trusted = doc
                    trusted.visibility = .locked
                    rows.docs.append(trusted)
                } else if index == 1 {
                    // The second didn't: her mental coach sees that it's there.
                    rows.lockedDocs.append(LockedMentalDocRow(id: doc.id, profileID: doc.profileID, folder: doc.folder, docUpdatedAt: doc.docUpdatedAt))
                }
            }
        }

        let roster = roster(kind: kind, sport: sport)
        let places = rows.profiles.map { RosterAthleteRow(rosterID: roster.id, profileID: $0.id) }

        // Tasks, some already ticked off, and notes on the latest games.
        let tasks = DemoTasks.make(kind: kind, sport: sport, rosterID: roster.id, athletes: rows.profiles.map(\.id), now: now, calendar: calendar)
        rows.assignments = tasks.map(AssignmentRow.init)
        let coach = DemoTasks.teamCoach(for: sport)
        let notes = sport == .hockey
            ? ["Strong on the forecheck all game. Rest up this week.", "Good gaps on the rush. Get your backhand off quicker in tight."]
            : ["Huge effort on the ride. Rest up this week.", "Good slides. Work on your left-hand outlet."]
        for (index, profile) in rows.profiles.enumerated() {
            for task in tasks where task.schedule == .once && task.kind == .check && task.isFor(profile.id) && index % 2 == 0 {
                rows.completions.append(CompletionRow(assignmentID: task.id, profileID: profile.id, periodStart: task.startsOn))
            }
            if kind == .team, index < notes.count,
               let game = rows.events.filter({ $0.profileID == profile.id && $0.ourScore != nil }).max(by: { $0.startsAt < $1.startsAt }) {
                rows.coachNotes.append(AthleteCoachNoteRow(eventID: game.id, profileID: profile.id, coachID: coach.id, coachName: coach.name,
                                                           note: notes[index], updatedAt: Timestamp(game.startsAt.date.addingTimeInterval(86_400))))
            }
        }
        return CoachWorkspace.assemble(rosters: [roster], places: places, rows: rows)
    }
}

/// A made-up teammate of Maya's on a demo roster.
struct DemoTeammate {
    enum Pattern {
        case loadSpike
        /// Lacrosse: wall ball mostly on the right hand.
        case leftHandBehind
        /// Hockey: hardly any backhands.
        case backhandBehind
        case none
        case quiet
    }

    var id: UUID
    var name: String
    var classYear: Int
    var positions: String
    var themeID: String
    var pattern: Pattern
    var shoots: Handedness?
    var playsGoal = false

    static let lacrosse = [
        DemoTeammate(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000000A1")!, name: "Ava", classYear: 2031, positions: "Attack",
                     themeID: "northwestern", pattern: .loadSpike),
        DemoTeammate(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000000A2")!, name: "Lily", classYear: 2030, positions: "Defence",
                     themeID: "maryland", pattern: .leftHandBehind),
        DemoTeammate(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000000A3")!, name: "Zoe", classYear: 2032, positions: "Midfield",
                     themeID: "stanford", pattern: .none),
        DemoTeammate(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000000A4")!, name: "Nora", classYear: 2031, positions: "Goalie",
                     themeID: "navy", pattern: .quiet)
    ]

    /// Maya's hockey team: different teammates, since a coach only sees the one sport.
    static let hockey = [
        DemoTeammate(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000100A1")!, name: "Chloe", classYear: 2031, positions: "Right wing",
                     themeID: "colorado", pattern: .loadSpike, shoots: .right),
        DemoTeammate(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000100A2")!, name: "Emma", classYear: 2030, positions: "Defence",
                     themeID: "syracuse", pattern: .backhandBehind, shoots: .left),
        DemoTeammate(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000100A3")!, name: "Grace", classYear: 2032, positions: "Left wing",
                     themeID: "stony-brook", pattern: .none, shoots: .left),
        DemoTeammate(id: UUID(uuidString: "DE300000-0000-4000-8000-0000000100A4")!, name: "Hannah", classYear: 2031, positions: "Goalie",
                     themeID: "johns-hopkins", pattern: .quiet, shoots: .left, playsGoal: true)
    ]

    static func roster(for sport: Sport) -> [DemoTeammate] {
        sport == .hockey ? hockey : lacrosse
    }

    func apply(to data: inout AppData, now: Date, calendar: Calendar) {
        data.id = id
        data.profile.firstName = name
        data.profile.classYear = classYear
        data.profile.positions = positions
        data.profile.athleteID = nil
        if data.profile.sport == .hockey {
            data.profile.shoots = shoots
            data.profile.playsGoal = playsGoal
        }
        data.themeID = themeID
        for index in data.docs.indices where data.docs[index].updatedBy == "Maya" { data.docs[index].updatedBy = name }

        let weekStart = Workload.startOfWeek(for: now, calendar: calendar)
        if pattern != .leftHandBehind {
            // Maya's left hand trails a little; keep everyone else's this week even, so only Lily is flagged for it.
            for index in data.wallballSessions.indices where data.wallballSessions[index].date >= weekStart {
                let rightByDrill = Dictionary(data.wallballSessions[index].sets.filter { $0.hand == .right }.map { ($0.drillID, $0.reps) },
                                              uniquingKeysWith: +)
                for setIndex in data.wallballSessions[index].sets.indices where data.wallballSessions[index].sets[setIndex].hand == .left {
                    data.wallballSessions[index].sets[setIndex].reps = max(1, (rightByDrill[data.wallballSessions[index].sets[setIndex].drillID] ?? 30) - 2)
                }
            }
        }
        // Maya's backhand trails too: a quarter of everyone's shots this week (Emma's hardly any), so only Emma is flagged.
        for index in data.practiceSessions.indices where data.practiceSessions[index].date >= weekStart {
            let sets = data.practiceSessions[index].sets
            let others = sets.filter { $0.drillID != PracticeCatalog.backhandID && data.practiceDrill(id: $0.drillID)?.measure == .shots }
                .map(\.amount).reduce(0, +)
            for setIndex in sets.indices where sets[setIndex].drillID == PracticeCatalog.backhandID {
                let shots = max(1, pattern == .backhandBehind ? others / 30 : others / 3)
                data.practiceSessions[index].sets[setIndex].amount = shots
                data.practiceSessions[index].sets[setIndex].onTarget = sets[setIndex].onTarget.map { _ in shots / 2 }
            }
        }
        switch pattern {
        case .loadSpike:
            // Enough extra team sessions this week to take the load ratio to about 1.7.
            let weeks = Workload.weeks(endingAt: now, count: 5, sessions: data.sessions, calendar: calendar)
            let average = weeks.dropLast().map(\.hours.physical).reduce(0, +) / Double(max(weeks.count - 1, 1))
            let needed = max(0, average * 1.7 - (weeks.last?.hours.physical ?? 0))
            let count = Int((needed / 2).rounded(.up))
            let span = now.timeIntervalSince(weekStart)
            let team = data.programs.first { $0.group == .teams }?.id ?? "club"
            for k in 0..<count {
                data.sessions.append(TrainingSession(date: weekStart.addingTimeInterval(span * Double(k + 1) / Double(count + 1)),
                                                     programID: team, category: .team, minutes: 120, effort: 8, focus: ["Conditioning"],
                                                     notes: "Extra tournament prep"))
            }
        case .leftHandBehind:
            for index in data.wallballSessions.indices where data.wallballSessions[index].date >= weekStart {
                let rightByDrill = Dictionary(data.wallballSessions[index].sets.filter { $0.hand == .right }.map { ($0.drillID, $0.reps) },
                                              uniquingKeysWith: +)
                for setIndex in data.wallballSessions[index].sets.indices where data.wallballSessions[index].sets[setIndex].hand == .left {
                    let right = rightByDrill[data.wallballSessions[index].sets[setIndex].drillID] ?? 30
                    data.wallballSessions[index].sets[setIndex].reps = max(1, right / 6)
                }
            }
        case .quiet:
            // Nothing this week, and nothing for six days.
            let cutoff = min(weekStart, now.addingTimeInterval(-6 * 86_400))
            data.sessions.removeAll { $0.date > cutoff }
            data.wallballSessions.removeAll { $0.date > cutoff }
            data.practiceSessions.removeAll { $0.date > cutoff }
        case .backhandBehind, .none:
            break
        }
    }
}

/// Made-up coaches' tasks for the demo.
enum DemoTasks {
    /// The team coach of each sport's roster.
    static func teamCoach(for sport: Sport) -> (id: UUID, name: String) {
        switch sport {
        case .lacrosse: return (UUID(uuidString: "DE300000-0000-4000-8000-0000000000C1")!, "Coach Reyes")
        case .hockey: return (UUID(uuidString: "DE300000-0000-4000-8000-0000000100C1")!, "Coach Novak")
        }
    }

    /// Maya's mental coach, who keeps a roster for each sport.
    static let mentalCoachName = "Coach Rivera"

    /// A team coach's or mental coach's tasks for one sport, started a while ago and running now. `athletes` (in name
    /// order) lets one task go to a single athlete.
    static func make(kind: RosterKind, sport: Sport = .lacrosse, rosterID: UUID? = nil, athletes: [UUID] = [], now: Date, calendar: Calendar) -> [Assignment] {
        func day(_ offset: Int) -> DayKey { DayKey(calendar.date(byAdding: .day, value: offset, to: now) ?? now, calendar: calendar) }
        func id(_ n: Int) -> UUID {
            UUID(uuidString: "DE300000-0000-4000-8000-0000000\(sport == .hockey ? 1 : 0)00\(kind == .team ? "D" : "E")\(n)")!
        }
        let row = DemoSeason.roster(kind: kind, sport: sport)
        let roster = rosterID ?? row.id
        let coach = kind == .team ? teamCoach(for: sport).name : mentalCoachName
        func task(_ n: Int, profileID: UUID? = nil, kind taskKind: AssignmentKind, title: String, notes: String = "", schedule: AssignmentSchedule,
                  startsOn: Int, dueOn: Int? = nil, reps: Int? = nil, minutes: Int? = nil, category: SessionCategory? = nil) -> Assignment {
            Assignment(id: id(n), rosterID: roster, profileID: profileID, rosterName: row.name, coachName: coach, kind: taskKind, title: title,
                       notes: notes, schedule: schedule, startsOn: day(startsOn), dueOn: dueOn.map(day), targetReps: reps, targetMinutes: minutes,
                       category: category)
        }
        switch (kind, sport) {
        case (.team, .lacrosse):
            var tasks = [
                task(1, kind: .wallball, title: "Wall ball, left hand first", notes: "Start every set on your left.", schedule: .daily,
                     startsOn: -10, reps: 200),
                task(2, kind: .training, title: "Stick skills", schedule: .weekly, startsOn: -20, minutes: 180, category: .skills),
                task(3, kind: .check, title: "Watch the North Shore film", notes: "Note two rides you'd do differently.", schedule: .once,
                     startsOn: -2, dueOn: 2)
            ]
            if athletes.count > 2 {
                tasks.append(task(4, profileID: athletes[2], kind: .check, title: "Check in with me about your week", schedule: .once,
                                  startsOn: -1, dueOn: 1))
            }
            return tasks
        case (.team, .hockey):
            var tasks = [
                task(1, kind: .shots, title: "1,000 shots", notes: "At least one set of backhands every day.", schedule: .weekly,
                     startsOn: -20, reps: 1_000),
                task(2, kind: .stickhandling, title: "Hands every day", notes: "Head up for the last two minutes.", schedule: .daily,
                     startsOn: -10, minutes: 10),
                task(3, kind: .training, title: "Power skating", schedule: .weekly, startsOn: -20, minutes: 60, category: .skills),
                task(4, kind: .check, title: "Watch the Highland film", notes: "Note two shifts where you'd change your gap.", schedule: .once,
                     startsOn: -2, dueOn: 2)
            ]
            if athletes.count > 2 {
                tasks.append(task(5, profileID: athletes[2], kind: .check, title: "Check in with me about your week", schedule: .once,
                                  startsOn: -1, dueOn: 1))
            }
            return tasks
        case (.mental, .lacrosse):
            return [
                task(1, kind: .training, title: "Visualisation", notes: "Walk through the draw routine before bed.", schedule: .weekly,
                     startsOn: -14, minutes: 45, category: .mental),
                task(2, kind: .check, title: "Three lines in your game journal", schedule: .once, startsOn: -3, dueOn: 3)
            ]
        case (.mental, .hockey):
            return [
                task(1, kind: .training, title: "Visualisation", notes: "Picture your first shift and your first faceoff before bed.",
                     schedule: .weekly, startsOn: -14, minutes: 45, category: .mental),
                task(2, kind: .check, title: "Write your next-shift reset", notes: "One line for after a bad shift, one for after a good one.",
                     schedule: .once, startsOn: -3, dueOn: 3)
            ]
        }
    }
}
