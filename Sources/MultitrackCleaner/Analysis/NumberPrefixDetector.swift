import Foundation

struct NumberPrefixDetector {
    struct Detection: Sendable {
        let number: Int
        let hadLeadingZeros: Bool
        let hadExplicitSeparator: Bool
        let remainder: String
    }

    private let pattern = try! NSRegularExpression(pattern: #"^\s*(\d{1,5})(\s*[-_.:]\s*|\s+)(.+?)\s*$"#)

    func candidate(in name: String) -> Detection? {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = pattern.firstMatch(in: name, range: range),
              let numberRange = Range(match.range(at: 1), in: name),
              let delimiterRange = Range(match.range(at: 2), in: name),
              let remainderRange = Range(match.range(at: 3), in: name),
              let number = Int(name[numberRange]) else { return nil }

        let numberText = String(name[numberRange])
        let delimiter = String(name[delimiterRange])
        let remainder = String(name[remainderRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }
        return Detection(
            number: number,
            hadLeadingZeros: numberText.count > 1 && numberText.first == "0",
            hadExplicitSeparator: delimiter.rangeOfCharacter(from: CharacterSet(charactersIn: "-_.:")) != nil,
            remainder: remainder
        )
    }

    func isConfirmed(_ detection: Detection, in batch: [String]) -> Bool {
        if detection.hadLeadingZeros || detection.hadExplicitSeparator { return true }
        let candidates = batch.compactMap(candidate(in:)).filter { $0.hadLeadingZeros || $0.hadExplicitSeparator }
        guard candidates.count >= 2 else { return false }
        let values = candidates.map(\.number).sorted()
        return Set(values).count == values.count && values.last! - values.first! <= values.count + 2
    }
}
