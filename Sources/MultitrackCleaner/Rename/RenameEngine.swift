import Foundation
import OSLog

struct RenameEngine {
    private let fileAccess: any FileAccess
    private let logger = Logger(subsystem: "com.multitrackcleaner", category: "rename")

    init(fileAccess: any FileAccess = LocalFileAccess()) {
        self.fileAccess = fileAccess
    }

    func execute(_ plan: RenamePlan) throws -> [RenameOperation] {
        guard !plan.operations.isEmpty else { return [] }
        let staged = try plan.operations.map { operation in
            StagedOperation(operation: operation, temporaryURL: try uniqueTemporaryURL(for: operation.sourceURL))
        }
        var inTemporary: [StagedOperation] = []
        var completed: [StagedOperation] = []

        do {
            for item in staged {
                try fileAccess.moveItem(at: item.operation.sourceURL, to: item.temporaryURL)
                inTemporary.append(item)
            }
            for item in staged {
                try fileAccess.moveItem(at: item.temporaryURL, to: item.operation.targetURL)
                completed.append(item)
                inTemporary.removeAll { $0 == item }
            }
            logger.info("Completed transactional rename of \(plan.operations.count, privacy: .public) files")
            return plan.operations
        } catch {
            logger.error("Rename failed; attempting rollback")
            rollback(completed: completed, inTemporary: inTemporary)
            throw RenameExecutionError.failed(originalError: error.localizedDescription)
        }
    }

    private func rollback(completed: [StagedOperation], inTemporary: [StagedOperation]) {
        for item in completed.reversed() where fileAccess.fileExists(at: item.operation.targetURL) && !fileAccess.fileExists(at: item.operation.sourceURL) {
            try? fileAccess.moveItem(at: item.operation.targetURL, to: item.operation.sourceURL)
        }
        for item in inTemporary.reversed() where fileAccess.fileExists(at: item.temporaryURL) && !fileAccess.fileExists(at: item.operation.sourceURL) {
            try? fileAccess.moveItem(at: item.temporaryURL, to: item.operation.sourceURL)
        }
    }

    private func uniqueTemporaryURL(for sourceURL: URL) throws -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        for _ in 0..<100 {
            let candidate = directory.appendingPathComponent(".multitrack-cleaner-\(UUID().uuidString).tmp")
            if !fileAccess.fileExists(at: candidate) { return candidate }
        }
        throw RenameExecutionError.failed(originalError: "Could not allocate a safe temporary file name.")
    }

    private struct StagedOperation: Equatable {
        let operation: RenameOperation
        let temporaryURL: URL
    }
}

enum RenameExecutionError: LocalizedError {
    case failed(originalError: String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): "Could not complete rename. The app attempted to restore all affected files. \(message)"
        }
    }
}
