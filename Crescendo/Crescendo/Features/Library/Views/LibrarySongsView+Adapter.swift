import ComposableArchitecture

/// Adapts the confirmed Library order into the Songs presentation contract.
///
/// The adapter owns Store-to-model projection only. It does not render, sort,
/// navigate, resolve files, or control playback.
extension LibrarySongsView.Model {
    /// Projects the confirmed Library order and row actions for Songs.
    @MainActor
    init(_ store: StoreOf<LibraryReducer>) {
        self.init(
            tracks: store.library.items.map { item in
                LibraryTrackRowView.Model(item) { trackID in
                    store.send(.trackTapped(trackID))
                }
            },
            strings: .init(title: Locs.Library.songs)
        )
    }
}
