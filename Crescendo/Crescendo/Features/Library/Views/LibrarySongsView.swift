import SwiftUI

/// Renders the complete confirmed Songs collection supplied by its model.
///
/// The view owns destination layout only. It does not hold a Store, sort the
/// Library, localize values, navigate, resolve files, or control playback.
struct LibrarySongsView: View {
    let model: Model

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.tracks) { track in
                    LibraryTrackRowView(model: track)

                    if track.id != model.tracks.last?.id {
                        Divider()
                            .padding(.leading, 88)
                    }
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(model.strings.title)
    }
}

extension LibrarySongsView {
    /// The immutable presentation contract for the Songs destination.
    struct Model {
        let tracks: [LibraryTrackRowView.Model]
        let strings: Strings
    }
}

extension LibrarySongsView.Model {
    /// Contains every localized string rendered by the Songs destination.
    struct Strings: Equatable {
        let title: String
    }
}
