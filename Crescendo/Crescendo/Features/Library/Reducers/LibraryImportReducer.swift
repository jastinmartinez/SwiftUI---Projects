import ComposableArchitecture
import Foundation

/// Coordinates the transient workflow for one sequential Library import batch.
///
/// The reducer owns source order, progress, summaries, and working
/// Library/catalog projections. It starts one item-import child at a time and
/// reports only completed projections to `LibraryReducer`, which remains their
/// sole confirmed owner. It does not perform per-file operations, present the
/// picker, navigate, control playback, implement storage, or encode the catalog.
@Reducer
struct LibraryImportReducer {
    @ObservableState
    struct State: Equatable {
        var workingLibrary: Library
        var workingCatalog: LibraryCatalogClient.Snapshot
        var lifecycle: Lifecycle
        var itemImport: LibraryItemImportReducer.State?
        var phase: Phase

        init(
            sources: [URL],
            library: Library,
            catalog: LibraryCatalogClient.Snapshot
        ) {
            workingLibrary = library
            workingCatalog = catalog
            lifecycle = .importing(
                Progress(
                    sources: sources,
                    nextIndex: 0,
                    importedCount: 0,
                    duplicateCount: 0,
                    issues: []
                )
            )
            itemImport = nil
            phase = .ready
        }
    }

    enum Action: Equatable {
        case start
        case cancelButtonTapped
        case cancellationCompleted
        case nextFileRequested
        case itemImport(LibraryItemImportReducer.Action)
        case delegate(Delegate)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                guard state.phase == .ready else { return .none }
                return .send(.nextFileRequested)

            case .cancelButtonTapped:
                guard state.phase == .ready else { return .none }
                state.phase = .cancellationRequested
                guard state.itemImport != nil else {
                    return .send(.cancellationCompleted)
                }
                return .send(.itemImport(.cancelButtonTapped))

            case .cancellationCompleted:
                guard
                    state.phase == .cancellationRequested,
                    case let .importing(progress) = state.lifecycle
                else {
                    return .none
                }
                let summary = Summary(
                    importedCount: progress.importedCount,
                    duplicateCount: progress.duplicateCount,
                    issues: progress.issues
                )
                let completion = Completion(
                    library: state.workingLibrary,
                    catalog: state.workingCatalog,
                    summary: summary
                )
                state.lifecycle = .cancelled(summary)
                state.phase = .completed
                return .send(.delegate(.cancelled(completion)))

            case .nextFileRequested:
                guard
                    state.phase == .ready,
                    state.itemImport == nil,
                    case let .importing(progress) = state.lifecycle
                else {
                    return .none
                }

                guard progress.nextIndex < progress.sources.count else {
                    let summary = Summary(
                        importedCount: progress.importedCount,
                        duplicateCount: progress.duplicateCount,
                        issues: progress.issues
                    )
                    let completion = Completion(
                        library: state.workingLibrary,
                        catalog: state.workingCatalog,
                        summary: summary
                    )
                    state.lifecycle = .completed(summary)
                    state.phase = .completed
                    return .send(.delegate(.completed(completion)))
                }

                state.itemImport = LibraryItemImportReducer.State(
                    source: progress.sources[progress.nextIndex],
                    library: state.workingLibrary,
                    catalog: state.workingCatalog
                )
                return .send(.itemImport(.start))

            case let .itemImport(.delegate(.imported(importedItem))):
                guard case var .importing(progress) = state.lifecycle else {
                    return .none
                }
                state.itemImport = nil
                state.workingLibrary = state.workingLibrary.appending(
                    importedItem.item
                )
                state.workingCatalog = importedItem.catalog
                progress.nextIndex += 1
                progress.importedCount += 1
                progress.issues.append(contentsOf: importedItem.issues)
                state.lifecycle = .importing(progress)
                if state.phase == .cancellationRequested {
                    return .send(.cancellationCompleted)
                }
                return .send(.nextFileRequested)

            case .itemImport(.delegate(.duplicate)):
                guard case var .importing(progress) = state.lifecycle else {
                    return .none
                }
                state.itemImport = nil
                progress.nextIndex += 1
                progress.duplicateCount += 1
                state.lifecycle = .importing(progress)
                if state.phase == .cancellationRequested {
                    return .send(.cancellationCompleted)
                }
                return .send(.nextFileRequested)

            case let .itemImport(.delegate(.failed(issue))):
                guard case var .importing(progress) = state.lifecycle else {
                    return .none
                }
                state.itemImport = nil
                progress.nextIndex += 1
                progress.issues.append(issue)
                state.lifecycle = .importing(progress)
                if state.phase == .cancellationRequested {
                    return .send(.cancellationCompleted)
                }
                return .send(.nextFileRequested)

            case .itemImport(.delegate(.cancelled)):
                guard state.phase == .cancellationRequested else {
                    return .none
                }
                state.itemImport = nil
                return .send(.cancellationCompleted)

            case .itemImport, .delegate:
                return .none
            }
        }
        .ifLet(\.itemImport, action: \.itemImport) {
            LibraryItemImportReducer()
        }
    }
}
