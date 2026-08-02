import ComposableArchitecture

/// Adapts confirmed Library and loading facts into the overview presentation.
///
/// The adapter owns Store-to-model projection and action mapping only. It does
/// not render, present the picker, persist data, or control playback.
extension LibraryOverviewView.Model {
    /// Projects confirmed Library facts and feature actions into the overview.
    @MainActor
    init(_ store: StoreOf<LibraryReducer>) {
        let loadingPresentation: LoadingPresentation
        switch (store.loadStatus, store.library.items.isEmpty) {
        case (.idle, true), (.loading, true):
            loadingPresentation = .initial
        case (.loading, false):
            loadingPresentation = .refreshing
        case (.idle, false),
            (.loaded, _),
            (.recoveredWithCatalogFailure, _),
            (.failed, _):
            loadingPresentation = .hidden
        }

        self.init(
            songCount: store.library.items.count,
            albumCount: store.library.albumCount,
            recentlyAdded: store.library.recentlyAdded.prefix(5).map { item in
                LibraryTrackRowView.Model(item) { trackID in
                    store.send(.trackTapped(trackID))
                }
            },
            isEmpty: store.library.items.isEmpty,
            isImportEnabled: store.isImportAvailable,
            loadingPresentation: loadingPresentation,
            strings: .init(
                title: Locs.Library.title,
                songs: Locs.Library.songs,
                albums: Locs.Library.albums,
                recentlyAdded: Locs.Library.recentlyAdded,
                importMusic: Locs.Library.importMusic,
                emptyTitle: Locs.Library.emptyTitle,
                emptyMessage: Locs.Library.emptyMessage,
                loading: Locs.Library.loading
            ),
            onImport: { store.send(.importButtonTapped) },
            onOpenSongs: { store.send(.destinationTapped(.songs)) }
        )
    }
}
