import ComposableArchitecture
@testable import Filer
import Foundation
import Testing

@MainActor
struct FilesFeatureTests {
    private func remoteFile(_ id: String) -> FileItem {
        FileItem(id: id, name: id, kind: .image, size: 100, status: .remote)
    }

    private func media(_ id: String) -> ImportedMedia {
        ImportedMedia(
            id: id,
            name: id,
            fileURL: URL(fileURLWithPath: "/tmp/\(id)"),
            contentType: "image/jpeg",
            kind: .image,
            size: 1000
        )
    }

    @Test func onAppearLoadsFilesToReady() async {
        let files = [remoteFile("a.jpg"), remoteFile("b.jpg")]
        let store = TestStore(initialState: FilesFeature.State()) {
            FilesFeature()
        } withDependencies: {
            $0.mediaRemoteStorage.list = { files }
        }

        await store.send(.onAppear)
        await store.receive(\.filesLoaded) {
            $0.files = IdentifiedArray(
                uniqueElements: files.map { FileFeature.State(item: $0) },
                id: \.item.id
            )
            $0.loadPhase = .ready
        }
    }

    @Test func onAppearFailureSetsFailedPhase() async {
        struct ListError: Error {}
        let store = TestStore(initialState: FilesFeature.State()) {
            FilesFeature()
        } withDependencies: {
            $0.mediaRemoteStorage.list = { throw ListError() }
        }

        await store.send(.onAppear)
        await store.receive(\.loadFailed) {
            $0.loadPhase = .failed(ListError().localizedDescription)
        }
    }

    @Test func importerImportedInsertsRowsAndStartsUpload() async {
        let m = media("new.jpg")
        let store = TestStore(initialState: FilesFeature.State()) {
            FilesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.mediaRemoteStorage.upload = { _ in AsyncThrowingStream { $0.finish() } }
        }
        store.exhaustivity = .off

        await store.send(.importer(.delegate(.imported([m])))) {
            $0.files.insert(FileFeature.State(item: FileItem(importing: m)), at: 0)
        }
        await store.receive(\.rows[id: m.id].startUpload)
    }

    @Test func rowCancelledRemovesFile() async {
        let m = media("x.jpg")
        var state = FilesFeature.State()
        state.files.insert(FileFeature.State(item: FileItem(importing: m)), at: 0)

        let store = TestStore(initialState: state) {
            FilesFeature()
        }
        store.exhaustivity = .off

        await store.send(.rows(.element(id: m.id, action: .delegate(.cancelled)))) {
            $0.files.remove(id: m.id)
        }
    }

    @Test func rowPreviewSetsPreviewItem() async {
        let m = media("y.jpg")
        let url = URL(fileURLWithPath: "/tmp/y.jpg")
        var state = FilesFeature.State()
        state.files.insert(
            FileFeature.State(item: FileItem(id: m.id, name: m.name, kind: .image, size: 100, status: .local(url))),
            at: 0
        )

        let store = TestStore(initialState: state) {
            FilesFeature()
        }
        store.exhaustivity = .off

        await store.send(.rows(.element(id: m.id, action: .delegate(.preview(url, .image))))) {
            $0.preview = FilesFeature.PreviewItem(url: url, kind: .image)
        }
    }

    @Test func previewDismissedClearsPreview() async {
        var state = FilesFeature.State()
        state.preview = FilesFeature.PreviewItem(url: URL(fileURLWithPath: "/tmp/z.jpg"), kind: .image)

        let store = TestStore(initialState: state) {
            FilesFeature()
        }

        await store.send(.previewDismissed) {
            $0.preview = nil
        }
    }
}
