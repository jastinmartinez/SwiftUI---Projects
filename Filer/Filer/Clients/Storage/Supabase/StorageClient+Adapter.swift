import Foundation
import Storage

// MARK: - FileObject → FileItem

// framework → domain (list). FileObject.metadata is an untyped [String: AnyJSON]? —
// no typed .size/.mimetype/.displayName members; read by key with AnyJSON unwrapping.
// Non-media objects map to nil so the live `list` compactMaps them away (§12).
extension FileItem {
    init?(_ object: FileObject) {
        let meta = object.metadata
        guard let kind = FileItem.Kind(mimeType: meta?["mimetype"]?.stringValue) else { return nil }
        self.init(
            id: object.name,
            name: meta?["name"]?.stringValue ?? object.name,
            kind: kind,
            size: meta?["size"]?.doubleValue.map(Int64.init),
            status: .remote
        )
    }
}

// MARK: - TransferProgress stream → StorageClient events

extension AsyncThrowingStream where Element == TransferProgress, Failure == Error {
    func mapToUploadEvent(_ media: ImportedMedia) -> AsyncThrowingStream<StorageClient.UploadEvent, Error> {
        AsyncThrowingStream<StorageClient.UploadEvent, Error> { cont in
            let task = Task {
                do {
                    for try await p in self {
                        cont.yield(.progress(p))
                    }
                    cont.yield(.finished(FileItem(uploaded: media)))
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    func mapToDownloadEvent(_ dest: URL) -> AsyncThrowingStream<StorageClient.DownloadEvent, Error> {
        AsyncThrowingStream<StorageClient.DownloadEvent, Error> { cont in
            let task = Task {
                do {
                    for try await p in self {
                        cont.yield(.progress(p))
                    }
                    cont.yield(.finished(dest))
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Download destination

extension FileManager {
    /// Download destination: object id under the caches dir (system-evictable).
    func cachesURL(for file: FileItem) -> URL {
        let caches = urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: file.id)
    }
}
