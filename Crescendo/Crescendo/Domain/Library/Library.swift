import Foundation
import IdentifiedCollections

/// The confirmed Library aggregate and its membership-derived projections.
///
/// This value owns Library membership, duplicate-content lookup,
/// recently-added order, and album counting. Import, persistence, recovery,
/// navigation, and playback remain outside the aggregate.
struct Library: Equatable, Sendable {
    let items: IdentifiedArrayOf<Item>

    /// Reports whether the confirmed Library already contains the content.
    ///
    /// Infrastructure decides how identities are produced. The aggregate uses
    /// only their equality to enforce the product's duplicate-content policy.
    ///
    /// - Parameter contentIdentity: The opaque identity to find.
    /// - Returns: `true` when any confirmed item has the same identity.
    func contains(_ contentIdentity: ContentIdentity) -> Bool {
        items.contains { $0.contentIdentity == contentIdentity }
    }

    var recentlyAdded: IdentifiedArrayOf<Item> {
        IdentifiedArray(
            uniqueElements: items.sorted {
                $0.addedAt > $1.addedAt
            }
        )
    }

    var albumCount: Int {
        Set(
            items.compactMap {
                $0.track.albumTitle?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty }
        ).count
    }

    /// Returns a copy that inserts or replaces one membership by identity.
    ///
    /// The result preserves the order of unaffected memberships.
    ///
    /// - Parameter item: The confirmed membership to insert or replace.
    /// - Returns: The updated Library aggregate.
    func appending(_ item: Item) -> Self {
        var updatedItems = items
        updatedItems.updateOrAppend(item)
        return Self(items: updatedItems)
    }
}
