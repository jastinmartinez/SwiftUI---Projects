import Foundation

extension HTTPTransport {
    static func live(session: URLSession) -> HTTPTransport {
        let data: DataRequest = { request in
            let (body, response) = try await session.data(for: request)
            return try HTTPResponse(body: body, response: response)
        }

        let upload: UploadRequest = { request, body in
            let (responseBody, response) = try await session.upload(for: request, from: body)
            return try HTTPResponse(body: responseBody, response: response)
        }

        return HTTPTransport(data: data, upload: upload)
    }
}

extension HTTPResponse {
    /// Bridges a URLSession `(Data, URLResponse)` pair into the normalized response.
    init(body: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let key = key as? String else { continue }
            headers[key] = String(describing: value)
        }

        self.init(statusCode: http.statusCode, headers: headers, body: body)
    }
}
