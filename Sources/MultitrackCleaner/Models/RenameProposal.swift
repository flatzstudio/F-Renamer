import Foundation

enum RenameStatus: String, Codable, Sendable {
    case unchanged
    case proposed
    case manual
    case conflict
    case invalid

    var title: String {
        switch self {
        case .unchanged: "No change"
        case .proposed: "Proposed"
        case .manual: "Manual"
        case .conflict: "Conflict"
        case .invalid: "Invalid"
        }
    }
}

enum RenameReason: Hashable, Sendable {
    case numericPrefix
    case commonLeftSegment(String)
    case commonRightSegment(String)
    case normalizedInstrument(String)
    case capitalizedName
    case collisionNumber(Int)
    case manual
    case ambiguous

    var title: String {
        switch self {
        case .numericPrefix: "Track number"
        case .commonLeftSegment(let value): "Common left: \(value)"
        case .commonRightSegment(let value): "Common right: \(value)"
        case .normalizedInstrument(let value): "Instrument: \(value)"
        case .capitalizedName: "Capitalization normalized"
        case .collisionNumber(let value): "Collision number: \(value)"
        case .manual: "Edited manually"
        case .ambiguous: "Kept unchanged"
        }
    }
}

enum Confidence: String, Sendable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: "Confident"
        case .medium: "Review"
        case .low: "No change"
        }
    }
}

struct RenameProposal: Identifiable, Hashable, Sendable {
    let sourceURL: URL
    let originalFilename: String
    var proposedFilename: String
    var status: RenameStatus
    var reasons: [RenameReason]
    var confidence: Confidence
    var isManualEdit: Bool
    var validationMessage: String?

    var id: URL { sourceURL }
    var targetURL: URL { sourceURL.deletingLastPathComponent().appendingPathComponent(proposedFilename) }
    var hasChange: Bool { originalFilename != proposedFilename }
}

struct RenameOperation: Hashable, Sendable {
    let sourceURL: URL
    let targetURL: URL
}

struct RenamePlan: Sendable {
    let operations: [RenameOperation]
}
