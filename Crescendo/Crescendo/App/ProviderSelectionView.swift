import SwiftUI

struct ProviderSelectionView: View {
    let model: Model

    var body: some View {
        AccessibilityLayoutReader { layout in
            providerMenu(layout: layout)
        }
    }

    // MARK: - Views

    private func providerMenu(layout: AccessibilityLayout) -> some View {
        Menu {
            Section(model.menuTitle) {
                ForEach(model.providerRows) { row in
                    Button(action: row.onSelect) {
                        HStack(spacing: 10) {
                            Image("AppleMusicProviderIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                if let statusLabel = row.statusLabel {
                                    Text(statusLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if row.isSelected {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .disabled(!row.isEnabled)
                }

                if let recoveryAction = model.recoveryAction {
                    Button(recoveryAction.label, action: recoveryAction.perform)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image("AppleMusicProviderIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(model.collapsedLabel)
                    .lineLimit(layout == .expanded ? 2 : 1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Color.white, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.gray.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .disabled(!model.isSelectionEnabled || model.providerRows.isEmpty)
        .accessibilityLabel(model.menuTitle)
        .accessibilityValue(model.accessibilityValue)
    }
}

extension ProviderSelectionView {
    struct Model {
        enum Status: Equatable {
            case disconnected
            case connecting(providerName: String)
            case connected(providerName: String)
            case needsAccess(providerName: String)
            case restricted(providerName: String)
            case failed(providerName: String)
        }

        struct ProviderRow: Identifiable {
            let id: ProviderID
            let label: String
            let statusLabel: String?
            let isSelected: Bool
            let isEnabled: Bool
            let onSelect: @MainActor () -> Void
        }

        struct RecoveryAction {
            let label: String
            let perform: @MainActor () -> Void
        }

        let status: Status
        let collapsedLabel: String
        let menuTitle: String
        let providerRows: [ProviderRow]
        let recoveryAction: RecoveryAction?
        let isSelectionEnabled: Bool

        var activeProviderName: String? {
            switch status {
            case .disconnected:
                nil
            case .connecting(let providerName),
                .connected(let providerName),
                .needsAccess(let providerName),
                .restricted(let providerName),
                .failed(let providerName):
                providerName
            }
        }

        var connectedProviderName: String? {
            guard case .connected(let providerName) = status else { return nil }
            return providerName
        }

        var accessibilityValue: String {
            collapsedLabel
        }

        init(
            status: Status,
            collapsedLabel: String,
            menuTitle: String,
            providerRows: [ProviderRow],
            recoveryAction: RecoveryAction?,
            isSelectionEnabled: Bool
        ) {
            self.status = status
            self.collapsedLabel = collapsedLabel
            self.menuTitle = menuTitle
            self.providerRows = providerRows
            self.recoveryAction = recoveryAction
            self.isSelectionEnabled = isSelectionEnabled
        }

    }
}
