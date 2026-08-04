struct JamendoTrack: Decodable, Sendable {
    let id: String
    let name: String
    let artistName: String
    let albumName: String
    let image: String
    let duration: String
    let audio: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case artistName = "artist_name"
        case albumName = "album_name"
        case image
        case duration
        case audio
    }
}

extension JamendoTrack {
    /// Decodes the duration field from either representation returned by
    /// Jamendo.
    ///
    /// Jamendo responses may encode seconds as a string or a JSON number.
    ///
    /// - Parameter decoder: A decoder positioned at one Jamendo track.
    /// - Throws: `DecodingError` when a required field or supported duration
    ///   representation cannot be decoded.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        artistName = try container.decode(String.self, forKey: .artistName)
        albumName = try container.decode(String.self, forKey: .albumName)
        image = try container.decode(String.self, forKey: .image)
        audio = try container.decode(String.self, forKey: .audio)

        if let value = try? container.decode(String.self, forKey: .duration) {
            duration = value
        } else if let value = try? container.decode(Int.self, forKey: .duration) {
            duration = String(value)
        } else {
            duration = String(
                try container.decode(Double.self, forKey: .duration)
            )
        }
    }
}
