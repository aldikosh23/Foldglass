import Foundation

@main
struct LocalizationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let resources = root.appendingPathComponent("Resources")
        let bundle = Bundle(path: resources.path)!
        let suite = "foldglass.localization-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["ru"], forKey: "AppleLanguages")
        precondition(AppLanguage.load(from: defaults) == .english, "english must be the default even on a russian system")
        AppLanguage.russian.save(in: defaults)
        precondition(AppLanguage.load(from: defaults) == .russian, "russian selection must persist")
        AppLanguage.english.save(in: defaults)
        precondition(AppLanguage.load(from: defaults) == .english, "switching back must persist")

        var catalogs: [AppLanguage: [String: String]] = [:]
        for language in AppLanguage.allCases {
            let data = try Data(contentsOf: resources.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings"))
            catalogs[language] = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        }
        let english = catalogs[.english]!, russian = catalogs[.russian]!
        precondition(Set(english.keys) == Set(russian.keys), "both languages must cover the same messages")
        for (key, value) in english {
            precondition(!value.isEmpty && !russian[key]!.isEmpty, "empty translation: \(key)")
            precondition(value.components(separatedBy: "%@").count == russian[key]!.components(separatedBy: "%@").count, "placeholder mismatch: \(key)")
        }
        let sourceURLs = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        let lookup = try NSRegularExpression(pattern: #"(?:\bt\(|\btext\(|\bfail\(|\bkey:\s*)"([a-z_]+)""#)
        for url in sourceURLs {
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in lookup.matches(in: source, range: range) {
                let key = String(source[Range(match.range(at: 1), in: source)!])
                precondition(english[key] != nil, "missing translation: \(key) in \(url.lastPathComponent)")
            }
        }
        let message = AppMessage(key: "raise_lid", arguments: ["92"])
        precondition(message.text(in: .english, bundle: bundle) == "raise the lid past 92°")
        precondition(message.text(in: .russian, bundle: bundle) == "подними крышку выше 92°")
        let failure = AppMessage(key: "sensor_read_failed", detail: "IOKit 0xe00002c0")
        for language in AppLanguage.allCases {
            precondition(failure.text(in: language, bundle: bundle).hasSuffix("IOKit 0xe00002c0"), "preserve underlying error codes")
        }
        print("localization passed: english default, saved selection, complete catalogs, live message translation")
    }
}
