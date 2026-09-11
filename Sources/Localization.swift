import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"

    var name: String { self == .english ? "english" : "русский" }
    var locale: Locale { Locale(identifier: rawValue) }

    static func load(from defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    func save(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: "language") }

    func text(_ key: String, arguments: [String] = [], bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: rawValue, withExtension: "lproj"),
              let translations = Bundle(url: url) else {
            fatalError("missing \(rawValue) translations; rebuild Foldglass with build.sh")
        }
        let format = translations.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: locale, arguments: arguments)
    }
}

// Keep messages untranslated until display so existing errors switch language too.
struct AppMessage: LocalizedError, Equatable {
    let key: String
    var arguments: [String] = []
    var detail: String?

    func text(in language: AppLanguage, bundle: Bundle = .main) -> String {
        let message = language.text(key, arguments: arguments, bundle: bundle)
        return detail.map { "\(message): \($0)" } ?? message
    }

    var errorDescription: String? { text(in: AppLanguage.load()) }

    static func preserving(_ error: Error) -> AppMessage {
        error as? AppMessage ?? AppMessage(key: "operation_failed", detail: error.localizedDescription)
    }
}
