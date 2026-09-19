import Foundation

enum Copy {
    private static var isJapanese: Bool {
        switch UserDefaults.standard.string(forKey: "appLanguage") {
        case "ja": return true
        case "en": return false
        default: break
        }
        return Locale.current.language.languageCode?.identifier == "ja"
    }

    static func text(_ japanese: String, _ english: String) -> String {
        isJapanese ? japanese : english
    }
}
