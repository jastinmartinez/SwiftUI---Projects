import Dependencies
import Foundation

extension MediaCacheClient: DependencyKey {
    static let liveValue = live()

    static func live(
        cacheStore: MediaCacheStore = MediaCacheStore(),
        directories: MediaCacheDirectories = .temporary(),
        now: @escaping @Sendable () -> Date = Date.init,
        policy: MediaCachePolicy = .default
    ) -> MediaCacheClient {
        @Sendable func loadImports() async throws -> [StoredContent] {
            let urls = try await cacheStore.contents(of: directories.imports)
            var result: [StoredContent] = []
            for url in urls {
                await result.append(
                    StoredContent(
                        key: url.lastPathComponent,
                        size: cacheStore.size(at: url) ?? 0,
                        modifiedAt: cacheStore.modificationDate(at: url),
                        localURL: url
                    )
                )
            }
            return result
        }

        return MediaCacheClient(
            storeImport: { key, data in
                let url = directories.importURL(for: key)
                try await cacheStore.write(data, to: url)
                return await StoredContent(
                    key: key,
                    size: cacheStore.size(at: url) ?? Int64(data.count),
                    modifiedAt: cacheStore.modificationDate(at: url),
                    localURL: url
                )
            },
            listImports: { try await loadImports() },
            removeImport: { key in try await cacheStore.remove(at: directories.importURL(for: key)) },
            uploadSource: { key in
                let url = directories.importURL(for: key)
                guard await cacheStore.exists(at: url) else { throw MissingContent(key: key) }
                return await UploadSource(key: key, localURL: url, size: cacheStore.size(at: url) ?? 0)
            },
            readUpload: { key, offset, length in
                let url = directories.importURL(for: key)
                guard await cacheStore.exists(at: url) else { throw MissingContent(key: key) }
                return try await cacheStore.read(at: url, offset: offset, length: length)
            },
            prepareDownload: { key in
                let url = directories.downloadURL(for: key)
                try await cacheStore.makeFileIfNeeded(at: url)
                return DownloadTarget(key: key, localURL: url)
            },
            downloadOffset: { key in
                await UInt64(cacheStore.size(at: directories.downloadURL(for: key)) ?? 0)
            },
            writeDownload: { key, data, offset in
                try await cacheStore.write(data, to: directories.downloadURL(for: key), at: offset)
            },
            store: { payload in
                let url = directories.importURL(for: payload.metadata.id)
                try await cacheStore.write(payload.data, to: url)
                return await ImportedMedia(
                    metadata: payload.metadata.with(size: cacheStore.size(at: url) ?? Int64(payload.data.count)),
                    fileURL: url
                )
            },
            removeExpired: {
                let expired = try await policy.expiredKeys(in: loadImports(), now: now())
                for key in expired {
                    try await cacheStore.remove(at: directories.importURL(for: key))
                }
            }
        )
    }
}
