import Foundation

/// Represents the Audius response fields needed to construct a playable track.
///
/// This provider DTO remains inside Audius infrastructure so wire-format names
/// and optional metadata cannot leak into reducer state or domain contracts.
struct AudiusTrack: Decodable, Sendable {
    let id: String
    let title: String
    let duration: TimeInterval?
    let isStreamable: Bool
    let isStreamGated: Bool
    let artwork: Artwork?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case isStreamable = "is_streamable"
        case isStreamGated = "is_stream_gated"
        case artwork
        case user
    }
}

extension AudiusTrack {
    /// Decodes the preferred Audius artwork variant used by Crescendo.
    struct Artwork: Decodable, Sendable {
        let url480: String?

        enum CodingKeys: String, CodingKey {
            case url480 = "480x480"
        }
    }

    /// Decodes only the Audius user metadata used as a track artist.
    struct User: Decodable, Sendable {
        let name: String?
    }
}
