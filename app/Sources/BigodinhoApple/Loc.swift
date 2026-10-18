import Foundation

/// Idioma da interface: "auto" (segue o sistema), "en" ou "pt".
enum L {
    static var isPT: Bool {
        switch Settings.shared.language {
        case "pt": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.lowercased().hasPrefix("pt") ?? false
        }
    }

    static func t(_ en: String, _ pt: String) -> String { isPT ? pt : en }
}
