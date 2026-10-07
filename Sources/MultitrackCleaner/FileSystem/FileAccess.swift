import Foundation

protocol FileAccess {
    func fileExists(at url: URL) -> Bool
    func moveItem(at sourceURL: URL, to targetURL: URL) throws
}

struct LocalFileAccess: FileAccess {
    private let fileManager = FileManager.default

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func moveItem(at sourceURL: URL, to targetURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: targetURL)
    }
}
