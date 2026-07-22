import SwiftUI

/// Renders an icon-only primary-row control from an immutable model.
struct PlaybackIconButtonView: View {
    let model: Model

    var body: some View {
        Button(action: model.perform) {
            Image(systemName: model.systemImage)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityLabel)
        .disabled(!model.isEnabled)
    }
}

extension PlaybackIconButtonView {
    /// Contains every value required to render one icon-only control.
    struct Model {
        let systemImage: String
        let accessibilityLabel: String
        let isEnabled: Bool
        let perform: () -> Void
    }
}
