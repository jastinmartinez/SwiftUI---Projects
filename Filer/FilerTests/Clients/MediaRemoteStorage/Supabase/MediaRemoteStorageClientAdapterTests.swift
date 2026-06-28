@testable import Filer
import Foundation
import Storage
import Testing

@Suite struct MediaRemoteStorageClientAdapterTests {
    // MARK: FileItem(_ FileObject)

    @Test func fileObjectWithImageMetadataMapsToRemoteFileItem() {
        let object = FileObject(name: "abc.jpg", metadata: [
            "name": .string("Holiday Photo"),
            "mimetype": .string("image/jpeg"),
            "size": .double(2048),
        ])
        let item = try! #require(FileItem(object))
        #expect(item.id == "abc.jpg")
        #expect(item.name == "Holiday Photo")
        #expect(item.kind == .image)
        #expect(item.size == 2048)
        #expect(item.status == .remote)
    }

    @Test func displayNameFallsBackToObjectKeyWhenAbsent() {
        let object = FileObject(name: "abc.jpg", metadata: ["mimetype": .string("image/jpeg"), "size": .double(2048)])
        let item = try! #require(FileItem(object))
        #expect(item.name == "abc.jpg")
    }

    @Test func nonMediaObjectIsDroppedAsNil() {
        let object = FileObject(name: "notes.pdf", metadata: ["mimetype": .string("application/pdf"), "size": .double(10)])
        #expect(FileItem(object) == nil)
    }

    @Test func missingMimeMetadataIsDroppedAsNil() {
        let object = FileObject(name: "mystery.bin", metadata: ["size": .double(10)])
        #expect(FileItem(object) == nil)
    }

    // MARK: mapToUploadEvent / mapToDownloadEvent

    @Test func mapToUploadEvent_emitsProgressThenFinished() async throws {
        let p0 = TransferProgress(bytesTransferred: 0, totalBytes: 12, completedChunks: 0, totalChunks: 1)
        let p1 = TransferProgress(bytesTransferred: 12, totalBytes: 12, completedChunks: 1, totalChunks: 1)

        var events: [MediaRemoteStorageClient.UploadEvent] = []
        for try await e in source([p0, p1]).mapToUploadEvent(media) {
            events.append(e)
        }

        #expect(events == [
            .progress(p0),
            .progress(p1),
            .finished(FileItem(uploaded: media)),
        ])
    }

    @Test func mapToUploadEvent_propagatesFailure() async {
        struct Boom: Error {}
        var caught: Error?
        do {
            for try await _ in failingSource(Boom()).mapToUploadEvent(media) {}
        } catch { caught = error }
        #expect(caught is Boom)
    }

    @Test func mapToDownloadEvent_emitsProgressThenFinishedDest() async throws {
        let dest = URL(fileURLWithPath: "/tmp/dest.jpg")
        let p0 = TransferProgress(bytesTransferred: 6, totalBytes: 12, completedChunks: 1, totalChunks: 2)

        var events: [MediaRemoteStorageClient.DownloadEvent] = []
        for try await e in source([p0]).mapToDownloadEvent(dest) {
            events.append(e)
        }

        #expect(events == [.progress(p0), .finished(dest)])
    }

    @Test func mapToDownloadEvent_propagatesFailure() async {
        struct Boom: Error {}
        let dest = URL(fileURLWithPath: "/tmp/dest.jpg")
        var caught: Error?
        do {
            for try await _ in failingSource(Boom()).mapToDownloadEvent(dest) {}
        } catch { caught = error }
        #expect(caught is Boom)
    }

    // MARK: - Helpers

    private func source(_ progresses: [TransferProgress]) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { cont in
            for p in progresses {
                cont.yield(p)
            }
            cont.finish()
        }
    }

    private func failingSource(_ error: Error) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { cont in cont.finish(throwing: error) }
    }

    private var media: ImportedMedia {
        ImportedMedia(
            metadata: MediaMetadata(
                id: "abc.jpg",
                name: "Photo",
                contentType: "image/jpeg",
                kind: .image,
                size: 12
            ),
            fileURL: URL(fileURLWithPath: "/tmp/abc.jpg")
        )
    }
}
