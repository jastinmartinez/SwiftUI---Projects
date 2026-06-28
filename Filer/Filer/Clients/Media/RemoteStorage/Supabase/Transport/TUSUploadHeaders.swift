import Foundation

/// Builds TUS protocol requests for resumable upload.
enum TUSUploadHeaders {
    static func createRequest(
        endpoint: URL,
        uploadLength: Int,
        headers: [String: String]
    ) -> URLRequest {
        request(
            url: endpoint,
            method: "POST",
            headers: headers.merging(
                [
                    "Tus-Resumable": "1.0.0",
                    "Upload-Length": "\(uploadLength)",
                ],
                uniquingKeysWith: { _, protocolValue in protocolValue }
            )
        )
    }

    static func patchRequest(uploadURL: URL, offset: Int) -> URLRequest {
        request(
            url: uploadURL,
            method: "PATCH",
            headers: [
                "Tus-Resumable": "1.0.0",
                "Upload-Offset": "\(offset)",
                "Content-Type": "application/offset+octet-stream",
            ]
        )
    }

    static func headRequest(uploadURL: URL) -> URLRequest {
        request(
            url: uploadURL,
            method: "HEAD",
            headers: ["Tus-Resumable": "1.0.0"]
        )
    }

    private static func request(
        url: URL,
        method: String,
        headers: [String: String]
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}
