struct JamendoResponseHeaders: Decodable, Sendable {
    let status: String
    let code: Int
    let resultsCount: Int
    let resultsFullCount: Int

    enum CodingKeys: String, CodingKey {
        case status
        case code
        case resultsCount = "results_count"
        case resultsFullCount = "results_fullcount"
    }
}
