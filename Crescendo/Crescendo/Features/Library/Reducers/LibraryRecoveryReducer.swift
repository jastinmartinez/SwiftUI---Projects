import ComposableArchitecture
import IdentifiedCollections

/// Coordinates restoration of the complete Library from catalog and managed audio.
///
/// The reducer owns the temporary batch queues, starts one item-recovery child
/// at a time, collects its semantic results, and replaces the catalog when the
/// recovered membership changed. It does not recover individual items, own the
/// confirmed Library, import media, navigate, control playback, or implement
/// persistence mechanics.
@Reducer
struct LibraryRecoveryReducer {
    @ObservableState
    struct State: Equatable {
        var pendingCatalogEntries: [LibraryCatalogClient.Entry]
        var unmatchedStoredAudio: [LibraryMediaStoreClient.StoredAudio]
        var recoveredItems: [LibraryItemRecoveryReducer.RecoveredItem]
        var catalogNeedsReplacement: Bool
        var itemRecovery: LibraryItemRecoveryReducer.State?
        var phase: Phase

        init(
            catalog: Result<LibraryCatalogClient.Snapshot, LibraryFailure>,
            storedAudio: [LibraryMediaStoreClient.StoredAudio]
        ) {
            switch catalog {
            case let .success(snapshot):
                pendingCatalogEntries = Array(snapshot.entries)
                catalogNeedsReplacement = false
            case .failure:
                pendingCatalogEntries = []
                catalogNeedsReplacement = true
            }
            unmatchedStoredAudio = storedAudio
            recoveredItems = []
            itemRecovery = nil
            phase = .ready
        }
    }

    enum Action: Equatable {
        case start
        case nextStepRequested
        case itemRecovery(LibraryItemRecoveryReducer.Action)
        case catalogReplacementCompleted(
            Result<LibraryCatalogClient.Snapshot, LibraryFailure>
        )
        case delegate(Delegate)
    }

    @Dependency(\.libraryCatalog) private var libraryCatalog

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                guard state.phase == .ready else { return .none }
                return .send(.nextStepRequested)

            case .nextStepRequested:
                guard
                    state.phase == .ready,
                    state.itemRecovery == nil
                else {
                    return .none
                }

                if !state.pendingCatalogEntries.isEmpty {
                    let catalogEntry = state.pendingCatalogEntries.removeFirst()
                    guard
                        let storedIndex = state.unmatchedStoredAudio.firstIndex(
                            where: {
                                $0.reference == catalogEntry.audioReference
                            }
                        )
                    else {
                        state.catalogNeedsReplacement = true
                        return .send(.nextStepRequested)
                    }

                    let storedAudio = state.unmatchedStoredAudio.remove(
                        at: storedIndex
                    )
                    state.itemRecovery = LibraryItemRecoveryReducer.State(
                        source: .catalogEntry(
                            catalogEntry,
                            storedAudio: storedAudio
                        )
                    )
                    return .send(.itemRecovery(.start))

                } else if !state.unmatchedStoredAudio.isEmpty {
                    let storedAudio = state.unmatchedStoredAudio.removeFirst()
                    state.itemRecovery = LibraryItemRecoveryReducer.State(
                        source: .uncatalogedAudio(storedAudio)
                    )
                    return .send(.itemRecovery(.start))

                } else {
                    let snapshot = LibraryCatalogClient.Snapshot(
                        entries: IdentifiedArray(
                            uniqueElements: state.recoveredItems.map(
                                \.catalogEntry
                            )
                        )
                    )
                    let library = Library(
                        items: IdentifiedArray(
                            uniqueElements: state.recoveredItems.map(
                                \.libraryItem
                            )
                        )
                    )

                    guard state.catalogNeedsReplacement else {
                        state.phase = .completed
                        return .send(
                            .delegate(
                                .completed(
                                    Completion(
                                        library: library,
                                        catalog: snapshot,
                                        catalogWriteFailure: nil
                                    )
                                )
                            )
                        )
                    }

                    state.phase = .replacingCatalog(
                        Completion(
                            library: library,
                            catalog: snapshot,
                            catalogWriteFailure: nil
                        )
                    )
                    return .run { send in
                        let result = await libraryCatalog.replace(snapshot)
                        await send(.catalogReplacementCompleted(result))
                    }
                }

            case let .itemRecovery(
                .delegate(
                    .completed(completion)
                )
            ):
                state.itemRecovery = nil
                switch completion {
                case let .catalogUnchanged(recoveredItem):
                    state.recoveredItems.append(recoveredItem)
                case let .catalogChanged(recoveredItem):
                    state.recoveredItems.append(recoveredItem)
                    state.catalogNeedsReplacement = true
                }
                return .send(.nextStepRequested)

            case let .itemRecovery(.delegate(.failed(failure))):
                state.itemRecovery = nil
                state.phase = .completed
                return .send(.delegate(.failed(failure)))

            case .itemRecovery:
                return .none

            case let .catalogReplacementCompleted(result):
                guard case let .replacingCatalog(completion) = state.phase else {
                    return .none
                }

                state.phase = .completed
                switch result {
                case .success:
                    return .send(.delegate(.completed(completion)))
                case let .failure(failure):
                    return .send(
                        .delegate(
                            .completed(
                                Completion(
                                    library: completion.library,
                                    catalog: completion.catalog,
                                    catalogWriteFailure: failure
                                )
                            )
                        )
                    )
                }

            case .delegate:
                return .none
            }
        }
        .ifLet(\.itemRecovery, action: \.itemRecovery) {
            LibraryItemRecoveryReducer()
        }
    }
}
