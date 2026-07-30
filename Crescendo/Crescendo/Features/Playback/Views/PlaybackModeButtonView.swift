import SwiftUI

/// Renders a playback-mode control with visible and accessible selection state.
///
/// The immutable model supplies all presentation values and the callback, leaving
/// this component free of playback and interaction state.
struct PlaybackModeButtonView: View {
    let model: Model

    var body: some View {
        Button {
            guard model.availability.isEnabled else { return }
            model.perform()
        } label: {
            Image(systemName: model.systemImage)
                .font(.title2)
                .foregroundStyle(
                    model.isSelected
                        ? AnyShapeStyle(LinearGradient.crescendoSpectrum)
                        : AnyShapeStyle(.primary)
                )
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
        .accessibilityAddTraits(model.isSelected ? .isSelected : [])
        .playbackControlAvailability(model.availability)
    }
}

extension PlaybackModeButtonView {
    /// The immutable presentation and accessibility contract for a mode action.
    struct Model {
        let systemImage: String
        let accessibilityLabel: String
        let accessibilityValue: String
        let isSelected: Bool
        let availability: PlaybackCommandPolicy.Availability
        let perform: () -> Void

        var isEnabled: Bool {
            availability.isEnabled
        }
    }
}
