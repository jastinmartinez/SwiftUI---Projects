import SwiftUI

/// Displays the ordered set of discrete timeline-navigation actions.
///
/// Every control carries its own identity, symbol, availability, accessibility
/// label, and callback, so the view does not infer reducer behavior.
struct PlaybackSkipControlsView: View {
    let model: Model

    var body: some View {
        HStack {
            Spacer()
            ForEach(model.controls) { control in
                Button {
                    guard control.availability.isEnabled else { return }
                    control.perform()
                } label: {
                    Image(systemName: control.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(LinearGradient.crescendoSpectrum)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(control.accessibilityLabel)
                .playbackControlAvailability(control.availability)
                Spacer()
            }
        }
    }
}

extension PlaybackSkipControlsView {
    /// The ordered timeline controls rendered by the view.
    struct Model {
        let controls: [Control]
    }
}

extension PlaybackSkipControlsView.Model {
    /// The immutable presentation and behavior for one timeline action.
    struct Control: Identifiable {
        let id: ID
        let systemImage: String
        let accessibilityLabel: String
        let availability: PlaybackCommandPolicy.Availability
        let perform: () -> Void

        var isEnabled: Bool {
            availability.isEnabled
        }
    }
}

extension PlaybackSkipControlsView.Model.Control {
    /// Stable identities for the supported timeline actions.
    enum ID: Hashable {
        case backward
        case forward
    }
}
