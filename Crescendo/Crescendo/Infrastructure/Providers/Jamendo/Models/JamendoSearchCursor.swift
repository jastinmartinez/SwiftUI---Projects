import Foundation

struct JamendoSearchCursor: Codable, Equatable, Sendable {
    let query: String
    let offset: Int

    init(query: String, offset: Int) {
        self.query = query
        self.offset = offset
    }

    init(searchCursor: SearchCursor) throws {
        guard let data = Data(base64Encoded: searchCursor.value) else {
            throw MusicProviderError.unavailable
        }
        do {
            self = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw MusicProviderError.unavailable
        }
    }

    func searchCursor() throws -> SearchCursor {
        do {
            return SearchCursor(
                value: try JSONEncoder().encode(self).base64EncodedString()
            )
        } catch {
            throw MusicProviderError.unavailable
        }
    }
}
