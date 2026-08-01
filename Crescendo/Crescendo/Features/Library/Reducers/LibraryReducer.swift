import ComposableArchitecture

/// Owns the confirmed Library and coordinates its load and recovery child.
///
/// The reducer starts catalog/media loading, preserves confirmed contents while
/// loading or after failure, and accepts only completed recovery delegates. It
/// does not reconcile files, perform persistence, import media, control
/// playback, select tabs, localize text, or render views.
@Reducer
struct LibraryReducer {
    enum LoadStatus: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case recoveredWithCatalogFailure(LibraryFailure)
        case failed(LibraryFailure)
    }

    @ObservableState
    struct State: Equatable {
        var library: Library
        var loadStatus: LoadStatus
        var recovery: LibraryRecoveryReducer.State?
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
        case recovery(LibraryRecoveryReducer.Action)
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

            case let .recovery(
                .delegate(
                    .completed(library, catalogWriteFailure)
                )
            ):
                state.recovery = nil
                state.library = library
                if let catalogWriteFailure {
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

            case .recovery:
                return .none
            }
        }
        .ifLet(\.recovery, action: \.recovery) {
            LibraryRecoveryReducer()
        }
    }
}
