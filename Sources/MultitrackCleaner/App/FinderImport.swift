import AppKit
import Combine
import Foundation
import OSLog

private let finderHandoffLogger = Logger(subsystem: "com.multitrackcleaner", category: "finder-handoff")
private let finderBookmarkLogger = Logger(subsystem: "com.multitrackcleaner", category: "finder-bookmark")

struct FinderImportRequest: Codable, Sendable {
    static let currentVersion = 1

    struct Entry: Codable, Sendable {
        let bookmarkData: Data
        let displayName: String
    }

    let version: Int
    let id: UUID
    let createdAt: Date
    let entries: [Entry]
}

enum FinderImportError: LocalizedError, Equatable, CustomNSError {
    case invalidLink
    case unavailableRequest
    case expiredRequest
    case invalidRequest
    case noSupportedItems
    case multipleFolders
    case wavFilesFromDifferentFolders
    case accessDenied(String)
    case unavailableItem(String)

    static var errorDomain: String { "com.multitrackcleaner.finder-import" }

    var errorCode: Int {
        switch self {
        case .invalidLink: 0
        case .unavailableRequest: 1
        case .expiredRequest: 2
        case .invalidRequest: 3
        case .noSupportedItems: 4
        case .multipleFolders: 5
        case .wavFilesFromDifferentFolders: 6
        case .accessDenied: 7
        case .unavailableItem: 8
        }
    }

    var diagnosticLabel: String {
        switch self {
        case .invalidLink: "invalidLink"
        case .unavailableRequest: "unavailableRequest"
        case .expiredRequest: "expiredRequest"
        case .invalidRequest: "invalidRequest"
        case .noSupportedItems: "noSupportedItems"
        case .multipleFolders: "multipleFolders"
        case .wavFilesFromDifferentFolders: "wavFilesFromDifferentFolders"
        case .accessDenied: "accessDenied"
        case .unavailableItem: "unavailableItem"
        }
    }

    var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: errorDescription ?? diagnosticLabel,
            "FinderImportErrorLabel": diagnosticLabel
        ]
    }

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            "The Finder request link is invalid."
        case .unavailableRequest:
            "The Finder selection is no longer available. Run the Quick Action again."
        case .expiredRequest:
            "The Finder selection request expired. Run the Quick Action again."
        case .invalidRequest:
            "The Finder selection could not be read."
        case .noSupportedItems:
            "Select a folder or WAV files to open in F Renamer."
        case .multipleFolders, .wavFilesFromDifferentFolders:
            "Please select one folder or WAV files from the same location."
        case .accessDenied(let name):
            "F Renamer does not have permission to access \(name). Choose it again in the app."
        case .unavailableItem(let name):
            "\(name) is no longer available."
        }
    }
}

struct FinderAttachmentURLExtractor {
    static let supportedTypeIdentifiers = [
        "com.microsoft.waveform-audio",
        "public.folder"
    ]

    func loadURL(from provider: NSItemProvider, completion: @escaping @Sendable (URL?, Error?) -> Void) {
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: Self.supportedTypeIdentifiers.contains) else {
            completion(nil, FinderImportError.noSupportedItems)
            return
        }

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
            if let url = item as? URL {
                completion(url, error)
            } else if let url = item as? NSURL {
                completion(url as URL, error)
            } else {
                completion(nil, error ?? FinderImportError.noSupportedItems)
            }
        }
    }
}

struct FinderSelection: Sendable {
    let urls: [URL]
    let ignoredItemCount: Int
}

struct FinderSelectionFilter {
    func filter(urls: [URL]) throws -> FinderSelection {
        finderHandoffLogger.info("Selection filter received \(urls.count, privacy: .private) URL(s): \(urls.map(\.path).joined(separator: " | "), privacy: .private)")
        var folders: [URL] = []
        var wavFiles: [URL] = []
        var ignoredItemCount = 0

        for (index, url) in urls.enumerated() {
            let selectedURL = url.standardizedFileURL
            let canonicalURL = selectedURL.resolvingSymlinksInPath()
            let selectedParent = selectedURL.deletingLastPathComponent().path
            let canonicalParent = canonicalURL.deletingLastPathComponent().path
            guard let values = try? canonicalURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
                finderHandoffLogger.error("Selection item ignored index=\(index, privacy: .private) reason=resourceLookupFailed selected=\(selectedURL.path, privacy: .private) canonical=\(canonicalURL.path, privacy: .private)")
                ignoredItemCount += 1
                continue
            }
            if values.isDirectory == true {
                finderHandoffLogger.info("Selection item accepted index=\(index, privacy: .private) kind=folder selected=\(selectedURL.path, privacy: .private) canonical=\(canonicalURL.path, privacy: .private)")
                folders.append(selectedURL)
            } else if values.isRegularFile == true,
                      canonicalURL.pathExtension.caseInsensitiveCompare("wav") == .orderedSame {
                finderHandoffLogger.info("Selection item accepted index=\(index, privacy: .private) kind=wav selected=\(selectedURL.path, privacy: .private) selectedParent=\(selectedParent, privacy: .private) canonical=\(canonicalURL.path, privacy: .private) canonicalParent=\(canonicalParent, privacy: .private)")
                wavFiles.append(selectedURL)
            } else {
                finderHandoffLogger.info("Selection item ignored index=\(index, privacy: .private) reason=unsupported selected=\(selectedURL.path, privacy: .private) canonical=\(canonicalURL.path, privacy: .private)")
                ignoredItemCount += 1
            }
        }

        let uniqueFolders = unique(folders)
        guard uniqueFolders.count <= 1 else {
            finderHandoffLogger.error("Selection rejected [multipleFolders]: \(uniqueFolders.map(\.path).joined(separator: " | "), privacy: .private)")
            throw FinderImportError.multipleFolders
        }

        let uniqueWAVFiles = unique(wavFiles)
        let selectedWAVParents = Set(uniqueWAVFiles.map { $0.deletingLastPathComponent().path })
        guard selectedWAVParents.count <= 1 else {
            finderHandoffLogger.error("Selection rejected [wavFilesFromDifferentFolders]: \(selectedWAVParents.sorted().joined(separator: " | "), privacy: .private)")
            throw FinderImportError.wavFilesFromDifferentFolders
        }

        let supported = uniqueFolders + uniqueWAVFiles
        guard !supported.isEmpty else {
            finderHandoffLogger.error("Selection rejected [noSupportedItems], ignored=\(ignoredItemCount, privacy: .public)")
            throw FinderImportError.noSupportedItems
        }
        finderHandoffLogger.info("Selection accepted: folders=\(uniqueFolders.count, privacy: .public), wavs=\(uniqueWAVFiles.count, privacy: .public), ignored=\(ignoredItemCount, privacy: .public)")
        return FinderSelection(urls: supported, ignoredItemCount: ignoredItemCount)
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

struct FinderImportPasteboard {
    static let requestLifetime: TimeInterval = 60
    static let payloadType = NSPasteboard.PasteboardType("com.multitrackcleaner.finder-import-payload")

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func write(entries: [FinderImportRequest.Entry]) throws -> FinderImportRequest {
        let request = FinderImportRequest(
            version: FinderImportRequest.currentVersion,
            id: UUID(),
            createdAt: now(),
            entries: entries
        )
        let pasteboard = NSPasteboard(name: Self.name(for: request.id))
        let payload: Data
        do {
            payload = try JSONEncoder().encode(request)
        } catch {
            let nsError = error as NSError
            finderHandoffLogger.error("Pasteboard encode failed id=\(request.id.uuidString, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            throw error
        }
        pasteboard.clearContents()
        guard pasteboard.setData(payload, forType: Self.payloadType) else {
            finderHandoffLogger.error("Pasteboard write failed id=\(request.id.uuidString, privacy: .public) bytes=\(payload.count, privacy: .public)")
            throw FinderImportError.unavailableRequest
        }
        finderHandoffLogger.info("Pasteboard write succeeded id=\(request.id.uuidString, privacy: .public) entries=\(entries.count, privacy: .public) bytes=\(payload.count, privacy: .public)")
        return request
    }

    func claim(id: UUID) throws -> FinderImportRequest {
        finderHandoffLogger.info("Pasteboard claim started id=\(id.uuidString, privacy: .public)")
        let pasteboard = NSPasteboard(name: Self.name(for: id))
        guard let data = pasteboard.data(forType: Self.payloadType) else {
            finderHandoffLogger.error("Pasteboard claim missing payload id=\(id.uuidString, privacy: .public)")
            throw FinderImportError.unavailableRequest
        }
        pasteboard.clearContents()

        let request: FinderImportRequest
        do {
            request = try JSONDecoder().decode(FinderImportRequest.self, from: data)
        } catch {
            let nsError = error as NSError
            finderHandoffLogger.error("Pasteboard decode failed id=\(id.uuidString, privacy: .public) bytes=\(data.count, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            throw FinderImportError.invalidRequest
        }
        guard request.version == FinderImportRequest.currentVersion, request.id == id, !request.entries.isEmpty else {
            finderHandoffLogger.error("Pasteboard request invalid id=\(id.uuidString, privacy: .public) version=\(request.version, privacy: .public) entries=\(request.entries.count, privacy: .public)")
            throw FinderImportError.invalidRequest
        }
        let age = now().timeIntervalSince(request.createdAt)
        guard age <= Self.requestLifetime else {
            finderHandoffLogger.error("Pasteboard request expired id=\(id.uuidString, privacy: .public) age=\(age, privacy: .public)")
            throw FinderImportError.expiredRequest
        }
        finderHandoffLogger.info("Pasteboard claim succeeded id=\(id.uuidString, privacy: .public) entries=\(request.entries.count, privacy: .public) age=\(age, privacy: .public)")
        return request
    }

    private static func name(for id: UUID) -> NSPasteboard.Name {
        NSPasteboard.Name("com.multitrackcleaner.finder-import.\(id.uuidString)")
    }
}

final class SecurityScopeLease: @unchecked Sendable {
    private var scopedURLs: [URL]

    init(scopedURLs: [URL]) {
        self.scopedURLs = scopedURLs
    }

    func release() {
        let urls = scopedURLs
        scopedURLs = []
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    deinit {
        release()
    }
}

struct ResolvedFinderImport: Sendable {
    let selection: FinderSelection
    let lease: SecurityScopeLease
}

struct FinderImportResolver {
    private let selectionFilter: FinderSelectionFilter

    init(selectionFilter: FinderSelectionFilter = FinderSelectionFilter()) {
        self.selectionFilter = selectionFilter
    }

    func resolve(_ request: FinderImportRequest) throws -> ResolvedFinderImport {
        finderBookmarkLogger.info("Bookmark resolution started id=\(request.id.uuidString, privacy: .public) entries=\(request.entries.count, privacy: .public)")
        var scopedURLs: [URL] = []
        var urls: [URL] = []
        do {
            for (index, entry) in request.entries.enumerated() {
                var isStale = false
                let url: URL
                do {
                    url = try URL(
                        resolvingBookmarkData: entry.bookmarkData,
                        options: [.withoutUI, .withoutImplicitStartAccessing],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                } catch {
                    let nsError = error as NSError
                    finderBookmarkLogger.error("Bookmark resolve failed id=\(request.id.uuidString, privacy: .private) index=\(index, privacy: .private) name=\(entry.displayName, privacy: .private) domain=\(nsError.domain, privacy: .private) code=\(nsError.code, privacy: .private)")
                    throw error
                }
                guard !isStale, FileManager.default.fileExists(atPath: url.path) else {
                    finderBookmarkLogger.error("Bookmark unavailable id=\(request.id.uuidString, privacy: .private) index=\(index, privacy: .private) stale=\(isStale, privacy: .private) path=\(url.path, privacy: .private)")
                    throw FinderImportError.unavailableItem(entry.displayName)
                }

                guard url.startAccessingSecurityScopedResource() else {
                    finderBookmarkLogger.error("Security scope denied id=\(request.id.uuidString, privacy: .private) index=\(index, privacy: .private) path=\(url.path, privacy: .private)")
                    throw FinderImportError.accessDenied(entry.displayName)
                }
                finderBookmarkLogger.info("Bookmark resolved id=\(request.id.uuidString, privacy: .private) index=\(index, privacy: .private) path=\(url.path, privacy: .private)")
                scopedURLs.append(url)
                urls.append(url)
            }
            let selection = try selectionFilter.filter(urls: urls)
            finderBookmarkLogger.info("Bookmark resolution succeeded id=\(request.id.uuidString, privacy: .public) selected=\(selection.urls.count, privacy: .public)")
            return ResolvedFinderImport(selection: selection, lease: SecurityScopeLease(scopedURLs: scopedURLs))
        } catch {
            finderBookmarkLogger.info("Bookmark resolution cleaning up scopes id=\(request.id.uuidString, privacy: .public) count=\(scopedURLs.count, privacy: .public)")
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
}

@MainActor
final class ApplicationInputRouter: ObservableObject {
    @Published private(set) var pendingImport: ResolvedFinderImport?
    @Published private(set) var errorMessage: String?

    private let pasteboard: FinderImportPasteboard
    private let resolver: FinderImportResolver

    init(
        pasteboard: FinderImportPasteboard = FinderImportPasteboard(),
        resolver: FinderImportResolver = FinderImportResolver()
    ) {
        self.pasteboard = pasteboard
        self.resolver = resolver
    }

    func receive(url: URL) {
        finderHandoffLogger.info("Main app received URL scheme=\(url.scheme ?? "<nil>", privacy: .private) host=\(url.host ?? "<nil>", privacy: .private) path=\(url.path, privacy: .private)")
        do {
            let requestID = try parseRequestID(from: url)
            let request = try pasteboard.claim(id: requestID)
            pendingImport = try resolver.resolve(request)
            finderHandoffLogger.info("Main app published Finder import id=\(requestID.uuidString, privacy: .public) selected=\(self.pendingImport?.selection.urls.count ?? 0, privacy: .public)")
            errorMessage = nil
        } catch {
            let nsError = error as NSError
            let label = (error as? FinderImportError)?.diagnosticLabel ?? "underlyingError"
            finderHandoffLogger.error("Main app handoff failed stage=receive label=\(label, privacy: .private) domain=\(nsError.domain, privacy: .private) code=\(nsError.code, privacy: .private) description=\(error.localizedDescription, privacy: .private)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func consumePendingImport() -> ResolvedFinderImport? {
        defer { pendingImport = nil }
        return pendingImport
    }

    func discardPendingImport() {
        pendingImport?.lease.release()
        pendingImport = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func parseRequestID(from url: URL) throws -> UUID {
        guard url.scheme == "multitrackcleaner", url.host == "import" else { throw FinderImportError.invalidLink }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1, let id = UUID(uuidString: components[0]) else { throw FinderImportError.invalidLink }
        return id
    }
}
