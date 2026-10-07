import Foundation

struct FileScanner {
    enum ScanError: LocalizedError {
        case unreadable(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url): "Could not read \(url.lastPathComponent)."
            }
        }
    }

    func scan(urls: [URL]) throws -> [AudioFile] {
        var fileURLs: [URL] = []
        let manager = FileManager.default

        for input in urls {
            let canonical = input.standardizedFileURL.resolvingSymlinksInPath()
            let values = try? canonical.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                let children = try manager.contentsOfDirectory(
                    at: canonical,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                fileURLs.append(contentsOf: children.filter { child in
                    let childValues = try? child.resourceValues(forKeys: [.isRegularFileKey])
                    return childValues?.isRegularFile == true && child.pathExtension.caseInsensitiveCompare("wav") == .orderedSame
                })
            } else if values?.isRegularFile == true, canonical.pathExtension.caseInsensitiveCompare("wav") == .orderedSame {
                fileURLs.append(canonical)
            }
        }

        let unique = Dictionary(grouping: fileURLs, by: { $0.standardizedFileURL.path }).compactMap { $0.value.first }
        return unique
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { AudioFile(url: $0, originalFilename: $0.lastPathComponent) }
    }
}
