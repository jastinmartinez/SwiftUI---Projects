import Foundation

extension Library {
    /// A provider-neutral track's confirmed membership in the Library.
    ///
    /// This value adds only Library-specific facts to `Track`. File paths,
    /// catalog encoding, metadata extraction, and identity generation remain
    /// infrastructure responsibilities.
    struct Item: Equatable, Identifiable, Sendable {
        let track: Track
        let contentIdentity: ContentIdentity
        let addedAt: Date

        var id: TrackID { track.id }
    }

    /// An opaque identity used by the Library's duplicate-content policy.
    ///
    /// Domain compares identities but does not interpret or validate their
    /// representation. Infrastructure may derive one from file content without
    /// exposing the hashing mechanism to the Library.
    struct ContentIdentity: Hashable, Sendable {
        let rawValue: String
    }
}
