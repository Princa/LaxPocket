import Foundation

/// The sport an athlete profile is for. An athlete who plays several sports has one profile per sport, and nothing is
/// added up across them (see docs/multi-sport.md). Matches `profiles.sport` and `rosters.sport` in the cloud.
public enum Sport: String, Codable, CaseIterable, Identifiable, Sendable {
    case lacrosse
    case hockey

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lacrosse: return "Lacrosse"
        case .hockey: return "Hockey"
        }
    }

    /// SF Symbol for the sport.
    public var symbolName: String {
        switch self {
        case .lacrosse: return "figure.lacrosse"
        case .hockey: return "figure.hockey"
        }
    }

    public var positionsPrompt: String {
        switch self {
        case .lacrosse: return "Positions, e.g. Midfield / Attack"
        case .hockey: return "Position, e.g. Centre / Left wing"
        }
    }

    /// Placeholders for the first team and the ones after it.
    public var teamPrompts: (first: String, more: String) {
        switch self {
        case .lacrosse: return ("Club or team, e.g. Club 2031", "Another team, e.g. school or box")
        case .hockey: return ("Team, e.g. Jr. Kings U15 AA", "Another team, e.g. spring or school")
        }
    }

    /// The kinds of team an athlete plays for, for help text.
    public var teamKinds: String {
        switch self {
        case .lacrosse: return "club, school, box, provincial"
        case .hockey: return "rep, house, school, spring"
        }
    }

    /// An example pre-game goal.
    public var goalExample: String {
        switch self {
        case .lacrosse: return "Win 3+ draw controls"
        case .hockey: return "Win 60% of faceoffs"
        }
    }

    /// Daily wall ball, by hand.
    public var hasWallball: Bool { self == .lacrosse }

    /// Home practice counted in shots, minutes and reps (`Practice.swift`): hockey's shooting, stickhandling and passing.
    public var hasPractice: Bool { self == .hockey }

    /// What the home practice is called.
    public var practiceTitle: String {
        switch self {
        case .lacrosse: return "Wall ball"
        case .hockey: return "Shooting & stickhandling"
        }
    }

    /// Combine results scored against the NDTP standards. Hockey's NHL Combine testing comes later.
    public var hasNDTPTesting: Bool { self == .lacrosse }

    /// A stat line for each game. Hockey's skater and goalie stats come later; its games take a score.
    public var hasGameStats: Bool { self == .lacrosse }

    /// Focus tags for a team or skills session.
    public func focusOptions(playsGoal: Bool = false) -> [String] {
        switch self {
        case .lacrosse:
            return TrainingSession.focusOptions
        case .hockey:
            return playsGoal ? Sport.hockeyGoalieFocus : Sport.hockeyFocus
        }
    }

    static let hockeyFocus = [
        "Skating", "Edges", "Shooting", "Stickhandling", "Passing",
        "Battles", "Positioning", "Faceoffs", "Conditioning", "Strength"
    ]

    static let hockeyGoalieFocus = [
        "Crease movement", "Tracking", "Rebounds", "Butterfly", "Puck handling",
        "Skating", "Conditioning", "Strength"
    ]
}

/// Which way a hockey player shoots.
public enum Handedness: String, Codable, CaseIterable, Identifiable, Sendable {
    case left
    case right

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

extension AppData {
    /// Identifies the athlete across their sport profiles: the first profile's ID.
    public var athleteKey: UUID { profile.athleteID ?? id }

    /// A new profile for the same athlete in another sport. It copies only the name, class year, height and weight
    /// units and exchange rate; everything else starts empty, because sports are kept apart.
    public func addingSport(_ sport: Sport, themeID: String = ThemeCatalog.defaultID, now: Date = Date()) -> AppData {
        let p = profile
        let athlete = AthleteProfile(firstName: p.firstName, classYear: p.classYear, positions: "", season: AthleteProfile.seasonLabel(for: now),
                                     bodyUnits: p.bodyUnits, usdToCAD: p.usdToCAD, sport: sport, athleteID: athleteKey)
        return AppData.newProfile(athlete, themeID: themeID)
    }

    /// A theme for an athlete's next sport: the first one none of their other sports uses, so each sport looks different.
    public static func suggestedTheme(besides used: [String]) -> String {
        ThemeCatalog.all.first { !used.contains($0.id) }?.id ?? ThemeCatalog.defaultID
    }
}
