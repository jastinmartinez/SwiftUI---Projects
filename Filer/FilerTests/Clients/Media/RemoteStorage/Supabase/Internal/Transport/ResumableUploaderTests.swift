@testable import Filer
import Foundation
import Testing

@Suite(.serialized) struct ResumableUploaderTests {
    @Test func postCreationSendsTusHeaders() async throws {
        let size = 2 * 1024 * 1024
        let captured = LockedBox<[URLRequest]>([])
        let transport = HTTPTransport(
            data: { request in
                captured.mutate { $0.append(request) }
                return try HTTPResponse(
                    statusCode: 201,
                    headers: ["Location": uploadURL().absoluteString],
                    body: Data()
                )
            },
            upload: { request, _ in
                captured.mutate { $0.append(request) }
                return HTTPResponse(
                    statusCode: 204,
                    headers: ["Upload-Offset": "\(size)"],
                    body: Data()
                )
            }
        )
        let uploader = makeUploader(transport: transport)

        for try await _ in try uploader.upload(
            ResumableUploader.Request(
                endpoint: endpoint(),
                commonHeaders: [:],
                createHeaders: ["Upload-Metadata": "name dGVzdA=="]
            ),
            source: source(bytes: size)
        ) {}

        let post = try #require(captured.value.first { $0.httpMethod == "POST" })
        #expect(post.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
        #expect(post.value(forHTTPHeaderField: "Upload-Length") == "\(size)")
        #expect(post.value(forHTTPHeaderField: "Upload-Metadata") == "name dGVzdA==")
    }

    @Test func patchCarriesProviderHeaders() async throws {
        let size = MediaRemoteTransferPolicy.default.chunkSize
        let captured = LockedBox<[URLRequest]>([])
        let transport = HTTPTransport(
            data: { request in
                captured.mutate { $0.append(request) }
                return try HTTPResponse(
                    statusCode: 201,
                    headers: ["Location": uploadURL().absoluteString],
                    body: Data()
                )
            },
            upload: { request, _ in
                captured.mutate { $0.append(request) }
                return HTTPResponse(
                    statusCode: 204,
                    headers: ["Upload-Offset": "\(size)"],
                    body: Data()
                )
            }
        )
        let uploader = makeUploader(transport: transport)

        for try await _ in try uploader.upload(
            ResumableUploader.Request(
                endpoint: endpoint(),
                commonHeaders: ["apikey": "anon-key", "Authorization": "Bearer anon-key"],
                createHeaders: ["x-upsert": "true"]
            ),
            source: source(bytes: size)
        ) {}

        let post = try #require(captured.value.first { $0.httpMethod == "POST" })
        let patch = try #require(captured.value.first { $0.httpMethod == "PATCH" })
        // Common headers ride every request...
        #expect(patch.value(forHTTPHeaderField: "apikey") == "anon-key")
        #expect(patch.value(forHTTPHeaderField: "Authorization") == "Bearer anon-key")
        // ...but create-only headers stay on the POST.
        #expect(post.value(forHTTPHeaderField: "x-upsert") == "true")
        #expect(patch.value(forHTTPHeaderField: "x-upsert") == nil)
    }

    @Test func patchOffsetSequenceAcrossChunkBoundaries() async throws {
        let size = 14 * 1024 * 1024
        let chunk = MediaRemoteTransferPolicy.default.chunkSize
        let offsets = LockedBox<[String]>([])
        let transport = HTTPTransport(
            data: { _ in
                try HTTPResponse(
                    statusCode: 201,
                    headers: ["Location": uploadURL().absoluteString],
                    body: Data()
                )
            },
            upload: { request, _ in
                let offset = try #require(request.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int.init))
                offsets.mutate { $0.append("\(offset)") }
                let sent = offset + min(chunk, size - offset)
                return HTTPResponse(
                    statusCode: 204,
                    headers: ["Upload-Offset": "\(sent)"],
                    body: Data()
                )
            }
        )
        let uploader = makeUploader(transport: transport)
        var last: TransferProgress?

        for try await progress in try uploader.upload(
            ResumableUploader.Request(endpoint: endpoint(), commonHeaders: [:], createHeaders: [:]),
            source: source(bytes: size)
        ) {
            last = progress
        }

        #expect(offsets.value == ["0", "\(chunk)", "\(2 * chunk)"])
        #expect(last?.bytesTransferred == Int64(size))
        #expect(last?.totalBytes == Int64(size))
        #expect(last?.completedChunks == 3)
        #expect(last?.totalChunks == 3)
    }

    @Test func resumesAfterInjectedFailureViaHead() async throws {
        let size = 12 * 1024 * 1024
        let chunk = MediaRemoteTransferPolicy.default.chunkSize
        let didFail = LockedBox<Bool>(false)
        let heads = LockedBox<Int>(0)
        let transport = HTTPTransport(
            data: { request in
                switch request.httpMethod {
                case "POST":
                    return try HTTPResponse(
                        statusCode: 201,
                        headers: ["Location": uploadURL().absoluteString],
                        body: Data()
                    )
                case "HEAD":
                    heads.mutate { $0 += 1 }
                    return HTTPResponse(
                        statusCode: 200,
                        headers: ["Upload-Offset": "\(chunk)"],
                        body: Data()
                    )
                default:
                    throw URLError(.badServerResponse)
                }
            },
            upload: { request, _ in
                let offset = try #require(request.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int.init))
                if offset == chunk, didFail.value == false {
                    didFail.mutate { $0 = true }
                    throw URLError(.networkConnectionLost)
                }
                return HTTPResponse(
                    statusCode: 204,
                    headers: ["Upload-Offset": "\(offset + min(chunk, size - offset))"],
                    body: Data()
                )
            }
        )
        let uploader = makeUploader(transport: transport)
        var progresses: [TransferProgress] = []

        for try await progress in try uploader.upload(
            ResumableUploader.Request(endpoint: endpoint(), commonHeaders: [:], createHeaders: [:]),
            source: source(bytes: size)
        ) {
            progresses.append(progress)
        }

        #expect(heads.value == 1)
        for (previous, next) in zip(progresses, progresses.dropFirst()) {
            #expect(next.bytesTransferred >= previous.bytesTransferred)
            #expect(next.completedChunks >= previous.completedChunks)
        }
        let last = try #require(progresses.last)
        #expect(last.completedChunks == last.totalChunks)
        #expect(last.bytesTransferred == Int64(size))
    }

    @Test func recreatesUploadOn409() async throws {
        let size = MediaRemoteTransferPolicy.default.chunkSize
        let posts = LockedBox<Int>(0)
        let conflicted = LockedBox<Bool>(false)
        let transport = HTTPTransport(
            data: { _ in
                posts.mutate { $0 += 1 }
                return try HTTPResponse(
                    statusCode: 201,
                    headers: ["Location": uploadURL().absoluteString],
                    body: Data()
                )
            },
            upload: { request, _ in
                if conflicted.value == false {
                    conflicted.mutate { $0 = true }
                    return HTTPResponse(statusCode: 409, headers: [:], body: Data())
                }
                let offset = try #require(request.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int.init))
                return HTTPResponse(
                    statusCode: 204,
                    headers: ["Upload-Offset": "\(offset + size)"],
                    body: Data()
                )
            }
        )
        let uploader = makeUploader(transport: transport)
        var last: TransferProgress?

        for try await progress in try uploader.upload(
            ResumableUploader.Request(endpoint: endpoint(), commonHeaders: [:], createHeaders: [:]),
            source: source(bytes: size)
        ) {
            last = progress
        }

        #expect(posts.value == 2)
        #expect(last?.bytesTransferred == Int64(size))
    }

    @Test func invalidPatchOffsetFailsWithoutRetrying() async throws {
        let size = MediaRemoteTransferPolicy.default.chunkSize
        let heads = LockedBox<Int>(0)
        let transport = HTTPTransport(
            data: { request in
                if request.httpMethod == "HEAD" {
                    heads.mutate { $0 += 1 }
                }
                return try HTTPResponse(
                    statusCode: 201,
                    headers: ["Location": uploadURL().absoluteString],
                    body: Data()
                )
            },
            upload: { _, _ in
                HTTPResponse(
                    statusCode: 204,
                    headers: ["Upload-Offset": "\(size + 1)"],
                    body: Data()
                )
            }
        )
        let uploader = makeUploader(transport: transport)

        await #expect(throws: ResumableUploader.Failure.invalidPatchResponse) {
            for try await _ in try uploader.upload(
                ResumableUploader.Request(endpoint: endpoint(), commonHeaders: [:], createHeaders: [:]),
                source: source(bytes: size)
            ) {}
        }
        #expect(heads.value == 0)
    }

    @Test func shortReadFailsBeforeUploadingChunk() async throws {
        let uploads = LockedBox<Int>(0)
        let transport = HTTPTransport(
            data: { _ in
                try HTTPResponse(
                    statusCode: 201,
                    headers: ["Location": uploadURL().absoluteString],
                    body: Data()
                )
            },
            upload: { _, _ in
                uploads.mutate { $0 += 1 }
                return HTTPResponse(statusCode: 204, headers: [:], body: Data())
            }
        )
        let uploader = makeUploader(transport: transport)
        let shortSource = ResumableUploader.UploadSource(
            size: 4,
            read: { _, _ in Data([1, 2]) }
        )

        await #expect(throws: ResumableUploader.Failure.invalidUploadSource) {
            for try await _ in try uploader.upload(
                ResumableUploader.Request(endpoint: endpoint(), commonHeaders: [:], createHeaders: [:]),
                source: shortSource
            ) {}
        }
        #expect(uploads.value == 0)
    }

    // MARK: - Helpers

    private func makeUploader(transport: HTTPTransport) -> ResumableUploader {
        ResumableUploader(
            transport: transport,
            retryPolicy: .default,
            connectivity: .alwaysOnline,
            sleeper: .immediate
        )
    }

    private func endpoint() throws -> URL {
        try #require(URL(string: "https://example.supabase.co/storage/v1/upload/resumable"))
    }

    private func uploadURL() throws -> URL {
        try #require(URL(string: "https://example.supabase.co/storage/v1/upload/resumable/upload-1"))
    }

    private func source(bytes size: Int) -> ResumableUploader.UploadSource {
        ResumableUploader.UploadSource(
            size: size,
            read: { offset, length in
                Data(repeating: UInt8(offset % 255), count: length)
            }
        )
    }
}
