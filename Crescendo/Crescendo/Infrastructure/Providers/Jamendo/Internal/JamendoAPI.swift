import Foundation

struct JamendoAPI: Sendable {
    let configuration: JamendoConfiguration
    let data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func tracks(
        query: String,
        offset: Int,
        limit: Int
    ) async throws -> JamendoTracksResponse {
        try await request(
            queryItems: [
                URLQueryItem(name: "client_id", value: configuration.clientID),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "fullcount", value: "true"),
                URLQueryItem(name: "type", value: "single albumtrack"),
                URLQueryItem(name: "audioformat", value: "mp32"),
                URLQueryItem(name: "imagesize", value: "300"),
            ]
        )
    }

    private func request(
        queryItems: [URLQueryItem]
    ) async throws -> JamendoTracksResponse {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.jamendo.com"
        components.path = "/v3.0/tracks/"
        components.queryItems = queryItems

        guard let url = components.url else {
            throw MusicProviderError.network
        }

        do {
            let (responseData, response) = try await data(
                URLRequest(url: url)
            )
            guard
                let response = response as? HTTPURLResponse,
                (200..<300).contains(response.statusCode)
            else {
                throw MusicProviderError.network
            }
            let jamendoResponse = try JSONDecoder().decode(
                JamendoTracksResponse.self,
                from: responseData
            )
            guard jamendoResponse.headers.code == 0 else {
                throw MusicProviderError.network
            }
            return jamendoResponse
        } catch let error as MusicProviderError {
            throw error
        } catch {
            throw MusicProviderError.network
        }
    }
}
