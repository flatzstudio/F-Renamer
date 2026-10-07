import Foundation

struct FilenameTokenizer {
    func normalizedBaseName(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func segments(in name: String) -> [String] {
        let normalized = normalizedBaseName(name)
        return normalized
            .replacingOccurrences(of: #"\s*(?:-{1,}|_{1,})\s*"#, with: "\u{001F}", options: .regularExpression)
            .components(separatedBy: "\u{001F}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func join(_ segments: [String]) -> String {
        segments.joined(separator: " - ")
    }
}
