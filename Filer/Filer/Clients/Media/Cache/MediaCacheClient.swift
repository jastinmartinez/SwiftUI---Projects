import Dependencies
import Foundation

struct MediaCacheClient: Sendable {
    typealias StoreImport = @Sendable (_ key: String, _ data: Data) async throws -> StoredContent
    typealias ListImports = @Sendable () async throws -> [StoredContent]
    typealias RemoveImport = @Sendable (_ key: String) async throws -> Void
    typealias UploadSourceFor = @Sendable (_ key: String) async throws -> UploadSource
    typealias ReadUpload = @Sendable (_ key: String, _ offset: Int, _ length: Int) async throws -> Data
    typealias PrepareDownload = @Sendable (_ key: String) async throws -> DownloadTarget
    typealias DownloadOffset = @Sendable (_ key: String) async throws -> UInt64
    typealias WriteDownload = @Sendable (_ key: String, _ data: Data, _ offset: UInt64) async throws -> Void
    typealias Store = @Sendable (_ media: MediaImportClient.LoadedMedia) async throws -> ImportedMedia
    typealias RemoveExpired = @Sendable () async throws -> Void

    var storeImport: StoreImport
    var listImports: ListImports
    var removeImport: RemoveImport
    var uploadSource: UploadSourceFor
    var readUpload: ReadUpload
    var prepareDownload: PrepareDownload
    var downloadOffset: DownloadOffset
    var writeDownload: WriteDownload
    var store: Store
    var removeExpired: RemoveExpired

    init(
        storeImport: @escaping StoreImport,
        listImports: @escaping ListImports,
        removeImport: @escaping RemoveImport,
        uploadSource: @escaping UploadSourceFor,
        readUpload: @escaping ReadUpload,
        prepareDownload: @escaping PrepareDownload,
        downloadOffset: @escaping DownloadOffset,
        writeDownload: @escaping WriteDownload,
        store: @escaping Store,
        removeExpired: @escaping RemoveExpired
    ) {
        self.storeImport = storeImport
        self.listImports = listImports
        self.removeImport = removeImport
        self.uploadSource = uploadSource
        self.readUpload = readUpload
        self.prepareDownload = prepareDownload
        self.downloadOffset = downloadOffset
        self.writeDownload = writeDownload
        self.store = store
        self.removeExpired = removeExpired
    }
}

extension MediaCacheClient {
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
}

extension DependencyValues {
    var mediaCache: MediaCacheClient {
        get { self[MediaCacheClient.self] }
        set { self[MediaCacheClient.self] = newValue }
    }
}
