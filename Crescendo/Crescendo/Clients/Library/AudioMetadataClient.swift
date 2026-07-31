import ComposableArchitecture
import Foundation

/// Defines the replaceable boundary for reading descriptive audio metadata.
///
/// The client exposes source metadata without applying fallback text, creating
/// Library membership, storing artwork, exposing AVFoundation, coordinating an
/// import, or deciding how failures are presented.
struct AudioMetadataClient: Sendable {
    /// Reads source metadata without retaining or modifying the file.
    var read: @Sendable (URL) async -> Result<Metadata, LibraryFailure>
}

extension AudioMetadataClient {
    /// The optional source values extracted from one audio file.
    ///
    /// Optionality preserves the distinction between absent source metadata
    /// and fallback values selected by a later workflow or presentation layer.
    struct Metadata: Equatable, Sendable {
        let title: String?
        let artistName: String?
        let albumTitle: String?
        let albumArtistName: String?
        let duration: TimeInterval?
        let trackNumber: Int?
        let discNumber: Int?
        let artworkData: Data?
    }
}

extension AudioMetadataClient: DependencyKey {
    static let liveValue = Self(
        read: { _ in
            fatalError("AudioMetadataClient.read is not configured")
        }
    )
}

extension DependencyValues {
    var audioMetadata: AudioMetadataClient {
        get { self[AudioMetadataClient.self] }
        set { self[AudioMetadataClient.self] = newValue }
    }
}
