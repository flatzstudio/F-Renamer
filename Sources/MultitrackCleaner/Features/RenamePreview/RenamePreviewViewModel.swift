import Foundation
import SwiftUI
import OSLog

@MainActor
final class RenamePreviewViewModel: ObservableObject {
    @Published private(set) var files: [AudioFile] = []
    @Published var proposals: [RenameProposal] = []
    @Published private(set) var selectedIDs: Set<URL> = []
    @Published private(set) var validationIssues: [ValidationIssue] = []
    @Published var userMessage: String?
    @Published private(set) var inputSource: String?
    @Published var isLoading = false
    @Published var capitalizeNames = false {
        didSet {
            guard oldValue != capitalizeNames, !files.isEmpty else { return }
            rebuildAutomaticProposals()
        }
    }

    private let scanner = FileScanner()
    private let analyzer = FilenameAnalyzer()
    private let nameCapitalizer = NameCapitalizer()
    private let proposedNameResolver = ProposedNameResolver()
    private var securityScopeLease: SecurityScopeLease?
    private let logger = Logger(subsystem: "com.multitrackcleaner", category: "preview")

    var renameCount: Int { proposals.filter(\.hasChange).count }
    var selectedProposals: [RenameProposal] { proposals.filter { selectedIDs.contains($0.id) } }
    var selectedRenameCount: Int { selectedProposals.filter(\.hasChange).count }
    var canRename: Bool { selectedRenameCount > 0 && !selectedProposals.contains { $0.status == .conflict || $0.status == .invalid } && !isLoading }
    var hasManualEdits: Bool { proposals.contains(where: \.isManualEdit) }

    func load(urls: [URL], source: String? = nil) {
        load(urls: urls, source: source, releaseSecurityScope: true)
    }

    func loadAdditional(urls additionalURLs: [URL]) {
        load(urls: files.map(\.url) + additionalURLs, source: inputSource, releaseSecurityScope: false)
    }

    private func load(urls: [URL], source: String?, releaseSecurityScope: Bool) {
        if releaseSecurityScope {
            securityScopeLease?.release()
            securityScopeLease = nil
        }
        inputSource = source
        isLoading = true
        defer { isLoading = false }
        do {
            let scanned = try scanner.scan(urls: urls)
            files = scanned
            proposals = proposedNameResolver.resolve(analyzer.analyze(scanned, capitalizeNames: capitalizeNames))
            selectedIDs = Set(proposals.map(\.id))
            validate()
            userMessage = scanned.isEmpty ? "No WAV files were found at the selected top level." : nil
        } catch {
            userMessage = error.localizedDescription
            files = []
            proposals = []
            selectedIDs = []
        }
    }

    func load(finderImport: ResolvedFinderImport) {
        securityScopeLease?.release()
        securityScopeLease = finderImport.lease
        inputSource = "Finder"
        isLoading = true
        defer { isLoading = false }
        do {
            let scanned = try scanner.scan(urls: finderImport.selection.urls)
            files = scanned
            proposals = proposedNameResolver.resolve(analyzer.analyze(scanned, capitalizeNames: capitalizeNames))
            selectedIDs = Set(proposals.map(\.id))
            validate()
            if scanned.isEmpty {
                userMessage = "Finder did not provide any WAV files at the selected top level."
            } else if finderImport.selection.ignoredItemCount > 0 {
                userMessage = "Ignored \(finderImport.selection.ignoredItemCount) unsupported Finder item\(finderImport.selection.ignoredItemCount == 1 ? "" : "s")."
            } else {
                userMessage = nil
            }
        } catch {
            userMessage = error.localizedDescription
            files = []
            proposals = []
            selectedIDs = []
        }
    }

    private func rebuildAutomaticProposals() {
        let manualProposals = Dictionary(uniqueKeysWithValues: proposals.filter(\.isManualEdit).map { ($0.id, $0) })
        let regenerated = analyzer.analyze(files, capitalizeNames: capitalizeNames).map { generated -> RenameProposal in
            guard var manual = manualProposals[generated.id] else { return generated }
            manual.reasons = generated.reasons
            if !manual.reasons.contains(.manual) { manual.reasons.append(.manual) }
            manual.status = .manual
            manual.validationMessage = nil
            return manual
        }
        proposals = proposedNameResolver.resolve(regenerated)
        validate()
    }

    func updateProposal(id: URL, name: String) {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else { return }
        proposals[index].proposedFilename = name
        proposals[index].isManualEdit = true
        proposals[index].status = .manual
        if !proposals[index].reasons.contains(.manual) { proposals[index].reasons.append(.manual) }
        validate()
    }

    func selectAll(_ selected: Bool) {
        selectedIDs = selected ? Set(proposals.map(\.id)) : []
    }

    func setSelected(_ selected: Bool, id: URL) {
        if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
    }

    func capitalizeSelected() {
        for index in proposals.indices where selectedIDs.contains(proposals[index].id) {
            proposals[index].proposedFilename = nameCapitalizer.capitalizeFilename(proposals[index].proposedFilename)
            proposals[index].isManualEdit = true
            proposals[index].status = .manual
            if !proposals[index].reasons.contains(.manual) { proposals[index].reasons.append(.manual) }
        }
        validate()
    }

    func validate() {
        validationIssues = RenameValidator().validate(proposals)
        let issueByID = Dictionary(grouping: validationIssues, by: \.proposalID)
        for index in proposals.indices {
            if let issue = issueByID[proposals[index].id]?.first {
                proposals[index].status = issue.status
                proposals[index].validationMessage = issue.message
            } else {
                proposals[index].validationMessage = nil
                if proposals[index].isManualEdit {
                    proposals[index].status = .manual
                } else {
                    proposals[index].status = proposals[index].hasChange ? .proposed : .unchanged
                }
            }
        }
    }

    func rename() async {
        validate()
        guard canRename else { return }
        let selected = selectedProposals
        do {
            let plan = try RenamePlanner().makePlan(from: selected)
            isLoading = true
            defer { isLoading = false }
            let operations = try await Task.detached(priority: .userInitiated) {
                try RenameEngine().execute(plan)
            }.value
            userMessage = "Renamed \(operations.count) file\(operations.count == 1 ? "" : "s")."
            let renamedIDs = Set(operations.map(\.sourceURL))
            proposals.removeAll { renamedIDs.contains($0.id) }
            files.removeAll { renamedIDs.contains($0.url) }
            selectedIDs = Set(proposals.map(\.id))
            validate()
        } catch {
            userMessage = error.localizedDescription
            logger.error("Rename request failed: \(error.localizedDescription, privacy: .private)")
        }
    }

}
