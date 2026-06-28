import Foundation

/// Executes HTTP requests for transfer engines.
///
/// This type owns URLSession bridging only. It does not interpret upload,
/// download, range, retry, persistence, progress, or Supabase semantics.
struct HTTPTransport: Sendable {
    typealias DataRequest = @Sendable (_ request: URLRequest) async throws -> HTTPResponse
    typealias UploadRequest = @Sendable (_ request: URLRequest, _ body: Data) async throws -> HTTPResponse

    var data: DataRequest
    var upload: UploadRequest
}

extension HTTPTransport {
    static func live(session: URLSession = .shared) -> HTTPTransport {
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

/// A normalized HTTP response used by transfer engines.
///
/// Header lookup is case-insensitive so policy code does not depend on
/// URLSession or server header casing.
struct HTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

extension HTTPResponse {
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

    func value(forHeader name: String) -> String? {
        headers.first { key, _ in key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
