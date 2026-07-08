@testable import Filer
import Foundation

// Convenience constructors for the HTTP shapes the transfer engines expect, so a
// stubbed transport reads as the response it stands for rather than a status-code
// literal. Header lookups are case-insensitive, matching `HTTPResponse.value(forHeader:)`.

extension HTTPResponse {
    /// 204 with no headers or body — an accepted request that returns nothing.
    static let noContent = HTTPResponse(statusCode: 204, headers: [:], body: Data())

    /// 201 Created carrying the resumable-upload `Location` (TUS create).
    static func created(location: String) -> HTTPResponse {
        HTTPResponse(statusCode: 201, headers: ["Location": location], body: Data())
    }

    /// 204 acknowledging a TUS PATCH, reporting the server's new `Upload-Offset`.
    static func accepted(uploadOffset: Int) -> HTTPResponse {
        HTTPResponse(statusCode: 204, headers: ["Upload-Offset": "\(uploadOffset)"], body: Data())
    }

    /// 200 answering a TUS HEAD probe with the server's confirmed `Upload-Offset`.
    static func head(uploadOffset: Int) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: ["Upload-Offset": "\(uploadOffset)"], body: Data())
    }
}

extension HTTPTransport {
    /// A transport that only answers `data` requests; an unexpected `upload` fails loudly.
    static func dataOnly(_ data: @escaping DataRequest) -> HTTPTransport {
        HTTPTransport(data: data, upload: { _, _ in throw NotStubbed("httpTransport.upload") })
    }
}
