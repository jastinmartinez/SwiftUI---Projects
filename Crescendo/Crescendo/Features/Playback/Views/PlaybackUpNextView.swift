import SwiftUI

/// Displays the confirmed tracks that follow the current queue item.
///
/// The model already contains the effective order, so this view owns only layout.
struct PlaybackUpNextView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title)
                .font(.headline)

            ForEach(model.tracks) { track in
                TrackRowView(model: track)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PlaybackUpNextView {
    /// The localized title and ordered track rows rendered by Up Next.
    struct Model: Equatable {
        let title: String
        let tracks: [TrackRowView.Model]
    }
}
