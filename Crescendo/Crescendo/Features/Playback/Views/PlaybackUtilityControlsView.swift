import SwiftUI

/// Renders secondary playback actions in the approved utility rail.
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
                        minWidth: 64,
                        maxWidth: 64,
                        minHeight: 64
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(control.accessibilityLabel)
                .disabled(!control.isEnabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

extension PlaybackUtilityControlsView {
    struct Model {
        let controls: [Control]
    }
}

extension PlaybackUtilityControlsView.Model {
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
    enum ID: Hashable {
        case restart
        case stop
    }
}
