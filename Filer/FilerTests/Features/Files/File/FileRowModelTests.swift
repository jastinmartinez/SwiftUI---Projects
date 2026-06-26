import ComposableArchitecture
@testable import Filer
import Testing

@MainActor
struct FileRowModelTests {
    private func makeSUT(_ item: FileItem) -> FileRowView.Model {
        let store = Store(initialState: FileFeature.State(item: item)) { FileFeature() }
        return FileRowView.Model(store)
    }

    private func model(_ item: FileItem) -> FileRowView.Model { makeSUT(item) }

    @Test func nameComesFromTheItem() {
        let m = model(FileItem(id: "a.jpg", name: "Sunset", kind: .image, size: 2_400_000, status: .remote))
        #expect(m.name == "Sunset")
    }

    @Test func remoteSubtitleJoinsSizeAndKind() {
        let m = model(FileItem(id: "a.jpg", name: "Sunset", kind: .image, size: 2_400_000, status: .remote))
        #expect(m.subtitle == "2.4 MB · Photo")
    }

    @Test func remoteSubtitleOmitsSizeWhenNil() {
        let m = model(FileItem(id: "a.jpg", name: "Sunset", kind: .video, size: nil, status: .remote))
        #expect(m.subtitle == "Video")
    }

    @Test func uploadingSubtitleShowsTransferredOverTotal() {
        let p = TransferProgress(bytesTransferred: 3_000_000, totalBytes: 12_000_000, completedChunks: 1, totalChunks: 4)
        let m = model(FileItem(id: "a.jpg", name: "Sunset", kind: .image, size: 12_000_000, status: .uploading(p)))
        #expect(m.subtitle == "Uploading 3 MB / 12 MB")
    }

    @Test func downloadingSubtitleShowsTransferredOverTotal() {
        let p = TransferProgress(bytesTransferred: 6_000_000, totalBytes: 12_000_000, completedChunks: 2, totalChunks: 4)
        let m = model(FileItem(id: "a.jpg", name: "Sunset", kind: .image, size: 12_000_000, status: .downloading(p)))
        #expect(m.subtitle == "Downloading 6 MB / 12 MB")
    }

    @Test func failedSubtitlePromptsRetry() {
        let status = FileItem.Status.failed(TransferError(operation: .download, message: "404"))
        let m = model(FileItem(id: "a.jpg", name: "Sunset", kind: .image, size: 12_000_000, status: status))
        #expect(m.subtitle == "Failed · Tap to retry")
    }

    @Test func accessoryIsBuiltFromStatus() {
        let m = model(FileItem(id: "a.jpg", name: "Sunset", kind: .image, size: 1, status: .remote))
        #expect(m.accessory == .remote)
    }

    @Test func sendTappedReachesTheReducer() {
        // Verify that model.send(.tapped) forwards to the reducer by observing the state change
        // (.remote → .downloading when tapped on a remote item).
        let item = FileItem(id: "a.jpg", name: "Sunset", kind: .image, size: 1, status: .remote)
        let store = Store(initialState: FileFeature.State(item: item)) {
            FileFeature()
        } withDependencies: {
            $0.storage.download = { _ in AsyncThrowingStream { $0.finish() } }
        }
        let m = FileRowView.Model(store)
        m.send(.tapped)
        if case .downloading = store.item.status {} else {
            Issue.record("expected .downloading after send(.tapped), got \(store.item.status)")
        }
    }
}
