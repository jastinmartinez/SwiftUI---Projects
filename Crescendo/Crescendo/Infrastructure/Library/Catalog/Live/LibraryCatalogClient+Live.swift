import Foundation

extension LibraryCatalogClient {
    /// Adapts one shared catalog actor to the reducer-facing client contract.
    ///
    /// This adapter creates no additional store or state and leaves recovery,
    /// media reconciliation, and import coordination to Library workflows.
    ///
    /// - Parameter store: The shared actor that serializes typed catalog access.
    /// - Returns: A reducer-facing client backed by that actor.
    static func live(store: LibraryCatalogStore) -> Self {
        Self(
            load: { await store.load() },
            replace: { await store.replace($0) }
        )
    }
}
