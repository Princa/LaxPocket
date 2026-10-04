import Foundation

public enum DocFolder: String, Codable, CaseIterable, Identifiable, Sendable {
    case routines
    case sessionNotes
    case journal
    case goals

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .routines: return "Routines"
        case .sessionNotes: return "Session notes"
        case .journal: return "Journal"
        case .goals: return "Goals"
        }
    }
}

public enum DocStatus: String, Codable, CaseIterable, Sendable {
    case new
    case toReview
    case reviewed

    public var title: String {
        switch self {
        case .new: return "New"
        case .toReview: return "To review"
        case .reviewed: return "Reviewed"
        }
    }
}

public enum DocKind: String, Codable, Sendable {
    case word
    case googleDoc
    case pdf
    case link

    public var badge: String {
        switch self {
        case .word: return "DOCX"
        case .googleDoc: return "GDOC"
        case .pdf: return "PDF"
        case .link: return "LINK"
        }
    }

    /// Best guess at the file type from a Google Drive / Docs share link.
    ///
    /// Word files opened from Drive use `docs.google.com/document/...` with `rtpof=true`,
    /// native Google Docs use the same path without it.
    public static func infer(from url: URL) -> DocKind {
        let text = url.absoluteString.lowercased()
        if text.hasSuffix(".docx") || text.hasSuffix(".doc") || text.contains("rtpof=true") { return .word }
        if text.hasSuffix(".pdf") { return .pdf }
        if text.contains("docs.google.com/document") { return .googleDoc }
        return .link
    }
}

/// Who else on the athlete sees a mental doc. Only the athlete's own login can lock or hide one.
public enum DocVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Everyone who sees the athlete's mental game.
    case shared
    /// Others see that it's there, its folder and when it changed, but not its title, link or note.
    case locked
    /// Only the athlete.
    case hidden

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .shared: return "Shared"
        case .locked: return "Locked"
        case .hidden: return "Hidden"
        }
    }

    public var detail: String {
        switch self {
        case .shared: return "Your parents can open it."
        case .locked: return "Your parents see there's a document, not what's in it. A mental coach you allow in People can open it."
        case .hidden: return "Only you see it."
        }
    }
}

/// A document shared with the mental performance coach, stored in Google Drive and opened by link.
public struct MentalDoc: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var folder: DocFolder
    public var kind: DocKind
    public var status: DocStatus
    public var updatedAt: Date
    public var updatedBy: String
    public var note: String
    public var visibility: DocVisibility

    public init(id: UUID = UUID(), title: String, url: URL, folder: DocFolder, kind: DocKind? = nil, status: DocStatus = .new, updatedAt: Date, updatedBy: String = "", note: String = "",
                visibility: DocVisibility = .shared) {
        self.id = id
        self.title = title
        self.url = url
        self.folder = folder
        self.kind = kind ?? DocKind.infer(from: url)
        self.status = status
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.note = note
        self.visibility = visibility
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, url, folder, kind, status, updatedAt, updatedBy, note, visibility
    }

    /// Docs saved before locking have no `visibility`: they're shared.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(URL.self, forKey: .url)
        folder = try c.decode(DocFolder.self, forKey: .folder)
        kind = try c.decode(DocKind.self, forKey: .kind)
        status = try c.decode(DocStatus.self, forKey: .status)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decode(String.self, forKey: .updatedBy)
        note = try c.decode(String.self, forKey: .note)
        visibility = try c.decodeIfPresent(DocVisibility.self, forKey: .visibility) ?? .shared
    }

    /// Accepts pasted text and returns a usable https URL, or nil.
    public static func normalizedURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed), let host = url.host, host.contains(".") else { return nil }
        return url
    }
}

/// A doc the athlete locked, as everyone else on the athlete sees it: there's a document in this folder, changed then.
public struct LockedMentalDoc: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var folder: DocFolder
    public var updatedAt: Date

    public init(id: UUID, folder: DocFolder, updatedAt: Date) {
        self.id = id
        self.folder = folder
        self.updatedAt = updatedAt
    }
}
