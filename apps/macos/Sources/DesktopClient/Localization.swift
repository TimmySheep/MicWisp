import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        let preference = UserDefaults.standard.string(forKey: "language") ?? "system"
        let language: String
        switch preference {
        case "zh-Hans": language = "zh-Hans"
        case "en": language = "en"
        default:
            language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
        let localized = Bundle.module.url(forResource: language, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        return localized.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
