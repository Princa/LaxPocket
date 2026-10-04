import Foundation

/// How an account is related to an athlete: the athlete's own login, a parent, or a coach. Also what an account says
/// it is when it's set up. Matches `profile_members.relationships` and `accounts.kind` in the cloud.
public enum Relationship: String, Codable, CaseIterable, Identifiable, Sendable {
    case parent
    case athlete
    case coach
    case mentalCoach

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .parent: return "Parent"
        case .athlete: return "Athlete"
        case .coach: return "Coach"
        case .mentalCoach: return "Mental coach"
        }
    }

    /// Sections this relationship can see.
    public var readableSections: Set<ProfileSection> {
        switch self {
        case .parent, .athlete: return Set(ProfileSection.allCases)
        case .coach: return [.training, .events]
        case .mentalCoach: return [.training, .events, .mental]
        }
    }

    /// Sections this relationship can change, given an owner or editor role. Athletes see the budget but don't change it.
    public var writableSections: Set<ProfileSection> {
        switch self {
        case .parent: return Set(ProfileSection.allCases)
        case .athlete: return [.training, .events, .health, .mental]
        case .coach, .mentalCoach: return []
        }
    }
}

/// Parts of an athlete's data that are shared separately.
public enum ProfileSection: String, Codable, CaseIterable, Sendable {
    /// Programs, training sessions, combine results and wall ball.
    case training
    /// Games, tournaments, showcases and camps, with stats, reflections, goals, videos and checklists.
    case events
    /// Height and weight.
    case health
    /// Expenses, trips and budgets.
    case budget
    /// Mental-game documents.
    case mental
}

public enum MemberRole: String, Codable, Sendable {
    /// Made the athlete; can change everything, invite people and delete the athlete.
    case owner
    case editor
    case viewer
}

/// What the signed-in account can do with one athlete in the cloud. Mirrors `private.can_read` and `private.can_write`
/// in supabase/migrations/20261007000000_family_accounts.sql.
public struct ProfileAccess: Codable, Hashable, Sendable {
    public var role: MemberRole
    public var relationships: Set<Relationship>

    public init(role: MemberRole, relationships: Set<Relationship>) {
        self.role = role
        self.relationships = relationships
    }

    public func canRead(_ section: ProfileSection) -> Bool {
        role == .owner || relationships.contains { $0.readableSections.contains(section) }
    }

    public func canWrite(_ section: ProfileSection) -> Bool {
        switch role {
        case .owner: return true
        case .editor: return relationships.contains { $0.writableSections.contains(section) }
        case .viewer: return false
        }
    }

    /// Name, goal, season and theme.
    public var canEditProfile: Bool { role != .viewer }

    /// Only the athlete's own login locks or hides mental docs.
    public var canLockDocs: Bool { relationships.contains(.athlete) }

    /// Inviting and removing people.
    public var canManagePeople: Bool { role == .owner }

    /// "Parent", "Athlete · Owner", "Coach, Mental coach".
    public var summary: String {
        let names = Relationship.allCases.filter(relationships.contains).map(\.title).joined(separator: ", ")
        return role == .owner ? "\(names) · Owner" : names
    }
}

extension AppData {
    /// True when this phone can see a section of the athlete. Athletes that aren't in the cloud, or that this account
    /// owns, show everything.
    public func canRead(_ section: ProfileSection) -> Bool {
        access?.canRead(section) ?? true
    }

    /// True when changes to a section here will reach the cloud. Changes to a section this account can only read are
    /// replaced by the cloud's copy at the next sync.
    public func canWrite(_ section: ProfileSection) -> Bool {
        access?.canWrite(section) ?? true
    }
}
