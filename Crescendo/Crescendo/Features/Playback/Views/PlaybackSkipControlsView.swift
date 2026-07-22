import SwiftUI

/// Renders the homogeneous backward and forward timeline actions.
struct PlaybackSkipControlsView: View {
    let model: Model

    var body: some View {
        HStack {
            Spacer()
            ForEach(model.controls) { control in
                Button(action: control.perform) {
                    Image(systemName: control.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(LinearGradient.crescendoSpectrum)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(control.accessibilityLabel)
                .disabled(!control.isEnabled)
                Spacer()
            }
        }
    }
}

extension PlaybackSkipControlsView {
    struct Model {
        let controls: [Control]
    }
}

extension PlaybackSkipControlsView.Model {
    struct Control: Identifiable {
        let id: ID
        let systemImage: String
        let accessibilityLabel: String
        let isEnabled: Bool
        let perform: () -> Void
    }
}

extension PlaybackSkipControlsView.Model.Control {
    enum ID: Hashable {
        case backward
        case forward
    }
}
