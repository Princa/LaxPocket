import Foundation

// Maya's hockey profile for the demo: the same athlete as her lacrosse profile (`athleteID` is `DemoSeason.profileID`),
// with its own teams, season, budget, mental-game docs and home practice, since sports are kept apart. Names, places,
// links and numbers are invented.

extension DemoBuilder {
    mutating func buildHockey() -> AppData {
        let profile = AthleteProfile(firstName: "Maya", classYear: 2031, positions: "Centre", mentalCoachName: DemoTasks.mentalCoachName,
                                     weeklyGoalHours: 9, season: AthleteProfile.seasonLabel(start: season), bodyUnits: .imperial,
                                     sport: .hockey, athleteID: DemoSeason.profileID, shoots: .left, level: "U15 AA")
        var data = AppData(id: DemoSeason.hockeyProfileID, profile: profile, programs: hockeyPrograms, themeID: "michigan")
        data.sessions = hockeySessions()
        let events = hockeyEvents()
        data.events = events
        let trips = hockeyTrips(events: events)
        data.trips = trips
        data.expenses = hockeyExpenses(trips: trips)
        data.seasonBudgets = [SeasonBudget(season: season, amount: 9_000), SeasonBudget(season: season - 1, amount: 8_200)]
        data.programBudgets = [
            ProgramBudget(programID: "rep", season: season, amount: 4_500),
            ProgramBudget(programID: "skating", season: season, amount: 1_200, note: "Two 10-packs"),
            ProgramBudget(programID: "dryland", season: season, amount: 600),
            ProgramBudget(programID: "mental", season: season, amount: 800),
            ProgramBudget(programID: "showcases", season: season, amount: 1_400),
            ProgramBudget(programID: "rep", season: season - 1, amount: 4_100)
        ]
        data.docs = hockeyDocs()
        // The same girl, so the same growth chart.
        data.bodyMeasurements = bodyMeasurements()
        data.practiceDrills = [
            PracticeDrill(id: "demo-tarp-corners", name: "Tarp corners", detail: "Pick the four corners of the shooting tarp in order.",
                          kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 40)
        ]
        data.practiceSessions = practiceSessions()
        return data
    }

    var hockeyPrograms: [Program] {
        [
            Program(id: "rep", name: "Lakeshore Lynx U15 AA", detail: "Rep team · fall and winter", group: .teams, sessionCategory: .team,
                    monogram: "LL", firstSeason: season - 1, lastSeason: season + 1),
            Program(id: "skating", name: "Edge Lab", detail: "Power skating and skills, weekly", group: .skills, sessionCategory: .skills,
                    monogram: "EL"),
            Program(id: "dryland", name: "Lynx dryland", detail: "Off-ice strength & speed, 2× a week", group: .fitness, sessionCategory: .fitness,
                    monogram: "LD"),
            Program(id: "mental", name: DemoTasks.mentalCoachName, detail: "Mental performance coach", group: .mental, sessionCategory: .mental,
                    monogram: "CR"),
            Program(id: "showcases", name: "Showcase circuit", detail: "Girls' showcases and ID camps", group: .showcases,
                    sessionCategory: nil, monogram: "SC")
        ]
    }

    // MARK: - Training

    /// Ten weeks of a weekly routine, building toward this week, up to now. Games are events, not sessions.
    mutating func hockeySessions() -> [TrainingSession] {
        let iceTags = ["Skating", "Shooting", "Passing", "Battles", "Faceoffs"]
        var sessions: [TrainingSession] = []
        for offset in -69...0 {
            let date = day(offset)
            let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
            // Later weeks run a little longer, so the load ratio climbs.
            let build = offset > -14 ? 15 : 0
            var planned: [(String, SessionCategory, Int, Int, Int, [String], String)] = []
            switch weekday {
            case 2: planned.append(("dryland", .fitness, 45, 6, 17, ["Strength"], ""))
            case 3: planned.append(("rep", .team, 75 + build, 7, 18, [iceTags.randomElement(using: &rng)!, "Skating"], ""))
            case 4: planned.append(("skating", .skills, 60, 7, 16, ["Edges", "Skating"], ""))
            case 5: planned.append(("rep", .team, 75 + build, 8, 19, ["Battles", "Positioning"], ""))
            case 6:
                if offset > -7 || chance(0.6) {
                    planned.append(("mental", .mental, 45, 3, 17, ["Pre-game routine", "Visualisation"], "Walked through the first shift"))
                }
            case 7: planned.append(("dryland", .fitness, 45, 7, 9, ["Conditioning"], ""))
            default: planned.append(("rep", .team, 60, 7, 10, ["Shooting", "Stickhandling"], ""))
            }
            // A missed session now and then, but none this week, so Home shows a full week.
            for (programID, category, minutes, effort, hour, focus, notes) in planned where offset > -7 || chance(0.9) {
                let start = day(offset, hour: hour)
                guard start <= now else { continue }
                sessions.append(TrainingSession(date: start, programID: programID, category: category,
                                                minutes: jitter(minutes, by: 2) / 5 * 5, effort: min(10, max(1, jitter(effort, by: 1))),
                                                focus: Array(Set(focus)).sorted(),
                                                notes: notes.isEmpty && chance(0.12) ? "Good legs tonight" : notes))
            }
        }
        return sessions
    }

    // MARK: - Events

    /// Games take a score until hockey's stat sheets come (phase 3), so what she tracks goes in her focus goals.
    mutating func hockeyEvents() -> [SeasonEvent] {
        let team = "Lakeshore Lynx U15 AA"
        let video = { (title: String, n: Int) in
            VideoLink(title: title, url: URL(string: "https://example.com/laxpocket-demo/hockey-video-\(n)")!, durationText: "\(n + 2):\(12 + n * 7)")
        }
        // Days ago, opponent, rink, score, her rating, faceoffs won and taken, shots on net.
        let games: [(Int, String, String, Int, Int, Int, Int, Int, Int)] = [
            (-44, "Bayview Bears", "Bayview Arena", 3, 1, 7, 9, 15, 4),
            (-37, "Northshore Wolves", "Lakeshore Arena", 2, 4, 6, 6, 14, 2),
            (-30, "Riverside Rapids", "Riverside Arena", 5, 2, 9, 12, 16, 5),
            (-23, "Eastside Ice", "Eastside Sportsplex", 2, 2, 7, 8, 15, 3),
            (-9, "Central Comets", "Lakeshore Arena", 1, 3, 5, 5, 13, 1),
            (-5, "Highland Huskies", "Highland Rink", 4, 3, 8, 11, 17, 4)
        ]
        var events: [SeasonEvent] = []
        for (index, game) in games.enumerated() {
            let (offset, opponent, location, us, them, rating, won, taken, shots) = game
            let share = Double(won) / Double(taken)
            events.append(SeasonEvent(
                kind: .game, title: "vs \(opponent)", team: team, opponent: opponent, date: day(offset, hour: 19, minute: 15), location: location,
                ourScore: us, theirScore: them,
                focus: [
                    FocusGoal(text: "Win 60% of faceoffs", outcome: share >= 0.6 ? .hit : share >= 0.45 ? .partly : .missed,
                              note: "\(won) of \(taken) faceoffs"),
                    FocusGoal(text: "A shot on net every period", outcome: shots >= 3 ? .hit : shots >= 1 ? .partly : .missed,
                              note: "\(shots) shot\(shots == 1 ? "" : "s") on net"),
                    FocusGoal(text: "Back-check hard every shift", outcome: rating >= 7 ? .hit : .partly)
                ],
                reflection: Reflection(selfRating: rating,
                                       wentWell: us > them ? "Won the battles on the wall, quick puck up to the wingers" : "Kept skating, good effort on the back-check",
                                       workOn: index % 2 == 0 ? "Backhand in tight" : "Gap control coming back",
                                       coachFeedback: index % 3 == 0 ? "Great jump through the neutral zone. Keep your stick on the ice in front." : "",
                                       coachFeedbackDate: index % 3 == 0 ? day(offset + 2) : nil),
                videos: index % 2 == 0 ? [video("Shifts", index)] : []
            ))
        }
        // Played, waiting for a score.
        events.append(SeasonEvent(kind: .game, title: "vs Harbour Blades", team: team, opponent: "Harbour Blades",
                                  date: day(-2, hour: 17, minute: 45), location: "Harbour Ice Centre",
                                  focus: [FocusGoal(text: "Win 60% of faceoffs"), FocusGoal(text: "Two backhands on net")]))
        // Past tournament with results and a trip.
        events.append(SeasonEvent(kind: .tournament, title: "Lake Placid Fall Classic", team: team,
                                  date: day(-17, hour: 8), endDate: day(-15, hour: 16), location: "Lake Placid, NY",
                                  ourScore: 3, theirScore: 1,
                                  focus: [FocusGoal(text: "Win 60% of faceoffs", outcome: .hit, note: "38 of 59 over four games")],
                                  reflection: Reflection(selfRating: 8, wentWell: "Faceoffs all weekend", workOn: "Legs in the last game"),
                                  videos: [video("Final", 4)],
                                  checklist: [ChecklistItem(title: "Registration", done: true), ChecklistItem(title: "Hotel", done: true),
                                              ChecklistItem(title: "Passport", done: true), ChecklistItem(title: "Sharpen skates", done: true),
                                              ChecklistItem(title: "Team jacket", done: true)]))
        // Coming up.
        events.append(SeasonEvent(kind: .game, title: "vs Northshore Wolves", team: team, opponent: "Northshore Wolves",
                                  date: day(2, hour: 19, minute: 15), location: "Northshore Arena",
                                  focus: [FocusGoal(text: "Win 60% of faceoffs"), FocusGoal(text: "Two backhands on net")]))
        events.append(SeasonEvent(kind: .game, title: "vs Bayview Bears", team: team, opponent: "Bayview Bears",
                                  date: day(5, hour: 16), location: "Lakeshore Arena"))
        events.append(SeasonEvent(kind: .game, title: "vs Riverside Rapids", team: team, opponent: "Riverside Rapids",
                                  date: day(9, hour: 11, minute: 30), location: "Riverside Arena"))
        events.append(SeasonEvent(kind: .camp, title: "Edge Lab skills camp", team: "Edge Lab", date: day(19, hour: 9), endDate: day(20, hour: 15),
                                  location: "Lakeshore Arena",
                                  checklist: [ChecklistItem(title: "Medical form", done: true), ChecklistItem(title: "Camp fee paid", done: true),
                                              ChecklistItem(title: "Sharpen skates")]))
        events.append(SeasonEvent(kind: .showcase, title: "Great Lakes Girls Showcase", team: "Showcase circuit", date: day(33, hour: 8),
                                  endDate: day(34, hour: 17), location: "Rochester, NY",
                                  checklist: [ChecklistItem(title: "Registration", done: true), ChecklistItem(title: "Hotel", done: true),
                                              ChecklistItem(title: "Email college coaches"), ChecklistItem(title: "Update highlight video"),
                                              ChecklistItem(title: "Passport check")]))
        events.append(SeasonEvent(kind: .tournament, title: "Lakeshore Holiday Classic", team: team, date: day(70, hour: 8),
                                  endDate: day(72, hour: 18), dateIsTentative: true, location: "Barrie, ON",
                                  checklist: [ChecklistItem(title: "Registration"), ChecklistItem(title: "Book hotel")]))
        return events
    }

    // MARK: - Budget

    func hockeyTrips(events: [SeasonEvent]) -> [Trip] {
        var trips: [Trip] = []
        if let placid = events.first(where: { $0.title == "Lake Placid Fall Classic" }) {
            var trip = Trip(event: placid, programID: "rep")
            trip.departureDate = day(-18, hour: 14)
            trip.returnDate = day(-15, hour: 21)
            trip.travelMode = .drive
            trip.travelDetails = "Carpool with the Patels"
            trip.hotelName = "Lakeview Lodge"
            trip.hotelAddress = "300 Example Rd, Lake Placid, NY"
            trip.hotelConfirmation = "DEMO-5190"
            trip.hotelCheckIn = day(-18, hour: 16)
            trip.hotelCheckOut = day(-15, hour: 11)
            trip.budget = 1_300
            trips.append(trip)
        }
        if let showcase = events.first(where: { $0.title == "Great Lakes Girls Showcase" }) {
            var trip = Trip(event: showcase, programID: "showcases")
            trip.departureDate = day(32, hour: 15)
            trip.returnDate = day(34, hour: 21)
            trip.travelMode = .drive
            trip.travelDetails = "About three hours, Lewiston bridge"
            trip.hotelName = "Riverside Inn"
            trip.hotelAddress = "400 Sample Blvd, Rochester, NY"
            trip.hotelConfirmation = "DEMO-6604"
            trip.hotelCheckIn = day(32, hour: 18)
            trip.hotelCheckOut = day(34, hour: 11)
            trip.budget = 900
            trip.note = "Bring both sticks and spare laces"
            trips.append(trip)
        }
        return trips
    }

    func hockeyExpenses(trips: [Trip]) -> [Expense] {
        let rate = ExchangeRate.defaultUSDToCAD
        func usd(_ date: Date, _ title: String, _ category: ExpenseCategory, _ amount: Double, program: String? = nil, trip: UUID? = nil, note: String = "") -> Expense {
            Expense(date: date, title: title, category: category, amount: ExchangeRate.cad(amount, in: .usd, rate: rate), note: note,
                    programID: program, season: season, tripID: trip, currency: .usd, originalAmount: amount)
        }
        func cad(_ date: Date, _ title: String, _ category: ExpenseCategory, _ amount: Double, program: String? = nil, trip: UUID? = nil, note: String = "") -> Expense {
            Expense(date: date, title: title, category: category, amount: amount, note: note, programID: program, season: season, tripID: trip)
        }
        var expenses = [
            cad(seasonDay(month: 8, day: 20), "Lakeshore Lynx · season fee", .teamFees, 3_900, program: "rep"),
            cad(day(-45), "Edge Lab · 10-session pack", .coaching, 450, program: "skating"),
            cad(day(-11), "Edge Lab · 10-session pack", .coaching, 450, program: "skating", note: "Crossovers and tight turns"),
            cad(day(-50), "Lynx dryland · fall term", .fitness, 280, program: "dryland"),
            cad(day(-20), "Coach Rivera · session", .coaching, 120, program: "mental"),
            cad(day(-6), "Coach Rivera · session", .coaching, 120, program: "mental"),
            cad(day(-33), "New stick", .equipment, 289),
            cad(day(-21), "Skate sharpening card", .equipment, 60),
            cad(day(-12), "Ice rental · shooting hour", .facility, 85, program: "rep"),
            usd(day(-30), "Great Lakes Showcase · registration", .showcases, 295, program: "showcases")
        ]
        if let placid = trips.first(where: { $0.name == "Lake Placid Fall Classic" }) {
            let id = placid.id
            expenses += [
                usd(day(-40), "Fall Classic · team entry share", .tournamentFees, 225, program: "rep", trip: id),
                usd(day(-18), "Lakeview Lodge · 3 nights", .lodging, 465, program: "rep", trip: id),
                usd(day(-16), "Team dinner", .food, 70, program: "rep", trip: id),
                cad(day(-18), "Gas and bridge toll", .travel, 110, program: "rep", trip: id)
            ]
        }
        if let showcase = trips.first(where: { $0.name == "Great Lakes Girls Showcase" }) {
            expenses.append(usd(day(-4), "Riverside Inn · 2 nights (deposit)", .lodging, 150, program: "showcases", trip: showcase.id))
        }
        return expenses
    }

    // MARK: - Mental game, practice

    func hockeyDocs() -> [MentalDoc] {
        func doc(_ slug: String) -> URL { URL(string: "https://docs.google.com/document/d/laxpocket-demo-hockey-\(slug)/edit")! }
        let coach = DemoTasks.mentalCoachName
        return [
            MentalDoc(title: "Pre-game routine", url: doc("routine"), folder: .routines, status: .toReview, updatedAt: day(-1, hour: 20),
                      updatedBy: coach, note: "1 new comment"),
            MentalDoc(title: "Next-shift reset", url: doc("reset"), folder: .routines, status: .reviewed, updatedAt: day(-10, hour: 19),
                      updatedBy: "Maya"),
            MentalDoc(title: "Session notes · confidence with the puck", url: doc("notes-confidence"), folder: .sessionNotes, status: .new,
                      updatedAt: day(-4, hour: 18), updatedBy: coach),
            MentalDoc(title: "Hockey season goals", url: doc("goals"), folder: .goals, status: .reviewed, updatedAt: day(-38, hour: 21),
                      updatedBy: "Maya"),
            MentalDoc(title: "Game journal", url: doc("journal"), folder: .journal, status: .toReview, updatedAt: day(-5, hour: 22),
                      updatedBy: "Maya", note: "After Highland")
        ]
    }

    /// Most mornings over six weeks, every morning for the last one: about 1,000 shots a week with the backhand a little
    /// behind and accuracy creeping up, stickhandling most days, some passing, and a timed challenge each week.
    mutating func practiceSessions() -> [PracticeSession] {
        // Drill, shots, share on target, how often it's in the routine.
        let shooting: [(String, Int, Double, Double)] = [
            ("wrist-shot", 60, 0.68, 1), ("snap-shot", 30, 0.6, 1), (PracticeCatalog.backhandID, 18, 0.45, 1),
            ("one-timer", 25, 0.5, 0.5), ("catch-and-release", 20, 0.55, 0.4), ("toe-drag-shot", 20, 0.45, 0.3),
            ("demo-tarp-corners", 40, 0.4, 0.3)
        ]
        // Drill, minutes or reps, how often.
        let other: [(String, Int, Double)] = [
            ("wide-dribble", 3, 1), ("quick-hands", 3, 1), ("figure-eights", 3, 0.6), ("toe-drags", 2, 0.5), ("head-up", 2, 0.5),
            ("dangle-course", 5, 0.3), ("forehand-pass", 30, 0.4), ("backhand-pass", 20, 0.3)
        ]
        var sessions: [PracticeSession] = []
        for offset in -41...0 {
            guard offset >= -6 || chance(0.8) else { continue }
            let improving = Double(offset + 41) * 0.002
            var sets: [PracticeSet] = []
            var shots = 0
            for (drillID, amount, onTarget, often) in shooting where often >= 1 || chance(often) {
                let count = max(5, jitter(amount, by: 6) / 5 * 5)
                let rate = onTarget + improving + Double.random(in: -0.06...0.06, using: &rng)
                sets.append(PracticeSet(drillID: drillID, amount: count, onTarget: min(count, max(0, Int(Double(count) * rate)))))
                shots += count
            }
            var minutes = 0
            for (drillID, amount, often) in other where often >= 1 || chance(often) {
                let isMinutes = !drillID.hasSuffix("-pass")
                let count = isMinutes ? max(1, jitter(amount, by: 1)) : max(5, jitter(amount, by: 5) / 5 * 5)
                sets.append(PracticeSet(drillID: drillID, amount: count))
                minutes += isMinutes ? count : 2
            }
            sessions.append(PracticeSession(date: day(offset, hour: 6, minute: 45), sets: sets, minutes: minutes + shots / 8,
                                            notes: chance(0.1) ? "Garage tarp before school" : ""))
            // A timed challenge once a week.
            if offset % 7 == 0 {
                let week = (offset + 41) / 7
                sessions.append(PracticeSession(date: day(offset, hour: 7, minute: 20), sets: [
                    PracticeSet(drillID: "quick-hands", amount: 62 + week * 3),
                    PracticeSet(drillID: "wrist-shot", amount: 14 + week / 2, onTarget: 9 + week / 2)
                ], challengeSeconds: 30, notes: offset == 0 ? "New best on quick hands" : ""))
            }
        }
        return sessions.filter { $0.date <= now }
    }
}
