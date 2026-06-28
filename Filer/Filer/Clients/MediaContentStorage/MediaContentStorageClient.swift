import Dependencies
import Foundation

struct MediaContentStorageClient: Sendable {
    typealias StoreImport = @Sendable (_ key: String, _ data: Data) async throws -> StoredContent
    typealias ListImports = @Sendable () async throws -> [StoredContent]
    typealias RemoveImport = @Sendable (_ key: String) async throws -> Void
    typealias ImportUploadSource = @Sendable (_ key: String) async throws -> UploadSource
    typealias PrepareDownloadTarget = @Sendable (_ key: String) async throws -> DownloadTarget
    typealias DownloadOffset = @Sendable (_ key: String) async throws -> UInt64
    typealias WriteDownload = @Sendable (_ key: String, _ data: Data, _ offset: UInt64) async throws -> Void

    var storeImport: StoreImport
    var listImports: ListImports
    var removeImport: RemoveImport
    var importUploadSource: ImportUploadSource
    var prepareDownloadTarget: PrepareDownloadTarget
    var downloadOffset: DownloadOffset
    var writeDownload: WriteDownload

    init(
        storeImport: @escaping StoreImport,
        listImports: @escaping ListImports,
        removeImport: @escaping RemoveImport,
        importUploadSource: @escaping ImportUploadSource,
        prepareDownloadTarget: @escaping PrepareDownloadTarget,
        downloadOffset: @escaping DownloadOffset,
        writeDownload: @escaping WriteDownload
    ) {
        self.storeImport = storeImport
        self.listImports = listImports
        self.removeImport = removeImport
        self.importUploadSource = importUploadSource
        self.prepareDownloadTarget = prepareDownloadTarget
        self.downloadOffset = downloadOffset
        self.writeDownload = writeDownload
    }
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
