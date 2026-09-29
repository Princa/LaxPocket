import Foundation

/// The three buckets every training session is counted in.
public enum SessionCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case team
    case skills
    case fitness

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .team: return "Team"
        case .skills: return "Skills"
        case .fitness: return "Fitness"
        }
    }
}

/// How a program is grouped on the Programs screen.
public enum ProgramGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case teams
    case skills
    case fitness
    case showcases
    case mental
    case combine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .teams: return "Teams & leagues"
        case .skills: return "Specialised skills"
        case .fitness: return "Strength & fitness"
        case .showcases: return "Showcases & camps"
        case .mental: return "Mental performance"
        case .combine: return "Combine testing"
        }
    }
}

/// A team, coach, facility or event the athlete trains with.
public struct Program: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var group: ProgramGroup
    /// The category sessions with this program count toward, if it is a training program.
    public var sessionCategory: SessionCategory?
    /// Two or three letters shown in the program's badge.
    public var monogram: String

    public init(id: String, name: String, detail: String, group: ProgramGroup, sessionCategory: SessionCategory?, monogram: String) {
        self.id = id
        self.name = name
        self.detail = detail
        self.group = group
        self.sessionCategory = sessionCategory
        self.monogram = monogram
    }

    /// A club or team the athlete plays for; its sessions count as team hours.
    public static func club(name: String, detail: String = "") -> Program {
        Program(id: newID(), name: name, detail: detail, group: .teams, sessionCategory: .team, monogram: suggestedMonogram(for: name))
    }

    /// A fresh ID for a program added in the app.
    public static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Badge letters from a name: the first letter of up to three words, plus a trailing number's last two digits,
    /// e.g. "Team Ontario U15" → "TOU", "Rockstar 2031" → "R31", "DodgeCity" → "DC", "OAA" → "OAA".
    public static func suggestedMonogram(for name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let named = words.filter { $0.first?.isLetter == true }
        var letters: String
        if named.count == 1, let word = named.first {
            let capitals = word.filter(\.isUppercase)
            letters = word.count <= 3 && word == word.uppercased() ? word : (capitals.count >= 2 ? String(capitals) : String(word.prefix(1)).uppercased())
        } else {
            letters = named.prefix(3).compactMap(\.first).map { String($0).uppercased() }.joined()
        }
        if let number = words.last, number.allSatisfy(\.isNumber), letters.count < 3 {
            letters += String(number.suffix(2))
        }
        return letters.isEmpty ? "?" : String(letters.prefix(3))
    }

    /// The session category a program in this group usually counts toward.
    public static func defaultCategory(for group: ProgramGroup) -> SessionCategory? {
        switch group {
        case .teams: return .team
        case .skills: return .skills
        case .fitness: return .fitness
        case .showcases, .mental, .combine: return nil
        }
    }
}

/// One logged practice, lesson or workout.
public struct TrainingSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var programID: String
    public var category: SessionCategory
    public var minutes: Int
    /// Session RPE, 1 (very easy) to 10 (max effort).
    public var effort: Int
    public var focus: [String]
    public var notes: String

    public init(id: UUID = UUID(), date: Date, programID: String, category: SessionCategory, minutes: Int, effort: Int, focus: [String] = [], notes: String = "") {
        self.id = id
        self.date = date
        self.programID = programID
        self.category = category
        self.minutes = minutes
        self.effort = effort
        self.focus = focus
        self.notes = notes
    }

    public var hours: Double { Double(minutes) / 60 }

    /// Session-RPE training load: minutes × effort.
    public var load: Int { minutes * effort }

    public static func effortLabel(_ effort: Int) -> String {
        switch effort {
        case ...2: return "Very easy"
        case 3...4: return "Easy"
        case 5...6: return "Moderate"
        case 7...8: return "Hard"
        default: return "Max effort"
        }
    }

    public static let focusOptions = [
        "Stick skills", "Shooting", "Dodging", "Draw controls",
        "Defence", "Ground balls", "Conditioning", "Strength"
    ]
}

public extension Calendar {
    /// Monday-start weeks, which is how the season is planned.
    static var laxWeek: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = TimeZone.current
        return calendar
    }
}
