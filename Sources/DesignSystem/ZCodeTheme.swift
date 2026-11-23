import SwiftUI
import UIKit

public enum ZCodeThemeMode: String, CaseIterable, Codable, Identifiable {
    case dark = "dark"
    case light = "light"
    case graphite = "graphite"
    case system = "system"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dark: return "ZCode Dark"
        case .light: return "ZCode Light"
        case .graphite: return "Graphite"
        case .system: return "Follow System"
        }
    }

    public var subtitle: String {
        switch self {
        case .dark: return "Official ZCode Obsidian (#161616)"
        case .light: return "Official ZCode Daylight (#F8F8F8)"
        case .graphite: return "Low-contrast Studio Slate (#1E1F22)"
        case .system: return "Automatically match iOS appearance"
        }
    }
}

public enum ZCodeSyntaxTheme: String, CaseIterable, Codable, Identifiable {
    case githubDark = "github-dark"
    case vitesseDark = "vitesse-dark"
    case catppuccinMocha = "catppuccin-mocha"
    case githubLight = "github-light"
    case vitesseLight = "vitesse-light"
    case catppuccinLatte = "catppuccin-latte"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .githubDark: return "GitHub Dark (Official)"
        case .vitesseDark: return "Vitesse Dark"
        case .catppuccinMocha: return "Catppuccin Mocha"
        case .githubLight: return "GitHub Light"
        case .vitesseLight: return "Vitesse Light"
        case .catppuccinLatte: return "Catppuccin Latte"
        }
    }

    public var isDark: Bool {
        switch self {
        case .githubDark, .vitesseDark, .catppuccinMocha: return true
        case .githubLight, .vitesseLight, .catppuccinLatte: return false
        }
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case vietnamese = "vi"
    case chineseSimplified = "zh-Hans"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English (Default)"
        case .vietnamese: return "Tiếng Việt"
        case .chineseSimplified: return "简体中文"
        }
    }
}

/// Official ZCode Desktop v3.16.3 Color Palette & Design Tokens
public struct ZCodePalette: Equatable {
    public let isDark: Bool
    public let background: Color
    public let backgroundElevated: Color
    public let header: Color
    public let panel: Color
    public let sidebar: Color
    public let card: Color
    public let surfaceHover: Color
    public let inputBackground: Color
    public let inputBorder: Color
    public let inputBorderFocused: Color
    public let menuBackground: Color
    public let foreground: Color
    public let foregroundSubtle: Color
    public let foregroundMuted: Color
    public let border: Color
    public let borderStrong: Color
    public let brand: Color
    public let brandForeground: Color
    public let accentBlue: Color
    public let success: Color
    public let destructive: Color
    public let warning: Color
    public let info: Color

    /// Exact tokens from ZCode Desktop `.theme-zai-dark`
    public static let zaiDark = ZCodePalette(
        isDark: true,
        background: Color(hex: 0x161616),
        backgroundElevated: Color(hex: 0x1C1C1C),
        header: Color(hex: 0x202020),
        panel: Color(hex: 0x202020),
        sidebar: Color(hex: 0x161616),
        card: Color(hex: 0x2B2B2B),
        surfaceHover: Color.white.opacity(0.06),
        inputBackground: Color(hex: 0x262626),
        inputBorder: Color.white.opacity(0.11),
        inputBorderFocused: Color.white.opacity(0.32),
        menuBackground: Color(hex: 0x2B2B2B),
        foreground: Color(hex: 0xE6E6E6),
        foregroundSubtle: Color(hex: 0x969696),
        foregroundMuted: Color(hex: 0x6E6E6E),
        border: Color.white.opacity(0.10),
        borderStrong: Color.white.opacity(0.18),
        brand: Color(hex: 0xFFFFFF),
        brandForeground: Color(hex: 0x000000),
        accentBlue: Color(hex: 0x3B82F6),
        success: Color(hex: 0x46BF72),
        destructive: Color(hex: 0xFF5C5C),
        warning: Color(hex: 0xFF8A30),
        info: Color(hex: 0x58A6FF)
    )

    /// Exact tokens from ZCode Desktop `.theme-zai-light`
    public static let zaiLight = ZCodePalette(
        isDark: false,
        background: Color(hex: 0xF8F8F8),
        backgroundElevated: Color(hex: 0xFFFFFF),
        header: Color(hex: 0xFFFFFF),
        panel: Color(hex: 0xFFFFFF),
        sidebar: Color(hex: 0xF0F0F0),
        card: Color(hex: 0xFFFFFF),
        surfaceHover: Color.black.opacity(0.045),
        inputBackground: Color(hex: 0xF4F4F4),
        inputBorder: Color.black.opacity(0.11),
        inputBorderFocused: Color.black.opacity(0.32),
        menuBackground: Color(hex: 0xFFFFFF),
        foreground: Color(hex: 0x1F1F1F),
        foregroundSubtle: Color(hex: 0x686868),
        foregroundMuted: Color(hex: 0x949494),
        border: Color.black.opacity(0.10),
        borderStrong: Color.black.opacity(0.18),
        brand: Color(hex: 0x000000),
        brandForeground: Color(hex: 0xFFFFFF),
        accentBlue: Color(hex: 0x2563EB),
        success: Color(hex: 0x1E8A3E),
        destructive: Color(hex: 0xE03131),
        warning: Color(hex: 0xD97706),
        info: Color(hex: 0x2B6CB0)
    )

    /// Graphite studio palette (from zcode-mobile-app reference)
    public static let graphite = ZCodePalette(
        isDark: true,
        background: Color(hex: 0x1E1F22),
        backgroundElevated: Color(hex: 0x25272B),
        header: Color(hex: 0x25272B),
        panel: Color(hex: 0x232529),
        sidebar: Color(hex: 0x1B1C1F),
        card: Color(hex: 0x2B2D31),
        surfaceHover: Color.white.opacity(0.07),
        inputBackground: Color(hex: 0x282A2E),
        inputBorder: Color.white.opacity(0.12),
        inputBorderFocused: Color.white.opacity(0.34),
        menuBackground: Color(hex: 0x2B2D31),
        foreground: Color(hex: 0xDFE1E5),
        foregroundSubtle: Color(hex: 0x9DA0A8),
        foregroundMuted: Color(hex: 0x72757D),
        border: Color.white.opacity(0.10),
        borderStrong: Color.white.opacity(0.18),
        brand: Color(hex: 0xFFFFFF),
        brandForeground: Color(hex: 0x141517),
        accentBlue: Color(hex: 0x4C8DFF),
        success: Color(hex: 0x49C479),
        destructive: Color(hex: 0xF76767),
        warning: Color(hex: 0xF59E0B),
        info: Color(hex: 0x60A5FA)
    )

    public static func resolve(mode: ZCodeThemeMode, systemScheme: ColorScheme) -> ZCodePalette {
        switch mode {
        case .dark:
            return .zaiDark
        case .light:
            return .zaiLight
        case .graphite:
            return .graphite
        case .system:
            return systemScheme == .light ? .zaiLight : .zaiDark
        }
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

private struct ZCodePaletteKey: EnvironmentKey {
    static let defaultValue: ZCodePalette = .zaiDark
}

public extension EnvironmentValues {
    var zcodePalette: ZCodePalette {
        get { self[ZCodePaletteKey.self] }
        set { self[ZCodePaletteKey.self] = newValue }
    }
}

/// Lightweight runtime localization helper (strictly defaults to English)
public enum L10n {
    public static func text(_ en: String, vi: String? = nil, zh: String? = nil, lang: AppLanguage) -> String {
        switch lang {
        case .english:
            return en
        case .vietnamese:
            return vi ?? en
        case .chineseSimplified:
            return zh ?? en
        }
    }
}
