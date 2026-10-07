import Foundation

struct RenamePlanner {
    private let validator: RenameValidator

    init(validator: RenameValidator = RenameValidator()) {
        self.validator = validator
    }

    func makePlan(from proposals: [RenameProposal]) throws -> RenamePlan {
        let issues = validator.validate(proposals)
        guard issues.isEmpty else { throw RenamePlanningError.validationFailed(issues) }
        return RenamePlan(operations: proposals.filter(\.hasChange).map {
            RenameOperation(sourceURL: $0.sourceURL, targetURL: $0.targetURL)
        })
    }

    func makePlan(from operations: [RenameOperation]) throws -> RenamePlan {
        let proposals = operations.map {
            RenameProposal(sourceURL: $0.sourceURL, originalFilename: $0.sourceURL.lastPathComponent, proposedFilename: $0.targetURL.lastPathComponent, status: .proposed, reasons: [], confidence: .high, isManualEdit: false, validationMessage: nil)
        }
        return try makePlan(from: proposals)
    }
}

enum RenamePlanningError: LocalizedError {
    case validationFailed([ValidationIssue])

    var errorDescription: String? {
        switch self {
        case .validationFailed(let issues): issues.first?.message ?? "Rename validation failed."
        }
    }
}
