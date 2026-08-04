import ComposableArchitecture

// Adapts picker or import lifecycle state into one localized summary model.
//
// The adapter owns workflow-to-copy projection and cancellation routing only.
// It does not render, mutate import policy, invoke clients, or persist data.
extension LibraryImportSummaryView.Model {
    /// Projects parent-owned picker failure or child-owned import lifecycle.
    ///
    /// Initialization fails when neither a picker failure nor an import batch
    /// is present.
    ///
    /// - Parameter store: The Library store supplying picker and import state.
    @MainActor
    init?(_ store: StoreOf<LibraryReducer>) {
        if let failure = store.fileSelectionFailure {
            self.init(
                title: Locs.Library.Import.failed,
                detail: Locs.Library.failure(failure),
                issueMessages: [],
                cancelTitle: nil,
                onCancel: nil
            )
            return
        }

        guard let importBatch = store.importBatch else { return nil }

        switch importBatch.lifecycle {
        case let .importing(progress):
            let currentSource = min(
                progress.nextIndex + (progress.sources.isEmpty ? 0 : 1),
                progress.sources.count
            )
            self.init(
                title: Locs.Library.Import.importing,
                detail: Locs.Library.Import.progress(
                    current: currentSource,
                    total: progress.sources.count
                ),
                issueMessages: Self.issueMessages(progress.issues),
                cancelTitle: Locs.Library.Import.cancel,
                onCancel: { store.send(.cancelImportButtonTapped) }
            )

        case let .completed(summary):
            self.init(
                title: Locs.Library.Import.completed,
                detail: Self.detail(summary, cancelled: false),
                issueMessages: Self.issueMessages(summary.issues),
                cancelTitle: nil,
                onCancel: nil
            )

        case let .cancelled(summary):
            self.init(
                title: Locs.Library.Import.cancelled,
                detail: Self.detail(summary, cancelled: true),
                issueMessages: Self.issueMessages(summary.issues),
                cancelTitle: nil,
                onCancel: nil
            )
        }
    }

    private static func detail(
        _ summary: LibraryImportReducer.Summary,
        cancelled: Bool
    ) -> String {
        let importText =
            cancelled
            ? Locs.Library.Import.importedBeforeCancellation(
                count: summary.importedCount
            )
            : Locs.Library.Import.imported(count: summary.importedCount)
        guard summary.duplicateCount > 0 else { return importText }
        return "\(importText) · \(Locs.Library.Import.duplicates(count: summary.duplicateCount))"
    }

    private static func issueMessages(
        _ issues: [LibraryImportReducer.Issue]
    ) -> [String] {
        issues.map { issue in
            "\(issue.sourceName): \(Locs.Library.failure(issue.failure))"
        }
    }
}
