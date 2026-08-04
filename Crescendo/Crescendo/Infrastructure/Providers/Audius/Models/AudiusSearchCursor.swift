import Foundation

/// Carries Audius-owned query and offset state through the provider-neutral
/// continuation boundary.
///
/// Search features cannot observe or construct provider pagination details;
/// only the Audius adapter encodes and restores this infrastructure value.
struct AudiusSearchCursor: Codable, Equatable, Sendable {
    let query: String
    let offset: Int

    init(query: String, offset: Int) {
        self.query = query
        self.offset = offset
    }

    /// Restores Audius pagination from provider-neutral continuation data.
    ///
    /// - Parameter searchCursor: Opaque data previously created by Audius.
    /// - Throws: `MusicProviderError.unavailable` when the payload is invalid.
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

    /// Hides Audius pagination state behind the provider-neutral cursor type.
    ///
    /// - Returns: Opaque continuation data for a later Audius request.
    /// - Throws: `MusicProviderError.unavailable` when encoding fails.
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
