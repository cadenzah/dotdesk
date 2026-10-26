import Foundation

/// The language the UI is shown in: the system's, or one picked in Settings.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, korean, english
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("시스템 설정 따르기", "Match system")
        case .korean: return "한국어"
        case .english: return "English"
        }
    }
}

enum Lang {
    /// Whether the UI is in Korean right now. Set from settings on the main thread, read from anywhere.
    nonisolated(unsafe) static var korean = resolve(.system)

    static func resolve(_ language: AppLanguage) -> Bool {
        switch language {
        case .korean: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        }
    }
}

/// The Korean or the English text, whichever the UI is in. Both are written side by side where the text is used,
/// so Korean particles (이/가) and English word order can each be handled in place.
func L(_ ko: String, _ en: String) -> String { Lang.korean ? ko : en }

/// Display name for a character group. The Korean names double as ids, so only translate them for display.
func characterGroupLabel(_ group: String) -> String {
    switch group {
    case "기본 도트": return L("기본 도트", "Pixel")
    case "포켓몬": return L("포켓몬", "Pokémon")
    default: return group
    }
}
