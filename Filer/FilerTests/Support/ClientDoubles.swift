@testable import Filer
import Foundation

/// Thrown by a stubbed endpoint that a test expects never to be reached, so an
/// accidental call fails loudly instead of silently passing.
struct NotStubbed: Error {
    let endpoint: String
    init(_ endpoint: String = "") { self.endpoint = endpoint }
}

// MARK: - MediaTransferClient

extension MediaTransferClient {
    /// Every endpoint fails loudly. Start here and override only the one under test.
    static var failing: MediaTransferClient {
        MediaTransferClient(
            list: { throw NotStubbed("mediaTransfer.list") },
            upload: { _ in AsyncThrowingStream { $0.finish(throwing: NotStubbed("mediaTransfer.upload")) } },
            download: { _ in AsyncThrowingStream { $0.finish(throwing: NotStubbed("mediaTransfer.download")) } }
        )
    }

    static func failing(list: @escaping List) -> MediaTransferClient {
        var client = failing
        client.list = list
        return client
    }

    static func failing(upload: @escaping Upload) -> MediaTransferClient {
        var client = failing
        client.upload = upload
        return client
    }

    static func failing(download: @escaping Download) -> MediaTransferClient {
        var client = failing
        client.download = download
        return client
    }
}

// MARK: - MediaImportClient

extension MediaImportClient {
    /// Loading fails loudly — for features that drive the import lifecycle directly.
    static var failing: MediaImportClient {
        MediaImportClient(load: { _ in throw NotStubbed("mediaImport.load") })
    }
}

// MARK: - MediaCacheClient

extension MediaCacheClient {
    /// Every endpoint fails loudly — for features that must not touch the cache.
    static var failing: MediaCacheClient {
        MediaCacheClient(
            storeImport: { _, _ in throw NotStubbed("mediaCache.storeImport") },
            listImports: { throw NotStubbed("mediaCache.listImports") },
            removeImport: { _ in throw NotStubbed("mediaCache.removeImport") },
            uploadSource: { _ in throw NotStubbed("mediaCache.uploadSource") },
            readUpload: { _, _, _ in throw NotStubbed("mediaCache.readUpload") },
            prepareDownload: { _ in throw NotStubbed("mediaCache.prepareDownload") },
            downloadOffset: { _ in throw NotStubbed("mediaCache.downloadOffset") },
            writeDownload: { _, _, _ in throw NotStubbed("mediaCache.writeDownload") },
            store: { _ in throw NotStubbed("mediaCache.store") },
            removeExpired: { throw NotStubbed("mediaCache.removeExpired") }
        )
    }
}
