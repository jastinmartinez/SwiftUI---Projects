import Foundation
import Testing

@testable import Crescendo

/// Proves the versioned catalog representation independently of file access.
struct LibraryCatalogDocumentTests {
    @Test
    func versionOneRoundTripsDeterministically() throws {
        let document = makeDocument()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let firstEncoding = try encoder.encode(document)
        let secondEncoding = try encoder.encode(document)
        let decoded = try JSONDecoder().decode(
            LibraryCatalogDocument.self,
            from: firstEncoding
        )

        #expect(firstEncoding == secondEncoding)
        #expect(decoded == document)
    }

    @Test
    func unsupportedVersionIsRejected() throws {
        let data = try encodedDocument { root in
            root["version"] = 2
        }

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                LibraryCatalogDocument.self,
                from: data
            )
        }
    }

    @Test(arguments: [
        "",
        "identity",
        String(repeating: "A", count: 64),
        String(repeating: "g", count: 64),
    ])
    func noncanonicalContentIdentityIsRejected(
        _ contentIdentity: String
    ) throws {
        let data = try encodedDocument { root in
            var records = try #require(root["records"] as? [[String: Any]])
            records[0]["contentIdentity"] = contentIdentity
            root["records"] = records
        }

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                LibraryCatalogDocument.self,
                from: data
            )
        }
    }

    @Test
    func escapingManagedReferenceIsRejected() throws {
        let data = try encodedDocument { root in
            var records = try #require(root["records"] as? [[String: Any]])
            records[0]["audioReference"] = "../outside.m4a"
            root["records"] = records
        }

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                LibraryCatalogDocument.self,
                from: data
            )
        }
    }

    private func makeDocument() -> LibraryCatalogDocument {
        LibraryCatalogDocument(
            version: 1,
            records: [
                LibraryCatalogDocument.Record(
                    id: TrackID(
                        providerID: .library,
                        nativeID: "01234567-89AB-CDEF-0123-456789ABCDEF"
                    ),
                    audioReference: "Audio/01234567-89AB-CDEF-0123-456789ABCDEF.m4a",
                    contentIdentity: String(repeating: "a", count: 64),
                    title: "Song",
                    artistName: "Artist",
                    albumTitle: "Album",
                    albumArtistName: "Album Artist",
                    duration: 180,
                    trackNumber: 2,
                    discNumber: 1,
                    artworkReference: "Artwork/01234567-89AB-CDEF-0123-456789ABCDEF",
                    addedAt: Date(timeIntervalSinceReferenceDate: 100)
                ),
            ]
        )
    }

    private func encodedDocument(
        modifying mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        let encoded = try JSONEncoder().encode(makeDocument())
        var root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        try mutation(&root)
        return try JSONSerialization.data(withJSONObject: root)
    }
}
