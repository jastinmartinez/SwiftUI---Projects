import Foundation

extension NowPlayingImageClient {
    /// Creates the production image loader from an explicitly supplied data
    /// operation.
    ///
    /// Remote responses must be successful HTTP responses. File URLs preserve
    /// the non-HTTP response returned for managed Library artwork. Transport and
    /// cancellation errors pass through unchanged.
    ///
    /// - Parameter data: The URL-session data operation supplied by application
    ///   composition.
    /// - Returns: A loader for remote and managed-file image bytes.
    static func live(
        data:
            @escaping @Sendable (URLRequest) async throws -> (
                Data,
                URLResponse
            )
    ) -> Self {
        Self(
            load: { url in
                let (payload, response) = try await data(
                    URLRequest(url: url)
                )
                if url.isFileURL {
                    return payload
                }
                guard
                    let response = response as? HTTPURLResponse,
                    (200..<300).contains(response.statusCode)
                else {
                    throw URLError(.badServerResponse)
                }
                return payload
            }
        )
    }
}
