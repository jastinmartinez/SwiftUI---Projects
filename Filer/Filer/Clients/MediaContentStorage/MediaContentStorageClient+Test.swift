import Dependencies
import Foundation
import Synchronization

extension MediaContentStorageClient: TestDependencyKey {
    static var testValue: MediaContentStorageClient {
        let state = Mutex<State>(State())

        let storeImport: StoreImport = { (key: String, data: Data) async throws -> StoredContent in
            state.withLock { state in
                let stored = StoredContent(
                    key: key,
                    size: Int64(data.count),
                    modifiedAt: nil,
                    localURL: Self.importURL(for: key)
                )
                state.imports[key] = ImportRecord(stored: stored, data: data)
                return stored
            }
        }

        let listImports: ListImports = { () async throws -> [StoredContent] in
            state.withLock { state in
                state.imports.values.map(\.stored).sorted { $0.key < $1.key }
            }
        }

        let removeImport: RemoveImport = { (key: String) async throws in
            state.withLock { state in
                state.imports[key] = nil
            }
        }

        let importUploadSource: ImportUploadSource = { (key: String) async throws -> UploadSource in
            try state.withLock { state in
                guard let record = state.imports[key] else {
                    throw MissingContent(key: key)
                }
                return UploadSource(
                    key: key,
                    localURL: record.stored.localURL,
                    size: record.stored.size
                )
            }
        }

        let prepareDownloadTarget: PrepareDownloadTarget = { (key: String) async throws -> DownloadTarget in
            state.withLock { state in
                if state.downloads[key] == nil {
                    state.downloads[key] = Data()
                }
                return DownloadTarget(key: key, localURL: Self.downloadURL(for: key))
            }
        }

        let downloadOffset: DownloadOffset = { (key: String) async throws -> UInt64 in
            state.withLock { state in
                UInt64(state.downloads[key]?.count ?? 0)
            }
        }

        let writeDownload: WriteDownload = { (key: String, data: Data, offset: UInt64) async throws in
            try state.withLock { state in
                guard var stored = state.downloads[key] else {
                    throw MissingContent(key: key)
                }
                let offset = Int(offset)
                if stored.count < offset {
                    stored.append(Data(repeating: 0, count: offset - stored.count))
                }
                if stored.count < offset + data.count {
                    stored.append(Data(repeating: 0, count: offset + data.count - stored.count))
                }
                stored.replaceSubrange(offset ..< offset + data.count, with: data)
                state.downloads[key] = stored
            }
        }

        return MediaContentStorageClient(
            storeImport: storeImport,
            listImports: listImports,
            removeImport: removeImport,
            importUploadSource: importUploadSource,
            prepareDownloadTarget: prepareDownloadTarget,
            downloadOffset: downloadOffset,
            writeDownload: writeDownload
        )
    }
}

private extension MediaContentStorageClient {
    struct ImportRecord {
        let stored: StoredContent
        let data: Data
    }

    struct State {
        var imports: [String: ImportRecord] = [:]
        var downloads: [String: Data] = [:]
    }

    static func importURL(for key: String) -> URL {
        URL(fileURLWithPath: "/memory/imports").appending(path: key)
    }

    static func downloadURL(for key: String) -> URL {
        URL(fileURLWithPath: "/memory/downloads").appending(path: key)
    }
}
