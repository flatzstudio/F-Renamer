import SwiftUI
import AppKit

struct MainWindow: View {
    @StateObject private var model = RenamePreviewViewModel()
    @EnvironmentObject private var inputRouter: ApplicationInputRouter
    @EnvironmentObject private var copy: AppLocalization
    @State private var showReplaceConfirmation = false
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 10) {
            header
            DropZone { model.loadAdditional(urls: $0) }
            HStack(spacing: 8) {
                Button(action: chooseFolder) { Label(copy.text("import.folder"), systemImage: "folder") }
                Button(action: chooseFiles) { Label(copy.text("import.files"), systemImage: "waveform") }
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small)
                    Text(copy.text("state.scanning"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(copy.text(model.files.count == 1 ? "files.count.one" : "files.count", model.files.count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let source = model.inputSource {
                            Text(copy.text("source", source))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.text("preview.title")).font(.headline)
                    Text(copy.text(model.isLoading ? "state.processing" : "state.ready"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.files.isEmpty {
                    Button(copy.text("action.clear"), role: .destructive) { model.load(urls: []) }
                        .buttonStyle(.plain)
                        .disabled(model.isLoading)
                }
            }
            RenameTable(model: model)

            if let message = model.userMessage {
                Text(copy.userMessage(message))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(model.validationIssues.isEmpty ? Color.secondary : Color.red)
                    .lineLimit(2)
            }

            footer
        }
        .padding(16)
        .frame(width: 720, height: 720)
        .onReceive(inputRouter.$pendingImport) { pendingImport in
            guard pendingImport != nil else { return }
            if model.hasManualEdits { showReplaceConfirmation = true }
            else { applyPendingFinderImport() }
        }
        .alert(copy.text("replace.title"), isPresented: $showReplaceConfirmation) {
            Button(copy.text("replace.confirm"), role: .destructive) { applyPendingFinderImport() }
            Button(copy.text("replace.keep"), role: .cancel) { inputRouter.discardPendingImport() }
        } message: {
            Text(copy.text("replace.detail"))
        }
        .alert(copy.text("finder.title"), isPresented: Binding(
            get: { inputRouter.errorMessage != nil },
            set: { if !$0 { inputRouter.dismissError() } }
        )) {
            Button(copy.text("finder.ok"), role: .cancel) { inputRouter.dismissError() }
        } message: {
            Text(copy.userMessage(inputRouter.errorMessage ?? copy.text("finder.error")))
        }
        .sheet(isPresented: $showAbout) {
            aboutPanel.environmentObject(copy)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("F Renamer").font(.title2.weight(.bold))
                Text(copy.text("app.subtitle")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(copy.text("about.language"), selection: Binding(get: { copy.language }, set: { copy.setLanguage($0) })) {
                Text("EN").tag(AppLanguage.en)
                Text("RU").tag(AppLanguage.ru)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 92)
            Menu {
                Button(copy.text("action.about"), systemImage: "info.circle") { showAbout = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(copy.text("menu.title"))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(copy.text("action.capitalize"), action: model.capitalizeSelected)
                .disabled(model.selectedIDs.isEmpty || model.isLoading)
            Spacer()
            Button {
                Task { await model.rename() }
            } label: {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(copy.text("action.rename", model.selectedRenameCount))
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRename)
        }
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path").font(.system(size: 26)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("F Renamer").font(.title2.bold())
                    Text(copy.text("about.version")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(copy.text("about.close")) { showAbout = false }
            }
            Text(copy.text("about.description")).fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(copy.text("about.developer"), value: "Maxim Koldaev")
                LabeledContent(copy.text("about.studio"), value: "FLATZ Studio")
                HStack {
                    Text(copy.text("about.telegram"))
                    Spacer()
                    Link("t.me/producermaxim", destination: URL(string: "https://t.me/producermaxim")!)
                }
                Text(copy.text("about.copyright"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text(copy.text("about.language")).font(.caption).foregroundStyle(.secondary)
            Picker(copy.text("about.language"), selection: Binding(get: { copy.language }, set: { copy.setLanguage($0) })) {
                Text("EN").tag(AppLanguage.en)
                Text("RU").tag(AppLanguage.ru)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 110)
        }
        .padding(24)
        .frame(width: 440)
    }

    private func applyPendingFinderImport() {
        guard let finderImport = inputRouter.consumePendingImport() else { return }
        model.load(finderImport: finderImport)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = copy.text("panel.open")
        if panel.runModal() == .OK { model.load(urls: panel.urls) }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.wav]
        panel.prompt = copy.text("panel.open")
        if panel.runModal() == .OK { model.load(urls: panel.urls) }
    }
}
