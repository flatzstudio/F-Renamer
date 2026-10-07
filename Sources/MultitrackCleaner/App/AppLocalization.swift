import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case ru

    var id: String { rawValue }
}

@MainActor
final class AppLocalization: ObservableObject {
    @Published private(set) var language: AppLanguage
    private let defaults: UserDefaults
    private var translations: [String: String]

    init(defaults: UserDefaults = .standard, language: AppLanguage? = nil) {
        self.defaults = defaults
        let savedLanguage = language ?? AppLanguage(rawValue: defaults.string(forKey: "app.language") ?? "") ?? .en
        self.language = savedLanguage
        translations = [:]
        loadTranslations()
    }

    private func loadTranslations() {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = .module
        #else
        bundle = .main
        #endif
        let url = bundle.url(forResource: language.rawValue, withExtension: "json", subdirectory: "Localizations")
            ?? bundle.url(forResource: language.rawValue, withExtension: "json")
        if let url, let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: String].self, from: data) {
            translations = values
        } else {
            translations = [:]
        }
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        defaults.set(language.rawValue, forKey: "app.language")
        loadTranslations()
        objectWillChange.send()
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = translations[key] ?? key
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    func userMessage(_ message: String) -> String {
        switch message {
        case "No WAV files were found at the selected top level.": return text("message.noFiles")
        case "Finder did not provide any WAV files at the selected top level.": return text("message.finderEmpty")
        case "A new name is required.": return text("validation.required")
        case "A file name cannot contain /, : or a null character.": return text("validation.characters")
        case "The name must keep the .wav extension.": return text("validation.extension")
        case "The file name before .wav cannot be empty.": return text("validation.emptyBase")
        case "The source file is no longer available.": return text("validation.sourceMissing")
        case "The target file already exists. No files will be overwritten.": return text("validation.targetExists")
        case "The Finder request link is invalid.": return text("finder.invalidLink")
        case "The Finder selection is no longer available. Run the Quick Action again.": return text("finder.unavailable")
        case "The Finder selection request expired. Run the Quick Action again.": return text("finder.expired")
        case "The Finder selection could not be read.": return text("finder.unreadable")
        case "Select a folder or WAV files to open in F Renamer.": return text("finder.noItems")
        case "Please select one folder or WAV files from the same location.": return text("finder.selection")
        case "Could not complete rename. The app attempted to restore all affected files. Rename validation failed.": return text("rename.failed")
        default:
            if message.hasPrefix("Could not complete rename. The app attempted to restore all affected files.") {
                return text("rename.failed")
            }
            if message.hasPrefix("Two files resolve to ") {
                let name = String(message.dropFirst("Two files resolve to ".count).dropLast())
                return text("validation.duplicate", name)
            }
            if message.hasPrefix("Could not read ") {
                let name = String(message.dropFirst("Could not read ".count).dropLast())
                return text("scan.unreadable", name)
            }
            if let range = message.range(of: #"^Renamed (\d+) files?\.$"#, options: .regularExpression),
               let count = Int(message[range].split(separator: " ")[1]) {
                return text(count == 1 ? "message.renamed.one" : "message.renamed.other", count)
            }
            if let range = message.range(of: #"^Ignored (\d+) unsupported Finder items?\.$"#, options: .regularExpression),
               let count = Int(message[range].split(separator: " ")[1]) {
                return text(count == 1 ? "message.finderIgnored.one" : "message.finderIgnored.other", count)
            }
            return message
        }
    }
}
