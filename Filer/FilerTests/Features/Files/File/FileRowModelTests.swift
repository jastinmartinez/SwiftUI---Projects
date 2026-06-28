import ComposableArchitecture
@testable import Filer
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

    @Test func accessoryIsBuiltFromStatus() {
        let m = model(file(name: "Sunset", size: 1))
        #expect(m.accessory == .remote)
    }

    @Test func sendTappedReachesTheReducer() {
        // Verify that model.send(.tapped) forwards to the reducer by observing the state change
        // (.remote → .downloading when tapped on a remote item).
        let item = file(name: "Sunset", size: 1)
        let store = Store(initialState: FileFeature.State(item: item)) {
            FileFeature()
        } withDependencies: {
            $0.mediaRemoteStorage = MediaRemoteStorageClient(download: { _ in AsyncThrowingStream { $0.finish() } })
        }
        let m = FileRowView.Model(store)
        m.send(.tapped)
        if case .downloading = store.item.status {} else {
            Issue.record("expected .downloading after send(.tapped), got \(store.item.status)")
        }
    }

    // MARK: - Helpers

    private func makeSUT(_ item: FileItem) -> FileRowView.Model {
        let store = withDependencies {
            $0.mediaRemoteStorage = MediaRemoteStorageClient()
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
}
