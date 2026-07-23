import Foundation

/// Apple Music's provider-private search continuation payload.
struct AppleMusicSearchCursor: Codable, Equatable, Sendable {
    let query: String
    let offset: Int
}

extension AppleMusicSearchCursor {
    init(searchCursor: SearchCursor) throws {
        self = try JSONDecoder().decode(
            Self.self,
            from: Data(searchCursor.value.utf8)
        )
    }

    func searchCursor() throws -> SearchCursor {
        let data = try JSONEncoder().encode(self)
        guard let value = String(data: data, encoding: .utf8) else {
            throw MusicProviderError.unavailable
        }
        return SearchCursor(value: value)
    }
}
