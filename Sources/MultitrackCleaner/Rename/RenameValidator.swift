import Foundation

struct ValidationIssue: Hashable, Sendable {
    let proposalID: URL
    let message: String
    let status: RenameStatus
}

struct RenameValidator {
    private let fileAccess: any FileAccess

    init(fileAccess: any FileAccess = LocalFileAccess()) {
        self.fileAccess = fileAccess
    }

    func validate(_ proposals: [RenameProposal]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let changed = proposals.filter(\.hasChange)
        let sourcePaths = Set(changed.map { $0.sourceURL.standardizedFileURL.path })

        for proposal in changed {
            let name = proposal.proposedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                issues.append(.init(proposalID: proposal.id, message: "A new name is required.", status: .invalid))
            } else if name.contains("/") || name.contains(":") || name.contains("\0") {
                issues.append(.init(proposalID: proposal.id, message: "A file name cannot contain /, : or a null character.", status: .invalid))
            } else if URL(fileURLWithPath: name).pathExtension.caseInsensitiveCompare("wav") != .orderedSame {
                issues.append(.init(proposalID: proposal.id, message: "The name must keep the .wav extension.", status: .invalid))
            } else if name == ".wav" {
                issues.append(.init(proposalID: proposal.id, message: "The file name before .wav cannot be empty.", status: .invalid))
            } else if !fileAccess.fileExists(at: proposal.sourceURL) {
                issues.append(.init(proposalID: proposal.id, message: "The source file is no longer available.", status: .invalid))
            }
        }

        let grouped = Dictionary(grouping: changed, by: targetComparisonKey)
        for group in grouped.values where group.count > 1 {
            for proposal in group {
                issues.append(.init(proposalID: proposal.id, message: "Two files resolve to \(proposal.proposedFilename).", status: .conflict))
            }
        }

        for proposal in changed {
            let target = proposal.targetURL
            if fileAccess.fileExists(at: target), !sourcePaths.contains(target.standardizedFileURL.path) {
                issues.append(.init(proposalID: proposal.id, message: "The target file already exists. No files will be overwritten.", status: .conflict))
            }
        }
        return issues
    }

    private func targetComparisonKey(_ proposal: RenameProposal) -> String {
        "\(proposal.sourceURL.deletingLastPathComponent().standardizedFileURL.path)\u{001F}\(normalizedPathComponent(proposal.proposedFilename))"
    }

    private func normalizedPathComponent(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct ProposedNameResolver {
    private let fileAccess: any FileAccess

    init(fileAccess: any FileAccess = LocalFileAccess()) {
        self.fileAccess = fileAccess
    }

    func resolve(_ proposals: [RenameProposal]) -> [RenameProposal] {
        guard !proposals.isEmpty else { return [] }

        var groupedIndices: [String: [Int]] = [:]
        var groupOrder: [String] = []
        for index in proposals.indices {
            let key = targetComparisonKey(for: proposals[index])
            if groupedIndices[key] == nil { groupOrder.append(key) }
            groupedIndices[key, default: []].append(index)
        }

        let mutableIndicesByGroup: [String: [Int]] = Dictionary(uniqueKeysWithValues: groupOrder.compactMap { key in
            guard let indices = groupedIndices[key], indices.count > 1 else { return nil }
            let mutable = indices.filter { !proposals[$0].isManualEdit && proposals[$0].hasChange }
            return mutable.isEmpty ? nil : (key, mutable)
        })
        guard !mutableIndicesByGroup.isEmpty else { return proposals }

        let resolvingIndices = Set(mutableIndicesByGroup.values.flatMap { $0 })
        var reservedNames = Set(proposals.indices.compactMap { index in
            resolvingIndices.contains(index) ? nil : targetComparisonKey(for: proposals[index])
        })
        let releasableSourcePaths = Set(proposals.filter(\.hasChange).map { $0.sourceURL.standardizedFileURL.path })
        var resolved = proposals

        for key in groupOrder {
            guard let indices = mutableIndicesByGroup[key] else { continue }
            var nextNumber = 1
            for index in indices {
                let proposal = resolved[index]
                guard let parts = filenameParts(proposal.proposedFilename) else { continue }
                var candidate: String
                repeat {
                    candidate = "\(parts.base) \(nextNumber).\(parts.extension)"
                    nextNumber += 1
                } while !isAvailable(
                    candidate,
                    in: proposal.sourceURL.deletingLastPathComponent(),
                    reservedNames: reservedNames,
                    releasableSourcePaths: releasableSourcePaths
                )

                resolved[index].proposedFilename = candidate
                resolved[index].reasons.removeAll { reason in
                    if case .collisionNumber = reason { return true }
                    return false
                }
                resolved[index].reasons.append(.collisionNumber(nextNumber - 1))
                reservedNames.insert(targetComparisonKey(for: resolved[index]))
            }
        }
        return resolved
    }

    private func isAvailable(
        _ filename: String,
        in directory: URL,
        reservedNames: Set<String>,
        releasableSourcePaths: Set<String>
    ) -> Bool {
        let targetURL = directory.appendingPathComponent(filename)
        let key = targetComparisonKey(directory: directory, filename: filename)
        guard !reservedNames.contains(key) else { return false }
        return !fileAccess.fileExists(at: targetURL) || releasableSourcePaths.contains(targetURL.standardizedFileURL.path)
    }

    private func filenameParts(_ filename: String) -> (base: String, extension: String)? {
        let url = URL(fileURLWithPath: filename)
        let base = url.deletingPathExtension().lastPathComponent
        let extensionPart = url.pathExtension
        guard !base.isEmpty, !extensionPart.isEmpty else { return nil }
        return (base, extensionPart)
    }

    private func targetComparisonKey(for proposal: RenameProposal) -> String {
        targetComparisonKey(directory: proposal.sourceURL.deletingLastPathComponent(), filename: proposal.proposedFilename)
    }

    private func targetComparisonKey(directory: URL, filename: String) -> String {
        let normalized = filename.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(directory.standardizedFileURL.path)\u{001F}\(normalized)"
    }
}
