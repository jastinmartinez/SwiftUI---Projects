import Dependencies
import Foundation

struct MediaContentStorageClient: Sendable {
    typealias StoreImport = @Sendable (_ key: String, _ data: Data) async throws -> StoredContent
    typealias ListImports = @Sendable () async throws -> [StoredContent]
    typealias RemoveImport = @Sendable (_ key: String) async throws -> Void
    typealias ImportUploadSource = @Sendable (_ key: String) async throws -> UploadSource
    typealias PrepareDownloadTarget = @Sendable (_ key: String) async throws -> DownloadTarget
    typealias WriteDownload = @Sendable (_ key: String, _ data: Data, _ offset: UInt64) async throws -> Void

    var storeImport: StoreImport = { _, _ in throw Unimplemented() }
    var listImports: ListImports = { throw Unimplemented() }
    var removeImport: RemoveImport = { _ in throw Unimplemented() }
    var importUploadSource: ImportUploadSource = { _ in throw Unimplemented() }
    var prepareDownloadTarget: PrepareDownloadTarget = { _ in throw Unimplemented() }
    var writeDownload: WriteDownload = { _, _, _ in throw Unimplemented() }
}

extension MediaContentStorageClient {
    struct StoredContent: Equatable, Sendable {
        let key: String
        let size: Int64
        let modifiedAt: Date?
        let localURL: URL
    }

    struct UploadSource: Equatable, Sendable {
        let key: String
        let localURL: URL
        let size: Int64
    }

    struct DownloadTarget: Equatable, Sendable {
        let key: String
        let localURL: URL
    }

    struct MissingContent: Error, Equatable {
        let key: String
    }

    struct Unimplemented: Error {}
}

extension DependencyValues {
    var mediaContentStorage: MediaContentStorageClient {
        get { self[MediaContentStorageClient.self] }
        set { self[MediaContentStorageClient.self] = newValue }
    }
}
