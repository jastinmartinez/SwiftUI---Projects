import AVFoundation
import Foundation

extension AudioMetadataClient {
    /// Reads optional source metadata through asynchronous AVFoundation APIs.
    ///
    /// The adapter neither moves the source nor applies fallback text, creates
    /// Library membership, stores artwork, or persists any extracted value.
    static func live() -> Self {
        let reader = AVFoundationMetadataReader()
        return Self(read: { await reader.read($0) })
    }
}

private extension AudioMetadataClient {
    struct AVFoundationMetadataReader: Sendable {
        func read(
            _ fileURL: URL
        ) async -> Result<AudioMetadataClient.Metadata, LibraryFailure> {
            let asset = AVURLAsset(url: fileURL)
            do {
                guard
                    try await !asset.loadTracks(
                        withMediaType: .audio
                    ).isEmpty
                else {
                    return .failure(.unsupportedFile)
                }
                let duration = try await asset.load(.duration)
                let metadata = try await asset.load(.metadata)
                return try .success(
                    AudioMetadataClient.Metadata(
                        title: await string(
                            .commonIdentifierTitle,
                            in: metadata
                        ),
                        artistName: await string(
                            .commonIdentifierArtist,
                            in: metadata
                        ),
                        albumTitle: await string(
                            .commonIdentifierAlbumName,
                            in: metadata
                        ),
                        albumArtistName: await string(
                            .iTunesMetadataAlbumArtist,
                            in: metadata
                        ),
                        duration: duration.seconds.isFinite
                            ? duration.seconds
                            : nil,
                        trackNumber: await integer(
                            .iTunesMetadataTrackNumber,
                            in: metadata
                        ),
                        discNumber: await integer(
                            .iTunesMetadataDiscNumber,
                            in: metadata
                        ),
                        artworkData: await data(
                            .commonIdentifierArtwork,
                            in: metadata
                        )
                    )
                )
            } catch {
                return .failure(.metadataReadFailed)
            }
        }

        private func string(
            _ identifier: AVMetadataIdentifier,
            in metadata: [AVMetadataItem]
        ) async throws -> String? {
            guard
                let item = AVMetadataItem.metadataItems(
                    from: metadata,
                    filteredByIdentifier: identifier
                ).first
            else {
                return nil
            }
            return try await item.load(.stringValue)
        }

        private func integer(
            _ identifier: AVMetadataIdentifier,
            in metadata: [AVMetadataItem]
        ) async throws -> Int? {
            guard
                let item = AVMetadataItem.metadataItems(
                    from: metadata,
                    filteredByIdentifier: identifier
                ).first
            else {
                return nil
            }
            if let value = try await item.load(.stringValue) {
                return Int(value.split(separator: "/").first ?? "")
            }
            guard
                let value = try await item.load(.dataValue),
                let currentNumber = Self.currentNumber(
                    fromITunesIndexData: value
                )
            else {
                return nil
            }
            return currentNumber
        }

        /// Decodes the current number from an iTunes `trkn` or `disk` atom.
        private static func currentNumber(
            fromITunesIndexData value: Data
        ) -> Int? {
            guard value.count >= 4 else { return nil }
            let highByte = value[value.startIndex.advanced(by: 2)]
            let lowByte = value[value.startIndex.advanced(by: 3)]
            return Int(highByte) << 8 | Int(lowByte)
        }

        private func data(
            _ identifier: AVMetadataIdentifier,
            in metadata: [AVMetadataItem]
        ) async throws -> Data? {
            guard
                let item = AVMetadataItem.metadataItems(
                    from: metadata,
                    filteredByIdentifier: identifier
                ).first
            else {
                return nil
            }
            return try await item.load(.dataValue)
        }
    }
}
