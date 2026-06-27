import Foundation

/// Ranged-download engine. Probes `Range` support at runtime (via `RangeProbe`),
/// then loops `bytes=` windows with contiguous writes, degrading to a single
/// streaming GET (progress against Content-Length) when the server ignores Range.
/// Generic HTTP machinery — no Supabase, no TCA.
actor RangedDownloader {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    nonisolated func download(
        _ url: URL,
        to dest: URL,
        headers: [String: String],
        expectedSize: Int64?,
        chunkSize: Int = TransferProgress.chunkSize
    ) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(url, dest, headers, expectedSize, chunkSize, continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ url: URL,
        _ dest: URL,
        _ headers: [String: String],
        _ expectedSize: Int64?,
        _ chunkSize: Int,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws {
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        let (probe, probeBody) = try await probeRange(url, headers)
        let total = probe.totalLength ?? expectedSize ?? 0

        if probe.supportsRanges, total > 0 {
            try await rangedLoop(url, headers, handle, Int(total), chunkSize, continuation)
        } else {
            try streamWhole(probeBody, handle, Int(total), continuation)
        }
    }

    private func probeRange(
        _ url: URL,
        _ headers: [String: String]
    ) async throws -> (RangeProbe.Result, Data) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (RangeProbe.parse(http), data)
    }

    private func rangedLoop(
        _ url: URL,
        _ headers: [String: String],
        _ handle: FileHandle,
        _ total: Int,
        _ chunkSize: Int,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws {
        let totalChunks = (total + chunkSize - 1) / chunkSize
        var offset = 0
        var completed = 0

        while offset < total {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, total) - 1
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            for (k, v) in headers {
                req.setValue(v, forHTTPHeaderField: k)
            }
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 206 || http.statusCode == 200
            else { throw URLError(.badServerResponse) }

            try handle.seek(toOffset: UInt64(offset))
            handle.write(data)
            offset += data.count
            completed += 1

            continuation.yield(TransferProgress(
                bytesTransferred: Int64(offset),
                totalBytes: Int64(total),
                completedChunks: min(completed, totalChunks),
                totalChunks: totalChunks
            ))
        }
    }

    private func streamWhole(
        _ body: Data,
        _ handle: FileHandle,
        _ total: Int,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) throws {
        try Task.checkCancellation()
        handle.write(body)
        let written = body.count
        continuation.yield(TransferProgress(
            bytesTransferred: Int64(written),
            totalBytes: Int64(total > 0 ? total : written),
            completedChunks: 1,
            totalChunks: 1
        ))
    }
}
