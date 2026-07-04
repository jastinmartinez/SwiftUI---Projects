import ComposableArchitecture
@testable import Filer
import Foundation
import Testing

@MainActor
struct FileRowModelTests {
    @Test func nameComesFromTheItem() {
        let m = model(file(name: "Sunset", size: 2_400_000))
        #expect(m.name == "Sunset")
    }

    @Test func remoteSubtitleJoinsSizeAndKind() {
        let m = model(file(name: "Sunset", size: 2_400_000))
        #expect(m.subtitle == "2.4 MB · Photo")
    }

    @Test func remoteSubtitleOmitsSizeWhenNil() {
        let m = model(file(name: "Sunset", contentType: "video/quicktime", kind: .video, size: nil))
        #expect(m.subtitle == "Video")
    }

    @Test func uploadingSubtitleShowsTransferredOverTotal() {
        let p = TransferProgress(bytesTransferred: 3_000_000, totalBytes: 12_000_000, completedChunks: 1, totalChunks: 4)
        let m = model(file(name: "Sunset", size: 12_000_000, status: .uploading(p)))
        #expect(m.subtitle == "Uploading 3 MB / 12 MB")
    }

    @Test func downloadingSubtitleShowsTransferredOverTotal() {
        let p = TransferProgress(bytesTransferred: 6_000_000, totalBytes: 12_000_000, completedChunks: 2, totalChunks: 4)
        let m = model(file(name: "Sunset", size: 12_000_000, status: .downloading(p)))
        #expect(m.subtitle == "Downloading 6 MB / 12 MB")
    }

    @Test func failedSubtitlePromptsRetry() {
        let status = FileItem.Status.failed(TransferError(operation: .download, message: "404"))
        let m = model(file(name: "Sunset", size: 12_000_000, status: status))
        #expect(m.subtitle == "Failed · Tap to retry")
    }

    @Test func cancellingUploadSubtitleShowsCancellationInProgress() {
        let m = model(file(name: "Sunset", size: 12_000_000, status: .cancellingUpload))
        #expect(m.subtitle == "Cancelling upload...")
    }

    @Test func accessoryIsBuiltFromStatus() {
        let m = model(file(name: "Sunset", size: 1))
        #expect(m.accessory == .remote)
    }

    @Test func uploadingExposesCancelTrailingAction() {
        let p = TransferProgress(bytesTransferred: 3_000_000, totalBytes: 12_000_000, completedChunks: 1, totalChunks: 4)
        let m = model(file(name: "Sunset", size: 12_000_000, status: .uploading(p)))
        #expect(m.trailingOperation?.kind == .cancel)
    }

    @Test func downloadingExposesCancelTrailingAction() {
        let p = TransferProgress(bytesTransferred: 3_000_000, totalBytes: 12_000_000, completedChunks: 1, totalChunks: 4)
        let m = model(file(name: "Sunset", size: 12_000_000, status: .downloading(p)))
        #expect(m.trailingOperation?.kind == .cancel)
    }

    @Test func failedExposesOnlyRetryTrailingAction() {
        let status = FileItem.Status.failed(TransferError(operation: .upload, message: "boom"))
        let m = model(file(name: "Sunset", size: 12_000_000, status: status))
        #expect(m.trailingOperation?.kind == .retry)
    }

    @Test func readyRowsExposeNoTrailingActions() {
        let remote = model(file(name: "Sunset", size: 12_000_000, status: .remote))
        let local = model(file(name: "Sunset", size: 12_000_000, status: .local(URL(filePath: "/tmp/a.jpg"))))
        #expect(remote.trailingOperation == nil)
        #expect(local.trailingOperation == nil)
    }

    @Test func cancellingUploadExposesNoTrailingAction() {
        let m = model(file(name: "Sunset", size: 12_000_000, status: .cancellingUpload))
        #expect(m.trailingOperation == nil)
    }

    @Test func onTapReachesTheReducer() {
        // Verify that onTap forwards to the reducer by observing the state change
        // (.remote -> .downloading when tapped on a remote item).
        let item = file(name: "Sunset", size: 1)
        let store = Store(initialState: FileFeature.State(item: item)) {
            FileFeature()
        } withDependencies: {
            $0.mediaRemoteStorage = Self.remoteStorage(download: { _ in AsyncThrowingStream { $0.finish() } })
        }
        let m = FileRowView.Model(store)
        m.onTap()
        if case .downloading = store.item.status {} else {
            Issue.record("expected .downloading after onTap, got \(store.item.status)")
        }
    }

    @Test func trailingOperationReachesTheReducer() {
        let p = TransferProgress(bytesTransferred: 3_000_000, totalBytes: 12_000_000, completedChunks: 1, totalChunks: 4)
        let item = file(name: "Sunset", size: 12_000_000, status: .downloading(p))
        let store = Store(initialState: FileFeature.State(item: item)) {
            FileFeature()
        } withDependencies: {
            $0.mediaRemoteStorage = Self.failingRemoteStorage()
        }
        let m = FileRowView.Model(store)
        m.trailingOperation?.perform()
        #expect(store.item.status == .remote)
    }

    // MARK: - Helpers

    private func makeSUT(_ item: FileItem) -> FileRowView.Model {
        let store = withDependencies {
            $0.mediaRemoteStorage = Self.failingRemoteStorage()
        } operation: {
            Store(initialState: FileFeature.State(item: item)) {
                FileFeature()
            }
        }
        return FileRowView.Model(store)
    }

    private func model(_ item: FileItem) -> FileRowView.Model { makeSUT(item) }

    private func file(
        id: String = "a.jpg",
        name: String,
        contentType: String = "image/jpeg",
        kind: MediaKind = .image,
        size: Int64?,
        status: FileItem.Status = .remote
    ) -> FileItem {
        FileItem(
            metadata: MediaMetadata(
                id: id,
                name: name,
                contentType: contentType,
                kind: kind,
                size: size
            ),
            status: status
        )
    }

    private static func remoteStorage(
        download: @escaping MediaRemoteStorageClient.Download
    ) -> MediaRemoteStorageClient {
        MediaRemoteStorageClient(
            list: { throw MediaRemoteStorageClient.Unimplemented("mediaRemoteStorage.list") },
            upload: { _ in AsyncThrowingStream { $0.finish(throwing: MediaRemoteStorageClient.Unimplemented("mediaRemoteStorage.upload")) } },
            download: download
        )
    }

    private static func failingRemoteStorage() -> MediaRemoteStorageClient {
        MediaRemoteStorageClient(
            list: { throw MediaRemoteStorageClient.Unimplemented("mediaRemoteStorage.list") },
            upload: { _ in AsyncThrowingStream { $0.finish(throwing: MediaRemoteStorageClient.Unimplemented("mediaRemoteStorage.upload")) } },
            download: { _ in AsyncThrowingStream { $0.finish(throwing: MediaRemoteStorageClient.Unimplemented("mediaRemoteStorage.download")) } }
        )
    }
}
