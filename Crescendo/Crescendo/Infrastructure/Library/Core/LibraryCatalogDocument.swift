import Foundation

/// Defines the versioned persistence representation of the Library catalog.
///
/// The document owns JSON compatibility and validation of persisted values. It
/// performs no file access, exposes no runtime URLs or Domain record, and makes
/// no recovery decision when stored data is unavailable.
struct LibraryCatalogDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let records: [Record]

    init(version: Int, records: [Record]) {
        self.version = version
        self.records = records
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        records = try container.decode([Record].self, forKey: .records)
        guard isValid else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported or invalid Library catalog"
                )
            )
        }
    }

    var isValid: Bool {
        version == Self.currentVersion
            && Set(records.map(\.id)).count == records.count
            && records.allSatisfy(\.isValid)
    }
}

extension LibraryCatalogDocument {
    /// One persistence-only Library catalog record.
    ///
    /// This representation stores relative managed-file references and raw
    /// metadata. It is neither a Domain entity nor the reducer-facing catalog
    /// entry exchanged by `LibraryCatalogClient`.
    struct Record: Codable, Equatable, Sendable {
        let id: TrackID
        let audioReference: String
        let contentIdentity: String
        let title: String
        let artistName: String?
        let albumTitle: String?
        let albumArtistName: String?
        let duration: TimeInterval?
        let trackNumber: Int?
        let discNumber: Int?
        let artworkReference: String?
        let addedAt: Date

        fileprivate var isValid: Bool {
            id.providerID == .library
                && UUID(uuidString: id.nativeID) != nil
                && Self.isCanonicalContentIdentity(contentIdentity)
                && Self.isContained(
                    audioReference,
                    under: "Audio"
                )
                && artworkReference.map {
                    Self.isContained($0, under: "Artwork")
                } ?? true
        }

        private static func isContained(
            _ reference: String,
            under directory: String
        ) -> Bool {
            let components = reference.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            return components.count == 2
                && components[0] == Substring(directory)
                && !components[1].isEmpty
                && components.allSatisfy { $0 != "." && $0 != ".." }
        }

        private static func isCanonicalContentIdentity(
            _ contentIdentity: String
        ) -> Bool {
            let hexadecimalCharacters = CharacterSet(
                charactersIn: "0123456789abcdef"
            )
            return contentIdentity.count == 64
                && contentIdentity.unicodeScalars.allSatisfy {
                    hexadecimalCharacters.contains($0)
                }
        }
    }
}
