import Foundation

/// TUS-resumable upload engine. Generic HTTP machinery: no Supabase, no TCA.
struct ResumableUploader: Sendable {
    private let transport: HTTPTransport
    private let retryPolicy: MediaRemoteTransferPolicy
    private let connectivity: ConnectivityMonitor
    private let sleeper: Sleeper

    init(
        transport: HTTPTransport,
        retryPolicy: MediaRemoteTransferPolicy,
        connectivity: ConnectivityMonitor,
        sleeper: Sleeper
    ) {
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.connectivity = connectivity
        self.sleeper = sleeper
    }

    func upload(
        _ request: Request,
        source: UploadSource
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, source, continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ upload: Request,
        _ source: UploadSource,
        _ continuation: AsyncThrowingStream<Event, Error>.Continuation
    ) async throws {
        let chunkSize = max(retryPolicy.chunkSize, 1)
        let length = source.size
        let totalChunks = length > 0
            ? (length + chunkSize - 1) / chunkSize
            : 0

        var uploadURL = try await createUpload(upload, length)
        var offset = 0
        var recreatesLeft = retryPolicy.maxRecreates

        while offset < length {
            try Task.checkCancellation()
            let chunkLength = min(chunkSize, length - offset)
            let chunk = try await source.read(offset, chunkLength)
            guard chunk.count == chunkLength else {
                throw Failure.invalidUploadSource
            }

            do {
                offset = try await uploadChunk(uploadURL, chunk, offset, total: length, headers: upload.commonHeaders)
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as Failure {
                if failure == .uploadConflict, recreatesLeft > 0 {
                    recreatesLeft -= 1
                    uploadURL = try await createUpload(upload, length)
                    offset = 0
                    continue
                }
                throw failure
            } catch {
                guard retryPolicy.shouldRetry(error) else { throw error }
                continuation.yield(.waitingForConnectivity)
                offset = try await recoverOffset(uploadURL, total: length, headers: upload.commonHeaders)
                continue
            }

            let completed = (offset + chunkSize - 1) / chunkSize
            continuation.yield(.progress(TransferProgress(
                bytesTransferred: Int64(offset),
                totalBytes: Int64(length),
                completedChunks: min(completed, totalChunks),
                totalChunks: totalChunks
            )))
        }
    }

    private func createUpload(_ upload: Request, _ length: Int) async throws -> URL {
        let response = try await transport.data(
            timed(TUSUploadHeaders.createRequest(
                endpoint: upload.endpoint,
                uploadLength: length,
                headers: upload.commonHeaders.merging(
                    upload.createHeaders,
                    uniquingKeysWith: { _, createValue in createValue }
                )
            ))
        )
        guard response.statusCode == 201,
              let location = response.value(forHeader: "Location"),
              let url = URL(string: location, relativeTo: upload.endpoint)
        else {
            throw Failure.invalidCreateResponse
        }
        return url.absoluteURL
    }

    private func uploadChunk(
        _ uploadURL: URL,
        _ chunk: Data,
        _ offset: Int,
        total: Int,
        headers: [String: String]
    ) async throws -> Int {
        let response = try await transport.upload(
            timed(TUSUploadHeaders.patchRequest(uploadURL: uploadURL, offset: offset, headers: headers)),
            chunk
        )
        switch response.statusCode {
        case 204, 200:
            guard let next = response.value(forHeader: "Upload-Offset").flatMap(Int.init),
                  next >= offset,
                  next <= total
            else {
                throw Failure.invalidPatchResponse
            }
            return next
        case 409, 410, 404:
            throw Failure.uploadConflict
        default:
            throw Failure.invalidPatchResponse
        }
    }

    private func fetchUploadOffset(_ uploadURL: URL, total: Int, headers: [String: String]) async throws -> Int {
        let response = try await transport.data(timed(TUSUploadHeaders.headRequest(uploadURL: uploadURL, headers: headers)))
        guard response.statusCode == 200,
              let offset = response.value(forHeader: "Upload-Offset").flatMap(Int.init),
              offset <= total
        else {
            throw Failure.invalidResumeResponse
        }
        return offset
    }

    /// Waits for connectivity to return, then re-reads the server offset,
    /// retrying within the reconnect budget. Each stall gets a full budget, so
    /// forward progress effectively refills it. Protocol-level resume failures
    /// (bad HEAD response) are not retried.
    private func recoverOffset(
        _ uploadURL: URL,
        total: Int,
        headers: [String: String]
    ) async throws -> Int {
        var lastError: Error?
        for attempt in 1 ... max(retryPolicy.maxResumes, 1) {
            try Task.checkCancellation()
            try await waitForConnectivity(timeout: retryPolicy.connectivityWaitTimeout)
            do {
                return try await fetchUploadOffset(uploadURL, total: total, headers: headers)
            } catch let failure as Failure {
                throw failure
            } catch {
                guard retryPolicy.shouldRetry(error) else { throw error }
                lastError = error
                try await sleeper.sleep(retryPolicy.resumeBackoff(attempt))
            }
        }
        throw lastError ?? Failure.invalidResumeResponse
    }

    /// Suspends until connectivity is reported online, bounded by `timeout`.
    /// Woken by the connectivity signal or the timeout, whichever comes first.
    private func waitForConnectivity(timeout: TimeInterval) async throws {
        let connectivity = connectivity
        let sleeper = sleeper
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await online in connectivity.stream() where online {
                    return true
                }
                return false
            }
            group.addTask {
                try await sleeper.sleep(timeout)
                return false
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    /// Applies the policy's per-request timeout so a mid-flight drop is noticed
    /// quickly rather than after URLSession's 60s default.
    private func timed(_ request: URLRequest) -> URLRequest {
        var request = request
        request.timeoutInterval = retryPolicy.requestTimeout
        return request
    }
}

extension ResumableUploader {
    enum Event: Equatable {
        case progress(TransferProgress)
        case waitingForConnectivity
    }

    struct Request: Equatable, Sendable {
        let endpoint: URL
        /// Sent with every request in the upload (e.g. authentication).
        let commonHeaders: [String: String]
        /// Sent only with the create (POST) request.
        let createHeaders: [String: String]
    }

    struct UploadSource: Sendable {
        typealias Read = @Sendable (_ offset: Int, _ length: Int) async throws -> Data

        let size: Int
        let read: Read
    }

    enum Failure: Error, Equatable {
        case invalidUploadSource
        case invalidCreateResponse
        case invalidPatchResponse
        case invalidResumeResponse
        case uploadConflict
    }
}

extension ResumableUploader.UploadSource {
    static func file(
        _ file: URL,
        fileManager: FileManager
    ) throws -> ResumableUploader.UploadSource {
        let attributes = try fileManager.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let read: Read = { offset, length in
            let handle = try FileHandle(forReadingFrom: file)
            do {
                try handle.seek(toOffset: UInt64(offset))
                let data = handle.readData(ofLength: length)
                try handle.close()
                return data
            } catch {
                try? handle.close()
                throw error
            }
        }

        return ResumableUploader.UploadSource(size: size, read: read)
    }
}
