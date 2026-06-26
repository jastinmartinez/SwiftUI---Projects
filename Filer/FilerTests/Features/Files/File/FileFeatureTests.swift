import ComposableArchitecture
@testable import Filer
import Foundation
import Testing

@MainActor
struct FileFeatureTests {
    private var sampleMedia: ImportedMedia {
        ImportedMedia(
            id: "abc.jpg",
            name: "photo.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/abc.jpg"),
            contentType: "image/jpeg",
            kind: .image,
            size: 12_000_000
        )
    }

    private func remoteItem(id: String = "remote.jpg", size: Int64? = 6_000_000) -> FileItem {
        FileItem(id: id, name: "remote.jpg", kind: .image, size: size, status: .remote)
    }

    @Test func startUploadWalksProgressToFinished() async {
        let media = sampleMedia
        let p1 = TransferProgress(bytesTransferred: 6_000_000, totalBytes: 12_000_000, completedChunks: 1, totalChunks: 2)
        let p2 = TransferProgress(bytesTransferred: 12_000_000, totalBytes: 12_000_000, completedChunks: 2, totalChunks: 2)
        let finished = FileItem(uploaded: media)

        let store = TestStore(
            initialState: FileFeature.State(item: FileItem(importing: media), source: nil)
        ) {
            FileFeature()
        } withDependencies: {
            $0.storage.upload = { _ in
                AsyncThrowingStream { cont in
                    cont.yield(.progress(p1))
                    cont.yield(.progress(p2))
                    cont.yield(.finished(finished))
                    cont.finish()
                }
            }
        }

        await store.send(.startUpload(media)) {
            $0.source = media
            $0.item = $0.item.with(status: .uploading(.start(total: media.size)))
        }
        await store.receive(\.upload)
        await store.receive(\.progress) {
            $0.item = $0.item.with(status: .uploading(p1))
        }
        await store.receive(\.progress) {
            $0.item = $0.item.with(status: .uploading(p2))
        }
        await store.receive(\.uploadFinished) {
            $0.item = finished
            $0.source = nil
        }
    }

    @Test func tappedRemoteStartsDownload() async {
        let item = remoteItem()
        let dest = URL(fileURLWithPath: "/tmp/remote.jpg")

        let store = TestStore(
            initialState: FileFeature.State(item: item, source: nil)
        ) {
            FileFeature()
        } withDependencies: {
            $0.storage.download = { _ in
                AsyncThrowingStream { cont in
                    cont.yield(.finished(dest))
                    cont.finish()
                }
            }
        }

        await store.send(.tapped) {
            $0.item = $0.item.with(status: .downloading(.start(total: item.size)))
        }
        await store.receive(\.download)
        await store.receive(\.downloadFinished) {
            $0.item = $0.item.with(status: .local(dest))
        }
    }

    @Test func tappedLocalSendsPreviewDelegate() async {
        let url = URL(fileURLWithPath: "/tmp/local.jpg")
        let item = FileItem(id: "local.jpg", name: "local.jpg", kind: .image, size: 100, status: .local(url))

        let store = TestStore(
            initialState: FileFeature.State(item: item, source: nil)
        ) {
            FileFeature()
        }

        await store.send(.tapped)
        await store.receive(\.delegate.preview)
    }

    @Test func cancelTappedWhileUploadingCancelsAndDelegatesCancelled() async {
        let media = sampleMedia
        let store = TestStore(
            initialState: FileFeature.State(
                item: FileItem(importing: media),
                source: media
            )
        ) {
            FileFeature()
        } withDependencies: {
            $0.storage.upload = { _ in
                AsyncThrowingStream { _ in } // never finishes; cancel terminates it
            }
        }
        store.exhaustivity = .off

        await store.send(.startUpload(media)) {
            $0.source = media
            $0.item = $0.item.with(status: .uploading(.start(total: media.size)))
        }
        await store.receive(\.upload)
        await store.send(.cancelTapped)
        await store.receive(\.delegate.cancelled)
    }

    @Test func cancelTappedWhileDownloadingReturnsToRemote() async {
        let item = remoteItem()
        let store = TestStore(
            initialState: FileFeature.State(item: item, source: nil)
        ) {
            FileFeature()
        } withDependencies: {
            $0.storage.download = { _ in AsyncThrowingStream { _ in } }
        }
        store.exhaustivity = .off

        await store.send(.tapped) {
            $0.item = $0.item.with(status: .downloading(.start(total: item.size)))
        }
        await store.receive(\.download)
        await store.send(.cancelTapped) {
            $0.item = $0.item.with(status: .remote)
        }
    }

    @Test func retryTappedAfterUploadFailureRestartsUpload() async {
        let media = sampleMedia
        let finished = FileItem(uploaded: media)
        let failed = FileItem(importing: media)
            .with(status: .failed(TransferError(operation: .upload, message: "boom")))

        let store = TestStore(
            initialState: FileFeature.State(item: failed, source: media)
        ) {
            FileFeature()
        } withDependencies: {
            $0.storage.upload = { _ in
                AsyncThrowingStream { cont in
                    cont.yield(.finished(finished))
                    cont.finish()
                }
            }
        }

        await store.send(.retryTapped) {
            $0.item = $0.item.with(status: .uploading(.start(total: media.size)))
        }
        await store.receive(\.upload)
        await store.receive(\.uploadFinished) {
            $0.item = finished
            $0.source = nil
        }
    }

    @Test func retryTappedAfterDownloadFailureRestartsDownload() async {
        let dest = URL(fileURLWithPath: "/tmp/remote.jpg")
        let item = FileItem(
            id: "remote.jpg", name: "remote.jpg", kind: .image, size: 6_000_000,
            status: .failed(TransferError(operation: .download, message: "boom"))
        )
        let store = TestStore(
            initialState: FileFeature.State(item: item, source: nil)
        ) {
            FileFeature()
        } withDependencies: {
            $0.storage.download = { _ in
                AsyncThrowingStream { cont in
                    cont.yield(.finished(dest))
                    cont.finish()
                }
            }
        }

        await store.send(.retryTapped) {
            $0.item = $0.item.with(status: .downloading(.start(total: item.size)))
        }
        await store.receive(\.download)
        await store.receive(\.downloadFinished) {
            $0.item = $0.item.with(status: .local(dest))
        }
    }

    @Test func failedTransitionsToFailed() async {
        let item = remoteItem()
        let store = TestStore(
            initialState: FileFeature.State(
                item: item.with(status: .downloading(.start(total: item.size))),
                source: nil
            )
        ) {
            FileFeature()
        }
        let error = TransferError(operation: .download, message: "404")
        await store.send(.failed(error)) {
            $0.item = $0.item.with(status: .failed(error))
        }
    }
}
