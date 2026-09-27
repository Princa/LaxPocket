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

    public init(id: UUID = UUID(), title: String, url: URL, folder: DocFolder, kind: DocKind? = nil, status: DocStatus = .new, updatedAt: Date, updatedBy: String = "", note: String = "") {
        self.id = id
        self.title = title
        self.url = url
        self.folder = folder
        self.kind = kind ?? DocKind.infer(from: url)
        self.status = status
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.note = note
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
