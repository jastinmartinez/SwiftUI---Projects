import Foundation
import IdentifiedCollections
import Testing

@testable import Crescendo

struct LibraryDomainTests {
    @Test
    func contentIdentityDetectsDuplicateContentAcrossDifferentTracks() {
        let sharedIdentity = Library.ContentIdentity(rawValue: "shared-content")
        let original = makeItem(
            nativeID: "original",
            contentIdentity: sharedIdentity
        )
        let duplicate = makeItem(
            nativeID: "duplicate",
            contentIdentity: sharedIdentity
        )
        let distinct = Library.ContentIdentity(rawValue: "distinct-content")
        let library = Library(
            items: IdentifiedArray(uniqueElements: [original])
        )

        #expect(library.contains(duplicate.contentIdentity))
        #expect(!library.contains(distinct))
    }

    @Test
    func recentlyAddedOrdersItemsByLibraryMembershipDate() {
        let older = makeItem(
            nativeID: "older",
            contentIdentity: .init(rawValue: "older-content"),
            addedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let newer = makeItem(
            nativeID: "newer",
            contentIdentity: .init(rawValue: "newer-content"),
            addedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let middle = makeItem(
            nativeID: "middle",
            contentIdentity: .init(rawValue: "middle-content"),
            addedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let library = Library(
            items: IdentifiedArray(uniqueElements: [older, newer, middle])
        )

        #expect(library.recentlyAdded.map(\.id) == [newer.id, middle.id, older.id])
    }

    @Test
    func albumCountUsesDistinctTrimmedCaseInsensitiveTitles() {
        let items = [
            makeItem(
                nativeID: "one",
                contentIdentity: .init(rawValue: "one-content"),
                albumTitle: "  Night Drive "
            ),
            makeItem(
                nativeID: "two",
                contentIdentity: .init(rawValue: "two-content"),
                albumTitle: "night drive"
            ),
            makeItem(
                nativeID: "three",
                contentIdentity: .init(rawValue: "three-content"),
                albumTitle: "Morning"
            ),
            makeItem(
                nativeID: "four",
                contentIdentity: .init(rawValue: "four-content"),
                albumTitle: "  "
            ),
            makeItem(
                nativeID: "five",
                contentIdentity: .init(rawValue: "five-content"),
                albumTitle: nil
            ),
        ]
        let library = Library(
            items: IdentifiedArray(uniqueElements: items)
        )

        #expect(library.albumCount == 2)
    }

    @Test
    func appendingReturnsANewAggregateContainingTheItem() {
        let item = makeItem(
            nativeID: "new",
            contentIdentity: .init(rawValue: "new-content")
        )
        let library = Library(
            items: IdentifiedArray(uniqueElements: [])
        )

        let updated = library.appending(item)

        #expect(library.items.isEmpty)
        #expect(updated.items[id: item.id] == item)
    }

    private func makeItem(
        nativeID: String,
        contentIdentity: Library.ContentIdentity,
        albumTitle: String? = nil,
        addedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> Library.Item {
        let track = Track(
            id: TrackID(providerID: .library, nativeID: nativeID),
            title: "Track \(nativeID)",
            artistName: nil,
            albumTitle: albumTitle,
            artworkURL: nil,
            duration: 180,
            playbackURL: URL(
                fileURLWithPath: "/managed/Audio/\(nativeID).m4a"
            )
        )
        return Library.Item(
            track: track,
            contentIdentity: contentIdentity,
            addedAt: addedAt
        )
    }
}
