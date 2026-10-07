import AppKit
import UniformTypeIdentifiers

private final class URLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storedURLs.append(url)
        lock.unlock()
    }

    func urls() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedURLs
    }
}

private struct FinderURLProvider {
    let provider: NSItemProvider
}

final class FinderActionViewController: NSViewController {
    private let selectionFilter = FinderSelectionFilter()
    private var didStartImport = false

    override func loadView() {
        let label = NSTextField(labelWithString: "Opening in F Renamer…")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        view = label
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStartImport else { return }
        didStartImport = true
        importSelection()
    }

    private func importSelection() {
        guard let context = extensionContext else {
            return
        }
        let extensionItems = context.inputItems.compactMap { $0 as? NSExtensionItem }
        let attachments = extensionItems.flatMap { item in
            let itemAttachments = item.attachments ?? []
            return itemAttachments
        }
        let providers = attachments.compactMap { provider -> FinderURLProvider? in
            if provider.registeredTypeIdentifiers.contains(where: FinderAttachmentURLExtractor.supportedTypeIdentifiers.contains) {
                return FinderURLProvider(provider: provider)
            }
            return nil
        }

        guard !providers.isEmpty else {
            context.cancelRequest(withError: FinderImportError.noSupportedItems)
            return
        }

        let group = DispatchGroup()
        let loadedURLs = URLAccumulator()

        for descriptor in providers {
            let provider = descriptor.provider
            group.enter()
            FinderAttachmentURLExtractor().loadURL(from: provider) { url, _ in
                defer { group.leave() }
                if let url { loadedURLs.append(url) }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            do {
                let urls = loadedURLs.urls()
                let selection = try self.selectionFilter.filter(urls: urls)
                let entries = try selection.urls.map(self.makeEntry)
                let request = try FinderImportPasteboard().write(entries: entries)
                guard let url = URL(string: "multitrackcleaner://import/\(request.id.uuidString)") else {
                    throw FinderImportError.invalidLink
                }
                context.open(url) { success in
                    if success {
                        context.completeRequest(returningItems: nil)
                    } else {
                        context.cancelRequest(withError: FinderImportError.unavailableRequest)
                    }
                }
            } catch {
                context.cancelRequest(withError: error)
            }
        }
    }

    private func makeEntry(url: URL) throws -> FinderImportRequest.Entry {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .nameKey])
        guard values.isDirectory == true || (
            values.isRegularFile == true && url.pathExtension.caseInsensitiveCompare("wav") == .orderedSame
        ) else {
            throw FinderImportError.noSupportedItems
        }
        let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return FinderImportRequest.Entry(bookmarkData: bookmarkData, displayName: values.name ?? url.lastPathComponent)
    }

}
