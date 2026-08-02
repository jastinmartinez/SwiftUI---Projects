import Foundation

/// Performs Audius HTTP search and constructs stable public stream endpoints.
///
/// This concrete infrastructure boundary owns Audius URL and response details;
/// features consume only the provider-neutral `ProviderSearchClient`.
struct AudiusAPI: Sendable {
    let configuration: AudiusConfiguration
    let data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Fetches and decodes one raw Audius search page.
    ///
    /// Transport, status, and response-document failures are normalized to the
    /// provider-neutral network failure while task cancellation remains intact.
    func tracks(
        query: String,
        offset: Int,
        limit: Int
    ) async throws -> AudiusTracksResponse {
        let url = try makeURL(
            path: "/v1/tracks/search",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )

        do {
            let (responseData, response) = try await data(URLRequest(url: url))
            guard
                let response = response as? HTTPURLResponse,
                (200..<300).contains(response.statusCode)
            else {
                throw MusicProviderError.network
            }
            return try JSONDecoder().decode(
                AudiusTracksResponse.self,
                from: responseData
            )
        } catch let error as CancellationError {
            throw error
        } catch let error as MusicProviderError {
            throw error
        } catch {
            throw MusicProviderError.network
        }
    }

    /// Constructs the stable endpoint AVPlayer requests for one Audius track.
    ///
    /// This operation performs no network request and rejects blank identities
    /// before they can enter a playback URL.
    func streamURL(trackID: String) throws -> URL {
        let trackID = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trackID.isEmpty else {
            throw MusicProviderError.network
        }
        return try makeURL(path: "/v1/tracks/\(trackID)/stream")
    }

    /// Builds one HTTPS Audius endpoint and appends the client metadata
    /// required by every request and stable playback URL.
    private func makeURL(
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.audius.co"
        components.path = path
        let authenticationQueryItems = [
            URLQueryItem(name: "app_name", value: "Crescendo"),
            URLQueryItem(name: "api_key", value: configuration.apiKey),
        ]
        components.queryItems = queryItems + authenticationQueryItems

        guard let url = components.url else {
            throw MusicProviderError.network
        }
        return url
    }
}
