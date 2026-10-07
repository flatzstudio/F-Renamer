import Foundation

struct ConfidenceScorer {
    func score(changed: Bool, reasons: [RenameReason]) -> Confidence {
        guard changed else { return .low }
        let hasNumber = reasons.contains(.numericPrefix)
        let hasCommon = reasons.contains { reason in
            if case .commonLeftSegment = reason { return true }
            if case .commonRightSegment = reason { return true }
            return false
        }
        let hasDictionary = reasons.contains {
            if case .normalizedInstrument = $0 { return true }
            return false
        }
        if (hasNumber && hasCommon) || (hasNumber && hasDictionary) || (hasCommon && hasDictionary) { return .high }
        return hasNumber || hasCommon || hasDictionary ? .medium : .low
    }
}
