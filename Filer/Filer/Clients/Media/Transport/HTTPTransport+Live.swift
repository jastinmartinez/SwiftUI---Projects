import Foundation

extension HTTPTransport {
    static func live(session: URLSession) -> HTTPTransport {
        let data: DataRequest = { request in
            let (body, response) = try await session.data(for: request)
            return try normalize(response, body: body)
        }

        let upload: UploadRequest = { request, body in
            let (responseBody, response) = try await session.upload(for: request, from: body)
            return try normalize(response, body: responseBody)
        }

        return HTTPTransport(data: data, upload: upload)
    }
}

/// Adapter: normalizes a URLSession `(Data, URLResponse)` pair into the domain
/// `HTTPResponse`, keeping URLSession's representation out of `HTTPResponse`'s API.
private func normalize(_ response: URLResponse, body: Data) throws -> HTTPResponse {
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }

    var headers: [String: String] = [:]
    for (key, value) in http.allHeaderFields {
        guard let key = key as? String else { continue }
        headers[key] = String(describing: value)
    }

    return HTTPResponse(statusCode: http.statusCode, headers: headers, body: body)
}
