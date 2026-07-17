import SwiftUI

struct ProviderSelectionView: View {
    let model: Model

    var body: some View {
        AccessibilityLayoutReader { layout in
            Menu {
                ForEach(model.providers, id: \.id) { provider in
                    Button {
                        model.onSelect(provider.id)
                    } label: {
                        Label {
                            Text(provider.name)
                        } icon: {
                            if provider.id == model.activeProviderID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .accessibilityHidden(true)
                    Text(model.activeProviderName ?? Locs.ProviderSelection.title)
                        .lineLimit(layout == .expanded ? 2 : 1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(.tint.opacity(0.1), in: Capsule())
            }
            .disabled(!model.isSelectionEnabled || model.providers.isEmpty)
            .accessibilityLabel(Locs.ProviderSelection.title)
            .accessibilityValue(model.accessibilityValue)
        }
    }
}

extension ProviderSelectionView {
    struct Model {
        let providers: [MusicProviderDescriptor]
        let activeProviderID: MusicProviderID?
        let isSelectionEnabled: Bool
        let onSelect: (MusicProviderID) -> Void

        var activeProviderName: String? {
            providers.first { $0.id == activeProviderID }?.name
        }

        var accessibilityValue: String {
            activeProviderName ?? Locs.ProviderSelection.noActiveProvider
        }
    }
}
