@testable import Filer
import Foundation
import Testing

@Suite(.serialized) struct ResumableUploaderTests {
    private let endpoint = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
    private let uploadURL = URL(string: "https://example.supabase.co/storage/v1/upload/resumable/upload-1")!

    @Test func postCreationSendsTusHeaders() async throws {
        let size = 2 * 1024 * 1024
        let file = try makeFile(bytes: size)
        let captured = LockedBox<[URLRequest]>([])

        StubURLProtocol.handler = { req in
            captured.mutate { $0.append(req) }
            if req.httpMethod == "POST" {
                return (Self.resp(req.url!, 201, ["Location": uploadURL.absoluteString]), Data())
            }
            return (Self.resp(req.url!, 204, ["Upload-Offset": "\(size)"]), Data())
        }
        defer { StubURLProtocol.handler = nil }

        let uploader = ResumableUploader(session: StubURLProtocol.session())
        for try await _ in uploader.upload(file, to: endpoint,
                                           headers: ["Upload-Metadata": "name dGVzdA=="]) {}

        let post = try #require(captured.value.first { $0.httpMethod == "POST" })
        #expect(post.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
        #expect(post.value(forHTTPHeaderField: "Upload-Length") == "\(size)")
        #expect(post.value(forHTTPHeaderField: "Upload-Metadata") == "name dGVzdA==")
    }

    @Test func patchOffsetSequenceAcrossChunkBoundaries() async throws {
        let size = 14 * 1024 * 1024 // 6 + 6 + 2
        let chunk = TransferProgress.chunkSize
        let file = try makeFile(bytes: size)
        let offsets = LockedBox<[String]>([])

        StubURLProtocol.handler = { req in
            if req.httpMethod == "POST" {
                return (Self.resp(req.url!, 201, ["Location": uploadURL.absoluteString]), Data())
            }
            let off = req.value(forHTTPHeaderField: "Upload-Offset") ?? "?"
            offsets.mutate { $0.append(off) }
            let sent = Int(off)! + min(chunk, size - Int(off)!)
            return (Self.resp(req.url!, 204, ["Upload-Offset": "\(sent)"]), Data())
        }
        defer { StubURLProtocol.handler = nil }

        let uploader = ResumableUploader(session: StubURLProtocol.session())
        var last: TransferProgress?
        for try await p in uploader.upload(file, to: endpoint, headers: [:], chunkSize: chunk) {
            last = p
        }

        #expect(offsets.value == ["0", "\(chunk)", "\(2 * chunk)"])
        #expect(last?.bytesTransferred == Int64(size))
        #expect(last?.totalBytes == Int64(size))
        #expect(last?.completedChunks == 3)
        #expect(last?.totalChunks == 3)
    }

    @Test func resumesAfterInjectedFailureViaHead() async throws {
        let size = 12 * 1024 * 1024 // 6 + 6
        let chunk = TransferProgress.chunkSize
        let file = try makeFile(bytes: size)
        let didFail = LockedBox<Bool>(false)
        let heads = LockedBox<Int>(0)

        StubURLProtocol.handler = { req in
            switch req.httpMethod {
            case "POST":
                return (Self.resp(req.url!, 201, ["Location": uploadURL.absoluteString]), Data())
            case "HEAD":
                heads.mutate { $0 += 1 }
                return (Self.resp(req.url!, 200, ["Upload-Offset": "\(chunk)"]), Data())
            default: // PATCH
                let off = Int(req.value(forHTTPHeaderField: "Upload-Offset") ?? "0")!
                if off == chunk, didFail.value == false {
                    didFail.mutate { $0 = true }
                    throw URLError(.networkConnectionLost) // transient blip on 2nd chunk
                }
                return (Self.resp(req.url!, 204, ["Upload-Offset": "\(off + min(chunk, size - off))"]), Data())
            }
        }
        defer { StubURLProtocol.handler = nil }

        let uploader = ResumableUploader(session: StubURLProtocol.session())
        var progresses: [TransferProgress] = []
        for try await p in uploader.upload(file, to: endpoint, headers: [:], chunkSize: chunk) {
            progresses.append(p)
        }

        #expect(heads.value == 1) // one resume probe

        // Robust assertions: don't pin the exact intermediate completedChunks (the resume
        // path may re-yield a chunk). Require monotonic non-decreasing progress across
        // yields, and a final progress that reflects the whole file.
        for (prev, next) in zip(progresses, progresses.dropFirst()) {
            #expect(next.bytesTransferred >= prev.bytesTransferred)
            #expect(next.completedChunks >= prev.completedChunks)
        }
        let last = try #require(progresses.last)
        #expect(last.completedChunks == last.totalChunks)
        #expect(last.bytesTransferred == last.totalBytes)
        #expect(last.bytesTransferred == Int64(size))
    }

    @Test func recreatesUploadOn409() async throws {
        let size = TransferProgress.chunkSize
        let chunk = TransferProgress.chunkSize
        let file = try makeFile(bytes: size)
        let posts = LockedBox<Int>(0)
        let conflicted = LockedBox<Bool>(false)

        StubURLProtocol.handler = { req in
            switch req.httpMethod {
            case "POST":
                posts.mutate { $0 += 1 }
                return (Self.resp(req.url!, 201, ["Location": uploadURL.absoluteString]), Data())
            default: // PATCH
                if conflicted.value == false {
                    conflicted.mutate { $0 = true }
                    return (Self.resp(req.url!, 409, [:]), Data()) // concurrent / expired
                }
                let off = Int(req.value(forHTTPHeaderField: "Upload-Offset") ?? "0")!
                return (Self.resp(req.url!, 204, ["Upload-Offset": "\(off + chunk)"]), Data())
            }
        }
        defer { StubURLProtocol.handler = nil }

        let uploader = ResumableUploader(session: StubURLProtocol.session())
        var last: TransferProgress?
        for try await p in uploader.upload(file, to: endpoint, headers: [:], chunkSize: chunk) {
            last = p
        }

        #expect(posts.value == 2) // recreated after 409
        #expect(last?.bytesTransferred == Int64(size))
    }

    // MARK: - Helpers

    private static func resp(_ url: URL, _ code: Int, _ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func makeFile(bytes: Int) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "\(UUID().uuidString).bin")
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        return url
    }
}
