import Foundation

/// Carries Library-owned query and offset state through the provider-neutral
/// continuation boundary.
///
/// The cursor freezes the submitted query and the next catalog-membership
/// offset between pages. Its Base64-encoded JSON representation is an
/// infrastructure detail; filtering, catalog access, URL resolution, and
/// reducer pagination state remain outside this value.
struct LibrarySearchCursor: Codable, Equatable, Sendable {
    let query: String
    let offset: Int

    init(query: String, offset: Int) {
        self.query = query
        self.offset = offset
    }

    /// Decodes provider-owned continuation state from its opaque boundary
    /// representation.
    ///
    /// - Parameter searchCursor: The opaque cursor returned by an earlier
    ///   Library search page.
    /// - Throws: `MusicProviderError.unavailable` when the cursor cannot be
    ///   decoded as Library continuation state.
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

    /// Encodes this provider-owned state for the provider-neutral search
    /// boundary.
    ///
    /// - Returns: An opaque cursor suitable for a continuation request.
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
