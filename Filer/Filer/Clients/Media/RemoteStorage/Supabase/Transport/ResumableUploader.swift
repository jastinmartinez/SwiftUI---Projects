import Foundation

/// TUS-resumable upload engine. Generic HTTP machinery: no Supabase, no TCA.
struct ResumableUploader: Sendable {
    private let transport: HTTPTransport
    private let retryPolicy: MediaRemoteTransferPolicy

    init(
        transport: HTTPTransport,
        retryPolicy: MediaRemoteTransferPolicy
    ) {
        self.transport = transport
        self.retryPolicy = retryPolicy
    }

    func upload(
        _ request: Request,
        source: UploadSource,
        chunkSize: Int
    ) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, source, max(chunkSize, 1), continuation)
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
        _ chunkSize: Int,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws {
        let length = source.size
        let totalChunks = length > 0
            ? (length + chunkSize - 1) / chunkSize
            : 0

        var uploadURL = try await create(upload, length)
        var offset = 0
        var resumesLeft = retryPolicy.maxResumes
        var recreatesLeft = retryPolicy.maxRecreates

        while offset < length {
            try Task.checkCancellation()
            let window = min(chunkSize, length - offset)
            let body = try await source.read(offset, window)
            guard body.count == window else {
                throw Failure.invalidUploadSource
            }

            do {
                offset = try await patch(uploadURL, body, offset, total: length)
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as Failure {
                if failure == .uploadConflict, recreatesLeft > 0 {
                    recreatesLeft -= 1
                    uploadURL = try await create(upload, length)
                    offset = 0
                    continue
                }
                throw failure
            } catch {
                guard retryPolicy.shouldRetry(error), resumesLeft > 0 else {
                    throw error
                }
                resumesLeft -= 1
                offset = try await head(uploadURL, total: length)
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

    private func create(_ upload: Request, _ length: Int) async throws -> URL {
        let response = try await transport.data(
            TUSUploadHeaders.createRequest(
                endpoint: upload.endpoint,
                uploadLength: length,
                headers: upload.headers
            )
        )
        guard response.statusCode == 201,
              let location = response.value(forHeader: "Location"),
              let url = URL(string: location, relativeTo: upload.endpoint)
        else {
            throw Failure.invalidCreateResponse
        }
        return url.absoluteURL
    }

    private func patch(
        _ uploadURL: URL,
        _ body: Data,
        _ offset: Int,
        total: Int
    ) async throws -> Int {
        let response = try await transport.upload(
            TUSUploadHeaders.patchRequest(uploadURL: uploadURL, offset: offset),
            body
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

    private func head(_ uploadURL: URL, total: Int) async throws -> Int {
        let response = try await transport.data(TUSUploadHeaders.headRequest(uploadURL: uploadURL))
        guard response.statusCode == 200,
              let offset = response.value(forHeader: "Upload-Offset").flatMap(Int.init),
              offset <= total
        else {
            throw Failure.invalidResumeResponse
        }
        return offset
    }
}

extension ResumableUploader {
    struct Request: Equatable, Sendable {
        let endpoint: URL
        let headers: [String: String]
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
