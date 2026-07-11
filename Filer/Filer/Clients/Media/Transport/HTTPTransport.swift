import Foundation

/// Executes HTTP requests for transfer engines.
///
/// A transport seam: the live implementation bridges URLSession (see
/// `HTTPTransport+Live`); tests inject stubs. It does not interpret upload,
/// download, range, retry, persistence, progress, or Supabase semantics.
struct HTTPTransport: Sendable {
    typealias DataRequest = @Sendable (_ request: URLRequest) async throws -> HTTPResponse
    typealias UploadRequest = @Sendable (_ request: URLRequest, _ body: Data) async throws -> HTTPResponse

    var data: DataRequest
    var upload: UploadRequest
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
    func value(forHeader name: String) -> String? {
        headers.first { key, _ in key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
