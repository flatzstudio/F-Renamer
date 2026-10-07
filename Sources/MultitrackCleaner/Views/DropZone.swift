import SwiftUI

struct DropZone: View {
    let onURLs: ([URL]) -> Void
    let compact: Bool
    @EnvironmentObject private var copy: AppLocalization
    @State private var isTargeted = false

    init(compact: Bool = false, onURLs: @escaping ([URL]) -> Void) {
        self.compact = compact
        self.onURLs = onURLs
    }

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: compact ? 20 : 27, weight: .regular))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 5) {
                Text(copy.text(compact ? "drop.more" : "drop.title"))
                    .font(.headline)
                Text(copy.text("drop.detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 64 : 136)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.28), style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5])))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: FinderAttachmentURLExtractor.supportedTypeIdentifiers, isTargeted: $isTargeted) { providers in
            let acceptedProviders = providers.filter { provider in
                provider.registeredTypeIdentifiers.contains { FinderAttachmentURLExtractor.supportedTypeIdentifiers.contains($0) }
            }
            guard !acceptedProviders.isEmpty else { return false }
            loadURLs(from: acceptedProviders)
            return true
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    FinderAttachmentURLExtractor().loadURL(from: provider) { url, _ in
                        continuation.resume(returning: url)
                    }
                }
                if let url { urls.append(url) }
            }
            if !urls.isEmpty { onURLs(urls) }
        }
    }
}
