/// Decodes one Audius search payload while preserving its raw provider count.
///
/// Row-level decoding failures are isolated here so valid siblings survive and
/// pagination can advance by provider rows rather than only mapped tracks.
struct AudiusTracksResponse: Decodable, Sendable {
    let tracks: [AudiusTrack]
    let rawTrackCount: Int

    private enum CodingKeys: String, CodingKey {
        case data
    }

    /// Decodes provider rows independently so one malformed track cannot
    /// discard valid siblings or distort the raw count used for pagination.
    ///
    /// - Parameter decoder: A decoder positioned at an Audius search response.
    /// - Throws: `DecodingError` when the top-level provider row collection
    ///   cannot be decoded; malformed individual rows remain isolated.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try container.decode([Row].self, forKey: .data)
        tracks = rows.compactMap(\.track)
        rawTrackCount = rows.count
    }
}

private extension AudiusTracksResponse {
    /// Consumes one provider row while containing that row's decoding failure.
    struct Row: Decodable {
        let track: AudiusTrack?

        init(from decoder: Decoder) throws {
            track = try? AudiusTrack(from: decoder)
        }
    }
}
