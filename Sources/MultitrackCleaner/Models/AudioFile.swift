import Foundation

struct AudioFile: Identifiable, Hashable, Sendable {
    let url: URL
    let originalFilename: String

    var id: URL { url }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    var fileExtension: String { url.pathExtension }
}
