import Foundation

/// TUS-resumable upload engine. Generic HTTP machinery — no Supabase, no TCA.
/// POST create → 201 Location, then PATCH `chunkSize` windows with `Upload-Offset`,
/// resuming after transient errors via HEAD and recreating on 409/expiry.
actor ResumableUploader {
    private let session: URLSession
    private static let maxRecreates = 1
    private static let maxResumes = 3

    init(session: URLSession) {
        self.session = session
    }

    nonisolated func upload(
        _ file: URL,
        to endpoint: URL,
        headers: [String: String],
        chunkSize: Int = 6 * 1024 * 1024
    ) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(file, endpoint, headers, chunkSize, continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ file: URL,
        _ endpoint: URL,
        _ headers: [String: String],
        _ chunkSize: Int,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let length = attrs[.size] as? Int ?? 0
        let totalChunks = length > 0
            ? (length + chunkSize - 1) / chunkSize
            : 0

        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var uploadURL = try await create(endpoint, headers, length)
        var offset = 0
        var resumesLeft = Self.maxResumes
        var recreatesLeft = Self.maxRecreates

        while offset < length {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(offset))
            let window = min(chunkSize, length - offset)
            let body = handle.readData(ofLength: window)

            do {
                offset = try await patch(uploadURL, body, offset)
            } catch let error as UploadConflict {
                _ = error
                guard recreatesLeft > 0 else { throw URLError(.cannotCreateFile) }
                recreatesLeft -= 1
                uploadURL = try await create(endpoint, headers, length)
                offset = 0
                continue
            } catch {
                guard resumesLeft > 0 else { throw error }
                resumesLeft -= 1
                offset = try await head(uploadURL)
                continue
            }

            let completed = (offset + chunkSize - 1) / chunkSize
            continuation.yield(TransferProgress(
                bytesTransferred: Int64(offset),
                totalBytes: Int64(length),
                completedChunks: min(completed, totalChunks),
                totalChunks: totalChunks
            ))
        }
    }

    private struct UploadConflict: Error {}

    private func create(_ endpoint: URL, _ headers: [String: String], _ length: Int) async throws -> URL {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        req.setValue("\(length)", forHTTPHeaderField: "Upload-Length")
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201,
              let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: endpoint)
        else { throw URLError(.badServerResponse) }
        return url.absoluteURL
    }

    private func patch(_ uploadURL: URL, _ body: Data, _ offset: Int) async throws -> Int {
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "PATCH"
        req.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        req.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
        req.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: req, from: body)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 204, 200:
            guard let next = http.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int.init)
            else { throw URLError(.badServerResponse) }
            return next
        case 409, 410, 404:
            throw UploadConflict()
        default:
            throw URLError(.badServerResponse)
        }
    }

    private func head(_ uploadURL: URL) async throws -> Int {
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "HEAD"
        req.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let off = http.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int.init)
        else { throw URLError(.badServerResponse) }
        return off
    }
}
