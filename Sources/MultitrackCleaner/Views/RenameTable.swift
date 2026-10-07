import SwiftUI

struct RenameTable: View {
    @ObservedObject var model: RenamePreviewViewModel
    @EnvironmentObject private var copy: AppLocalization

    var body: some View {
        List {
            HStack(spacing: 12) {
                Toggle(copy.text("select.all"), isOn: Binding(
                    get: { !model.proposals.isEmpty && model.selectedIDs.count == model.proposals.count },
                    set: { model.selectAll($0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 20)
                Text("#")
                    .font(.caption)
                    .frame(width: 24, alignment: .trailing)
                Text(copy.text("original")).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").frame(width: 18)
                Text(copy.text("newName")).frame(maxWidth: .infinity, alignment: .leading)
                Text(copy.text("status")).frame(width: 88, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if model.proposals.isEmpty {
                Text(copy.text("empty.detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            }

            ForEach(Array(model.proposals.enumerated()), id: \.element.id) { index, proposal in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { model.selectedIDs.contains(proposal.id) },
                            set: { model.setSelected($0, id: proposal.id) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .frame(width: 20)
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(proposal.originalFilename)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 18)
                        TextField(copy.text("name.placeholder"), text: Binding(
                            get: { proposal.proposedFilename },
                            set: { model.updateProposal(id: proposal.id, name: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        Text(statusTitle(proposal.status))
                            .foregroundStyle(statusColor(proposal.status))
                            .frame(width: 88, alignment: .leading)
                    }
                    if let message = proposal.validationMessage {
                        Text(copy.userMessage(message)).font(.caption).foregroundStyle(.red)
                    } else if !proposal.reasons.isEmpty {
                        Text(copy.text("reason.label") + ": " + proposal.reasons.map(reasonTitle).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay {
            if model.isLoading {
                ProgressView(copy.text("state.processing"))
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func statusColor(_ status: RenameStatus) -> Color {
        switch status {
        case .conflict, .invalid: .red
        case .manual: .blue
        case .proposed: .green
        case .unchanged: .secondary
        }
    }

    private func statusTitle(_ status: RenameStatus) -> String {
        switch status {
        case .unchanged: copy.text("status.unchanged")
        case .proposed: copy.text("status.proposed")
        case .manual: copy.text("status.manual")
        case .conflict: copy.text("status.conflict")
        case .invalid: copy.text("status.invalid")
        }
    }

    private func reasonTitle(_ reason: RenameReason) -> String {
        switch reason {
        case .numericPrefix: copy.text("reason.track")
        case .commonLeftSegment(let value): copy.text("reason.left", value)
        case .commonRightSegment(let value): copy.text("reason.right", value)
        case .normalizedInstrument(let value): copy.text("reason.instrument", value)
        case .capitalizedName: copy.text("reason.capitalize")
        case .collisionNumber(let value): copy.text("reason.collision", value)
        case .manual: copy.text("reason.manual")
        case .ambiguous: copy.text("reason.ambiguous")
        }
    }
}
