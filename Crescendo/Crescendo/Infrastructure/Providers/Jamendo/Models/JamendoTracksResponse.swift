struct JamendoTracksResponse: Decodable, Sendable {
    let headers: JamendoResponseHeaders
    let results: [JamendoTrack]
}
