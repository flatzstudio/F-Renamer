import Foundation

struct InstrumentNormalizer {
    private let rules: [(source: String, target: String)] = [
        ("Открытый хэт", "Open Hat"), ("Открытый хет", "Open Hat"),
        ("Закрытый хэт", "Closed Hat"), ("Закрытый хет", "Closed Hat"),
        ("Хай-хэт", "Hi-Hat"), ("Хай хэт", "Hi-Hat"), ("Хайхэт", "Hi-Hat"),
        ("Тамбурин", "Tambourine"), ("Перкуссия", "Percussion"),
        ("Ковбелл", "Cowbell"), ("Шейкер", "Shaker"), ("Конга", "Conga"),
        ("Снейр", "Snare"), ("Бочка", "Kick"), ("Кик", "Kick"),
        ("Хэт", "Hat"), ("Хет", "Hat"), ("Клэп", "Clap"), ("Клап", "Clap"),
        ("Басс", "Bass"), ("Бас", "Bass"), ("Вокал", "Vocal"),
        ("Голос", "Vocal"), ("Бубен", "Tambourine"), ("Том", "Tom")
    ]

    func normalize(_ name: String) -> (value: String, matchedSource: String?) {
        let normalized = normalizeForMatch(name)
        guard let rule = rules.first(where: { normalizeForMatch($0.source) == normalized }) else {
            return (name, nil)
        }
        return (rule.target, rule.source)
    }

    func isKnownTrackName(_ name: String) -> Bool {
        let normalized = normalizeForMatch(name)
        let canonical = ["bass", "kick", "snare", "hat", "hi-hat", "vocal", "shaker", "tambourine", "conga", "clap", "tom", "percussion", "cowbell"]
        return canonical.contains(normalized) || rules.contains { normalizeForMatch($0.source) == normalized }
    }

    private func normalizeForMatch(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
