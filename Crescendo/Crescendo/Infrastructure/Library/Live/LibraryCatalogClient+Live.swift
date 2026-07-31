import Foundation

extension LibraryCatalogClient {
    /// Adapts one shared catalog actor to the reducer-facing client contract.
    ///
    /// This adapter creates no additional store or state and leaves recovery,
    /// media reconciliation, and import coordination to Library workflows.
    static func live(store: LibraryCatalogStore) -> Self {
        Self(
            load: { await store.load() },
            replace: { await store.replace($0) }
        )
    }
}
