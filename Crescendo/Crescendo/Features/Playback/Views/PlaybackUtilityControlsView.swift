import SwiftUI

/// Displays secondary playback actions in a divided, equal-width utility rail.
///
/// Control order and availability are supplied by the adapter. This view only
/// applies the shared utility presentation and forwards callbacks.
struct PlaybackUtilityControlsView: View {
    let model: Model

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.controls.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                        .frame(height: 48)
                }

                let control = model.controls[index]
                Button(action: control.perform) {
                    VStack(spacing: 6) {
                        Image(systemName: control.systemImage)
                            .font(.title3.weight(.semibold))
                        Text(control.title)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 64
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(control.accessibilityLabel)
                .disabled(!control.isEnabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

extension PlaybackUtilityControlsView {
    /// The ordered secondary actions rendered in the utility rail.
    struct Model {
        let controls: [Control]
    }
}

extension PlaybackUtilityControlsView.Model {
    /// The immutable presentation and behavior for one utility action.
    struct Control: Identifiable {
        let id: ID
        let systemImage: String
        let title: String
        let accessibilityLabel: String
        let isEnabled: Bool
        let perform: () -> Void
    }
}

extension PlaybackUtilityControlsView.Model.Control {
    /// Stable identities for the supported utility actions.
    enum ID: Hashable {
        case restart
        case stop
    }
}
