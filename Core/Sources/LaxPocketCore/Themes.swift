import Foundation

/// A colour theme, stored as hex strings so it can be tested without UIKit.
public struct ThemePalette: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Rank in the final 2026 IWLCA Division I coaches poll, nil for the original theme.
    public let rank: Int?
    public let note: String
    public let primary: String
    public let primaryTint: String
    public let onPrimary: String
    public let accent: String
    public let accentSoft: String
    public let accentTint: String
    public let accentText: String
    public let third: String
    /// Colour of the arrow in the app icon and header mark.
    public let iconAccent: String
    /// Name of the alternate app icon in the asset catalog; nil uses the primary icon.
    public let alternateIconName: String?
}

public enum ThemeCatalog {
    public static let source = "Final 2026 IWLCA Division I coaches poll (May 26, 2026)"
    public static let defaultID = "original"

    public static let all: [ThemePalette] = [
        ThemePalette(id: "original", name: "Original", rank: nil, note: "Default · chalk & navy",
                     primary: "#1D3557", primaryTint: "#E7EDF5", onPrimary: "#C9D6E8", accent: "#E4702F", accentSoft: "#F4C3A1",
                     accentTint: "#FBE9DD", accentText: "#9A3A12", third: "#8DBBE3", iconAccent: "#E4702F", alternateIconName: nil),
        ThemePalette(id: "northwestern", name: "Northwestern", rank: 1, note: "2026 national champion · purple",
                     primary: "#4E2A84", primaryTint: "#EEEAF5", onPrimary: "#D9D1EA", accent: "#836EAA", accentSoft: "#E3DDD1",
                     accentTint: "#F1EEF7", accentText: "#5B3A94", third: "#C9BEE0", iconAccent: "#C9BEE0", alternateIconName: "AppIcon-Northwestern"),
        ThemePalette(id: "north-carolina", name: "North Carolina", rank: 2, note: "Runner-up · Carolina blue & navy",
                     primary: "#13294B", primaryTint: "#E6EEF6", onPrimary: "#BFD9EE", accent: "#7BAFD4", accentSoft: "#E3DDD1",
                     accentTint: "#E4F0F9", accentText: "#1F5A87", third: "#C4DDF0", iconAccent: "#7BAFD4", alternateIconName: "AppIcon-NorthCarolina"),
        ThemePalette(id: "johns-hopkins", name: "Johns Hopkins", rank: 3, note: "Black & Columbia blue",
                     primary: "#151515", primaryTint: "#ECEDEF", onPrimary: "#BFDDF5", accent: "#68ACE5", accentSoft: "#E3DDD1",
                     accentTint: "#E3F0FB", accentText: "#1B5A94", third: "#BFDDF5", iconAccent: "#68ACE5", alternateIconName: "AppIcon-JohnsHopkins"),
        ThemePalette(id: "maryland", name: "Maryland", rank: 4, note: "Red & gold",
                     primary: "#C8102E", primaryTint: "#FBE8EA", onPrimary: "#FFE9EC", accent: "#FFD200", accentSoft: "#FFE78A",
                     accentTint: "#FFF6CC", accentText: "#6E5800", third: "#F2B3BC", iconAccent: "#FFD200", alternateIconName: "AppIcon-Maryland"),
        ThemePalette(id: "colorado", name: "Colorado", rank: 5, note: "Black, gold & silver",
                     primary: "#1A1A1A", primaryTint: "#EFEDE6", onPrimary: "#E8D9A8", accent: "#CFB87C", accentSoft: "#EFE3BD",
                     accentTint: "#F6F0DE", accentText: "#6B5A2A", third: "#8F918E", iconAccent: "#CFB87C", alternateIconName: "AppIcon-Colorado"),
        ThemePalette(id: "stony-brook", name: "Stony Brook", rank: 6, note: "Red, grey & blue",
                     primary: "#990000", primaryTint: "#F7E6E6", onPrimary: "#FFD6D6", accent: "#5B7194", accentSoft: "#D5D9DE",
                     accentTint: "#E8ECF3", accentText: "#33476A", third: "#E6B0B0", iconAccent: "#D5D9DE", alternateIconName: "AppIcon-StonyBrook"),
        ThemePalette(id: "stanford", name: "Stanford", rank: 7, note: "Cardinal & poppy",
                     primary: "#8C1515", primaryTint: "#F6E8E8", onPrimary: "#F6D5D5", accent: "#E98300", accentSoft: "#F2DDB8",
                     accentTint: "#FDEFD9", accentText: "#9A5200", third: "#E3B3B3", iconAccent: "#E98300", alternateIconName: "AppIcon-Stanford"),
        ThemePalette(id: "navy", name: "Navy", rank: 8, note: "Navy & gold",
                     primary: "#00205B", primaryTint: "#E5E9F2", onPrimary: "#E3DCB9", accent: "#C5B783", accentSoft: "#E8E1C2",
                     accentTint: "#F4F0E0", accentText: "#6A5D2B", third: "#AFC0DD", iconAccent: "#C5B783", alternateIconName: "AppIcon-Navy"),
        ThemePalette(id: "michigan", name: "Michigan", rank: 9, note: "Blue & maize",
                     primary: "#00274C", primaryTint: "#E5EBF1", onPrimary: "#FFE68A", accent: "#FFCB05", accentSoft: "#FFE680",
                     accentTint: "#FFF5CC", accentText: "#6B5600", third: "#A9BCD0", iconAccent: "#FFCB05", alternateIconName: "AppIcon-Michigan"),
        ThemePalette(id: "syracuse", name: "Syracuse", rank: 10, note: "Orange & navy",
                     primary: "#C24000", primaryTint: "#FFF1E6", onPrimary: "#FFF3EA", accent: "#000E54", accentSoft: "#B8BFD9",
                     accentTint: "#E3E6F0", accentText: "#000E54", third: "#FBC79E", iconAccent: "#000E54", alternateIconName: "AppIcon-Syracuse")
    ]

    public static func palette(id: String) -> ThemePalette {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Colour maths used by tests and by the app for contrast checks.
public enum ColorMath {
    /// Parses "#RRGGBB" into 0...1 components.
    public static func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// WCAG relative luminance.
    public static func luminance(hex: String) -> Double? {
        guard let c = rgb(hex: hex) else { return nil }
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// WCAG contrast ratio between two colours (1...21).
    public static func contrast(_ a: String, _ b: String) -> Double? {
        guard let la = luminance(hex: a), let lb = luminance(hex: b) else { return nil }
        let (hi, lo) = la > lb ? (la, lb) : (lb, la)
        return (hi + 0.05) / (lo + 0.05)
    }
}
