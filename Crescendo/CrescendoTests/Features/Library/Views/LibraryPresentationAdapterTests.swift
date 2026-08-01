import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

/// Proves Library projection, localization fallback, ordering, and UI routing.
@MainActor
struct LibraryPresentationAdapterTests {
    @Test
    func emptyOverviewProjectsCountsAndEmptyState() {
        let model = LibraryOverviewView.Model(makeStore())

        #expect(model.songCount == 0)
        #expect(model.albumCount == 0)
        #expect(model.recentlyAdded.isEmpty)
        #expect(model.isEmpty)
    }

    @Test
    func overviewProjectsCountsAndFiveMostRecentlyAddedItems() {
        let items = [
            makeItem(index: 1, albumTitle: "First Album"),
            makeItem(index: 2, albumTitle: "first album"),
            makeItem(index: 3, albumTitle: "Second Album"),
            makeItem(index: 4, albumTitle: nil),
            makeItem(index: 5, albumTitle: "Third Album"),
            makeItem(index: 6, albumTitle: "   "),
            makeItem(index: 7, albumTitle: "Third Album"),
        ]
        let model = LibraryOverviewView.Model(
            makeStore(library: Library(items: .init(uniqueElements: items)))
        )

        #expect(model.songCount == 7)
        #expect(model.albumCount == 3)
        #expect(model.recentlyAdded.map(\.id) == items.reversed().prefix(5).map(\.id))
        #expect(!model.isEmpty)
    }

    @Test
    func overviewRoutesImportAndSongsActions() {
        let store = makeStore()
        let model = LibraryOverviewView.Model(store)

        model.onImport()
        #expect(store.isFileImporterPresented)

        model.onOpenSongs()
        #expect(store.path == [.songs])
    }

    @Test
    func rowProjectsLocalizedFallbacksAndSelection() {
        let selectedID = LockIsolated<TrackID?>(nil)
        let item = makeItem(
            index: 1,
            artistName: nil,
            albumTitle: "   "
        )
        let model = LibraryTrackRowView.Model(item) { trackID in
            selectedID.setValue(trackID)
        }

        #expect(model.title == item.track.title)
        #expect(model.artist == Locs.Common.unknownArtist)
        #expect(model.album == Locs.Library.unknownAlbum)
        #expect(model.artworkURL == item.track.artworkURL)

        model.onTap()
        #expect(selectedID.value == item.id)
    }

    @Test
    func songsPreserveConfirmedLibraryOrder() {
        let items = [
            makeItem(index: 2),
            makeItem(index: 1),
            makeItem(index: 3),
        ]
        let model = LibrarySongsView.Model(
            makeStore(library: Library(items: .init(uniqueElements: items)))
        )

        #expect(model.tracks.map(\.id) == items.map(\.id))
        #expect(model.strings.title == Locs.Library.songs)
    }

    @Test
    func importingSummaryProjectsProgressAndRoutesCancellation() async {
        let sources = [
            URL(fileURLWithPath: "/external/One.m4a"),
            URL(fileURLWithPath: "/external/Two.m4a"),
        ]
        var importBatch = makeImportBatch(sources: sources)
        importBatch.lifecycle = .importing(
            .init(
                sources: sources,
                nextIndex: 1,
                importedCount: 1,
                duplicateCount: 0,
                issues: []
            )
        )
        let store = makeStore(importBatch: importBatch)
        let model = LibraryImportSummaryView.Model(store)

        #expect(model?.title == Locs.Library.Import.importing)
        #expect(model?.detail == "Importing 2 of 2")
        #expect(model?.cancelTitle == Locs.Library.Import.cancel)

        model?.onCancel?()
        await Task.yield()

        guard case .cancelled = store.importBatch?.lifecycle else {
            Issue.record("Expected cancellation to reach the import child")
            return
        }
    }

    @Test
    func completedSummaryPluralizesCountsAndProjectsIssues() {
        let summary = LibraryImportReducer.Summary(
            importedCount: 2,
            duplicateCount: 1,
            issues: [
                .init(
                    id: UUID(0),
                    sourceName: "Broken.m4a",
                    failure: .metadataReadFailed
                )
            ]
        )
        var importBatch = makeImportBatch()
        importBatch.lifecycle = .completed(summary)
        importBatch.phase = .completed
        let model = LibraryImportSummaryView.Model(
            makeStore(importBatch: importBatch)
        )

        #expect(model?.title == Locs.Library.Import.completed)
        #expect(model?.detail == "2 songs imported · 1 duplicate skipped")
        #expect(
            model?.issueMessages == [
                "Broken.m4a: Metadata could not be read."
            ]
        )
        #expect(model?.cancelTitle == nil)
        #expect(model?.onCancel == nil)
    }

    @Test
    func cancelledSummaryDescribesPartialImport() {
        let summary = LibraryImportReducer.Summary(
            importedCount: 1,
            duplicateCount: 2,
            issues: []
        )
        var importBatch = makeImportBatch()
        importBatch.lifecycle = .cancelled(summary)
        importBatch.phase = .completed
        let model = LibraryImportSummaryView.Model(
            makeStore(importBatch: importBatch)
        )

        #expect(model?.title == Locs.Library.Import.cancelled)
        #expect(
            model?.detail
                == "1 song imported before cancellation · 2 duplicates skipped"
        )
    }

    @Test
    func pickerFailureProjectsWithoutAnImportBatch() {
        let model = LibraryImportSummaryView.Model(
            makeStore(fileSelectionFailure: .fileReadFailed)
        )

        #expect(model?.title == Locs.Library.Import.failed)
        #expect(model?.detail == "The selected files could not be read.")
        #expect(model?.issueMessages.isEmpty == true)
    }
}

private extension LibraryPresentationAdapterTests {
    func makeStore(
        library: Library = Library(items: []),
        importBatch: LibraryImportReducer.State? = nil,
        fileSelectionFailure: LibraryFailure? = nil
    ) -> StoreOf<LibraryReducer> {
        Store(
            initialState: LibraryReducer.State(
                library: library,
                catalog: .init(entries: []),
                loadStatus: .idle,
                path: [],
                isFileImporterPresented: false,
                recovery: nil,
                importBatch: importBatch,
                fileSelectionFailure: fileSelectionFailure
            )
        ) {
            LibraryReducer()
        }
    }

    func makeImportBatch(
        sources: [URL] = []
    ) -> LibraryImportReducer.State {
        LibraryImportReducer.State(
            sources: sources,
            library: Library(items: []),
            catalog: .init(entries: [])
        )
    }

    func makeItem(
        index: Int,
        artistName: String? = "Artist",
        albumTitle: String? = "Album"
    ) -> Library.Item {
        let trackID = TrackID(
            providerID: .library,
            nativeID: String(index)
        )
        return Library.Item(
            track: Track(
                id: trackID,
                title: "Song \(index)",
                artistName: artistName,
                albumTitle: albumTitle,
                artworkURL: URL(
                    string: "https://example.com/\(index).jpg"
                ),
                duration: 30,
                playbackURL: URL(
                    fileURLWithPath: "/managed/\(index).m4a"
                )
            ),
            contentIdentity: .init(rawValue: "content-\(index)"),
            addedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index))
        )
    }
}
