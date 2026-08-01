import ComposableArchitecture
import Foundation

/// Owns the confirmed Library, Library navigation, and feature-level routing.
///
/// The reducer starts catalog/media loading, preserves confirmed contents while
/// loading or after failure, accepts completed recovery delegates, presents the
/// file importer, routes selected files through the import child, and delegates
/// valid track selections. It does not reconcile files, perform persistence,
/// import individual media items, control playback, select tabs, localize text,
/// or render views.
@Reducer
struct LibraryReducer {
    @ObservableState
    struct State: Equatable {
        var library: Library
        var catalog: LibraryCatalogClient.Snapshot
        var loadStatus: LoadStatus
        var path: [Destination]
        var isFileImporterPresented: Bool
        var recovery: LibraryRecoveryReducer.State?
        var importBatch: LibraryImportReducer.State?
        var fileSelectionFailure: LibraryFailure?
    }

    enum Action: Equatable {
        case task
        case retryButtonTapped
        case libraryLoadCompleted(
            catalog: Result<
                LibraryCatalogClient.Snapshot,
                LibraryFailure
            >,
            storedAudio: Result<
                [LibraryMediaStoreClient.StoredAudio],
                LibraryFailure
            >
        )
        case importButtonTapped
        case setFileImporterPresented(Bool)
        case filesSelected([URL])
        case fileSelectionFailed(LibraryFailure)
        case cancelImportButtonTapped
        case destinationTapped(Destination)
        case pathChanged([Destination])
        case trackTapped(TrackID)
        case recovery(LibraryRecoveryReducer.Action)
        case importBatch(LibraryImportReducer.Action)
        case delegate(Delegate)
    }

    private enum CancelID {
        case load
    }

    @Dependency(\.libraryCatalog) private var libraryCatalog
    @Dependency(\.libraryMediaStore) private var libraryMediaStore

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.loadStatus = .loading
                state.recovery = nil
                return .run { send in
                    async let catalogLoad = libraryCatalog.load()
                    async let storedAudioLoad = libraryMediaStore.listStoredAudio()
                    let (catalog, storedAudio) = await (
                        catalogLoad,
                        storedAudioLoad
                    )
                    await send(
                        .libraryLoadCompleted(
                            catalog: catalog,
                            storedAudio: storedAudio
                        )
                    )
                }
                .cancellable(
                    id: CancelID.load,
                    cancelInFlight: true
                )

            case .retryButtonTapped:
                return .send(.task)

            case .importButtonTapped:
                state.isFileImporterPresented = true
                state.fileSelectionFailure = nil
                return .none

            case let .setFileImporterPresented(isPresented):
                state.isFileImporterPresented = isPresented
                return .none

            case let .filesSelected(sources):
                state.isFileImporterPresented = false
                state.fileSelectionFailure = nil
                guard !sources.isEmpty else { return .none }
                state.importBatch = LibraryImportReducer.State(
                    sources: sources,
                    library: state.library,
                    catalog: state.catalog
                )
                return .send(.importBatch(.start))

            case let .fileSelectionFailed(failure):
                state.isFileImporterPresented = false
                state.fileSelectionFailure = failure
                return .none

            case .cancelImportButtonTapped:
                guard state.importBatch != nil else { return .none }
                return .send(.importBatch(.cancelButtonTapped))

            case let .destinationTapped(destination):
                state.path.append(destination)
                return .none

            case let .pathChanged(path):
                state.path = path
                return .none

            case let .trackTapped(trackID):
                guard let item = state.library.items[id: trackID] else {
                    return .none
                }
                return .send(
                    .delegate(
                        .trackTapped(
                            item.track,
                            loadedTracks: IdentifiedArray(
                                uniqueElements: state.library.items.map(
                                    \.track
                                )
                            )
                        )
                    )
                )

            case let .libraryLoadCompleted(_, .failure(failure)):
                state.loadStatus = .failed(failure)
                return .none

            case let .libraryLoadCompleted(
                catalog,
                .success(storedAudio)
            ):
                state.recovery = LibraryRecoveryReducer.State(
                    catalog: catalog,
                    storedAudio: storedAudio
                )
                return .send(.recovery(.start))

            case let .recovery(.delegate(.completed(completion))):
                state.recovery = nil
                state.library = completion.library
                state.catalog = completion.catalog
                if let catalogWriteFailure = completion.catalogWriteFailure {
                    state.loadStatus = .recoveredWithCatalogFailure(
                        catalogWriteFailure
                    )
                } else {
                    state.loadStatus = .loaded
                }
                return .none

            case let .recovery(.delegate(.failed(failure))):
                state.recovery = nil
                state.loadStatus = .failed(failure)
                return .none

            case let .importBatch(.delegate(.completed(completion))),
                let .importBatch(.delegate(.cancelled(completion))):
                state.library = completion.library
                state.catalog = completion.catalog
                return .none

            case .recovery, .importBatch, .delegate:
                return .none
            }
        }
        .ifLet(\.recovery, action: \.recovery) {
            LibraryRecoveryReducer()
        }
        .ifLet(\.importBatch, action: \.importBatch) {
            LibraryImportReducer()
        }
    }
}
