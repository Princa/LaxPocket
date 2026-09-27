import SwiftUI
import LaxPocketCore

extension Color {
    /// Creates a colour from "#RRGGBB"; falls back to magenta so a typo is obvious.
    init(hex: String) {
        if let c = ColorMath.rgb(hex: hex) {
            self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
        } else {
            self.init(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)
        }
    }
}

/// The active colour theme plus the fixed neutrals shared by every theme.
struct AppTheme {
    let palette: ThemePalette

    var primary: Color { Color(hex: palette.primary) }
    var primaryTint: Color { Color(hex: palette.primaryTint) }
    var onPrimary: Color { Color(hex: palette.onPrimary) }
    var accent: Color { Color(hex: palette.accent) }
    var accentSoft: Color { Color(hex: palette.accentSoft) }
    var accentTint: Color { Color(hex: palette.accentTint) }
    var accentText: Color { Color(hex: palette.accentText) }
    var third: Color { Color(hex: palette.third) }
    var iconAccent: Color { Color(hex: palette.iconAccent) }

    // Neutrals
    static let background = Color(hex: "#F2F0EB")
    static let card = Color.white
    static let ink = Color(hex: "#15171C")
    static let ink2 = Color(hex: "#3A3D45")
    static let muted = Color(hex: "#545862")
    static let caption = Color(hex: "#62666F")
    static let line = Color(hex: "#ECE9E2")
    static let border = Color(hex: "#DDD9D0")
    static let chevron = Color(hex: "#8A8D95")

    func color(for category: SessionCategory) -> Color {
        switch category {
        case .team: return primary
        case .skills: return accent
        case .fitness: return third
        }
    }

    func tint(for category: SessionCategory) -> (background: Color, foreground: Color) {
        switch category {
        case .team: return (primaryTint, primary)
        case .skills: return (accentTint, accentText)
        case .fitness: return (primaryTint, primary)
        }
    }

    func tierColors(_ tier: Tier) -> (background: Color, foreground: Color) {
        switch tier {
        case .elite: return (primary, .white)
        case .competitive: return (primaryTint, primary)
        case .developing: return (accentTint, accentText)
        }
    }

    func bandColor(_ tier: Tier) -> Color {
        switch tier {
        case .developing: return accentSoft
        case .competitive: return third
        case .elite: return primary
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme(palette: ThemeCatalog.palette(id: ThemeCatalog.defaultID))
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension Font {
    /// Condensed display face used for titles and big numbers.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}
