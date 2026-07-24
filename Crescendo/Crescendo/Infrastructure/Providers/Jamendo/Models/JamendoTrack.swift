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
