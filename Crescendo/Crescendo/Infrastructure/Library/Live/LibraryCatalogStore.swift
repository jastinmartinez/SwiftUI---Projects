import Foundation
import IdentifiedCollections

/// Serializes typed Library catalog access through one persistence actor.
///
/// The store owns document encoding, decoding, version validation, and mapping
/// to the reducer-facing catalog contract. It owns no recovery workflow,
/// managed-audio deletion, runtime URL resolution, import sequencing, or UI
/// policy.
actor LibraryCatalogStore {
    private let catalogURL: URL
    private let catalogFile: LibraryCatalogFileClient

    init(
        catalogURL: URL,
        catalogFile: LibraryCatalogFileClient
    ) {
        self.catalogURL = catalogURL
        self.catalogFile = catalogFile
    }

    /// Loads the latest complete typed snapshot.
    ///
    /// A missing catalog is an empty snapshot. Unreadable, corrupt, invalid, or
    /// unsupported documents return `.catalogReadFailed` without mutating any
    /// managed media.
    func load() async -> Result<LibraryCatalogClient.Snapshot, LibraryFailure> {
        switch await catalogFile.read(catalogURL) {
        case let .failure(failure):
            return .failure(failure)
        case .success(nil):
            return .success(.init(entries: []))
        case let .success(.some(data)):
            do {
                let document = try JSONDecoder().decode(
                    LibraryCatalogDocument.self,
                    from: data
                )
                guard document.isValid else {
                    return .failure(.catalogReadFailed)
                }
                return .success(
                    .init(
                        entries: IdentifiedArray(
                            uniqueElements: document.records.map {
                                LibraryCatalogClient.Entry($0)
                            }
                        )
                    )
                )
            } catch {
                return .failure(.catalogReadFailed)
            }
        }
    }

    /// Replaces the complete catalog and confirms exactly the supplied value.
    ///
    /// The previous readable catalog remains authoritative whenever encoding or
    /// the complete-write operation fails.
    func replace(
        _ snapshot: LibraryCatalogClient.Snapshot
    ) async -> Result<LibraryCatalogClient.Snapshot, LibraryFailure> {
        let document = LibraryCatalogDocument(
            version: LibraryCatalogDocument.currentVersion,
            records: snapshot.entries.map {
                LibraryCatalogDocument.Record($0)
            }
        )
        guard document.isValid else {
            return .failure(.catalogWriteFailed)
        }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(document)
        } catch {
            return .failure(.catalogWriteFailed)
        }

        switch await catalogFile.write(data, catalogURL) {
        case .success:
            return .success(snapshot)
        case let .failure(failure):
            return .failure(failure)
        }
    }
}

private extension LibraryCatalogClient.Entry {
    init(_ record: LibraryCatalogDocument.Record) {
        self.init(
            id: record.id,
            audioReference: .init(rawValue: record.audioReference),
            contentIdentity: .init(rawValue: record.contentIdentity),
            title: record.title,
            artistName: record.artistName,
            albumTitle: record.albumTitle,
            albumArtistName: record.albumArtistName,
            duration: record.duration,
            trackNumber: record.trackNumber,
            discNumber: record.discNumber,
            artworkReference: record.artworkReference.map {
                .init(rawValue: $0)
            },
            addedAt: record.addedAt
        )
    }
}

private extension LibraryCatalogDocument.Record {
    init(_ entry: LibraryCatalogClient.Entry) {
        self.init(
            id: entry.id,
            audioReference: entry.audioReference.rawValue,
            contentIdentity: entry.contentIdentity.rawValue,
            title: entry.title,
            artistName: entry.artistName,
            albumTitle: entry.albumTitle,
            albumArtistName: entry.albumArtistName,
            duration: entry.duration,
            trackNumber: entry.trackNumber,
            discNumber: entry.discNumber,
            artworkReference: entry.artworkReference?.rawValue,
            addedAt: entry.addedAt
        )
    }
}
