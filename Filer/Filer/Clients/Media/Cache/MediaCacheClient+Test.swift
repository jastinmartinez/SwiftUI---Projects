import Dependencies
import Foundation
import Synchronization

extension MediaCacheClient: TestDependencyKey {
    static var testValue: MediaCacheClient {
        let state = Mutex<State>(State())

        return MediaCacheClient(
            storeImport: { key, data in
                state.withLock { state in
                    let stored = StoredContent(key: key, size: Int64(data.count), modifiedAt: nil, localURL: Self.importURL(for: key))
                    state.imports[key] = ImportRecord(stored: stored, data: data)
                    return stored
                }
            },
            listImports: { state.withLock { $0.imports.values.map(\.stored).sorted { $0.key < $1.key } } },
            removeImport: { key in state.withLock { $0.imports[key] = nil } },
            uploadSource: { key in
                try state.withLock { state in
                    guard let record = state.imports[key] else { throw MissingContent(key: key) }
                    return UploadSource(key: key, localURL: record.stored.localURL, size: record.stored.size)
                }
            },
            readUpload: { key, offset, length in
                try state.withLock { state in
                    guard let record = state.imports[key] else { throw MissingContent(key: key) }
                    let start = min(offset, record.data.count)
                    let end = min(offset + length, record.data.count)
                    return record.data.subdata(in: start ..< end)
                }
            },
            prepareDownload: { key in
                state.withLock { state in
                    if state.downloads[key] == nil { state.downloads[key] = Data() }
                    return DownloadTarget(key: key, localURL: Self.downloadURL(for: key))
                }
            },
            downloadOffset: { key in state.withLock { UInt64($0.downloads[key]?.count ?? 0) } },
            writeDownload: { key, data, offset in
                try state.withLock { state in
                    guard var stored = state.downloads[key] else { throw MissingContent(key: key) }
                    let offset = Int(offset)
                    if stored.count < offset { stored.append(Data(repeating: 0, count: offset - stored.count)) }
                    if stored.count < offset + data.count { stored.append(Data(repeating: 0, count: offset + data.count - stored.count)) }
                    stored.replaceSubrange(offset ..< offset + data.count, with: data)
                    state.downloads[key] = stored
                }
            },
            store: { payload in
                try state.withLock { state in
                    let stored = StoredContent(key: payload.metadata.id, size: Int64(payload.data.count), modifiedAt: nil, localURL: Self.importURL(for: payload.metadata.id))
                    state.imports[payload.metadata.id] = ImportRecord(stored: stored, data: payload.data)
                    return ImportedMedia(metadata: payload.metadata.with(size: stored.size), fileURL: stored.localURL)
                }
            },
            removeExpired: {}
        )
    }
}

private extension MediaCacheClient {
    struct ImportRecord {
        let stored: StoredContent
        let data: Data
    }

    struct State {
        var imports: [String: ImportRecord] = [:]
        var downloads: [String: Data] = [:]
    }

    static func importURL(for key: String) -> URL { URL(fileURLWithPath: "/memory/imports").appending(path: key) }
    static func downloadURL(for key: String) -> URL { URL(fileURLWithPath: "/memory/downloads").appending(path: key) }
}
