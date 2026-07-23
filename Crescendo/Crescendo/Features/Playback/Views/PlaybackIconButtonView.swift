import SwiftUI

/// Displays one icon-only action in the primary playback row.
///
/// The model supplies the symbol, accessibility label, availability, and callback
/// so this reusable component remains stateless.
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
    /// The immutable presentation contract for one icon-only playback action.
    struct Model {
        let systemImage: String
        let accessibilityLabel: String
        let isEnabled: Bool
        let perform: () -> Void
    }
}
