import Foundation

struct CommonSegments: Sendable {
    let left: String?
    let right: String?
}

struct CommonSegmentDetector {
    func detect(in tokenLists: [[String]]) -> CommonSegments {
        guard tokenLists.count >= 2, tokenLists.allSatisfy({ !$0.isEmpty }) else {
            return CommonSegments(left: nil, right: nil)
        }
        let firsts = tokenLists.compactMap(\.first)
        let lasts = tokenLists.compactMap(\.last)
        let left = identicalSegment(firsts) ? firsts.first : nil
        let right = identicalSegment(lasts) ? lasts.first : nil
        return CommonSegments(left: left, right: right)
    }

    private func identicalSegment(_ values: [String]) -> Bool {
        guard let first = values.first, !first.isEmpty else { return false }
        return values.allSatisfy {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) ==
            first.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
    }
}
