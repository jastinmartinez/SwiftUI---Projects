@testable import Filer
import Foundation
import Testing

struct FileRowAccessoryModelTests {
    @Test func remoteMapsToRemote() {
        guard case .remote = FileRowAccessoryView.Model(status: .remote) else {
            Issue.record("expected .remote"); return
        }
    }

    @Test func localMapsToLocal() {
        let url = URL(filePath: "/tmp/a.jpg")
        guard case .local = FileRowAccessoryView.Model(status: .local(url)) else {
            Issue.record("expected .local"); return
        }
    }

    @Test func failedMapsToFailed() {
        let status = FileItem.Status.failed(TransferError(operation: .upload, message: "boom"))
        guard case .failed = FileRowAccessoryView.Model(status: status) else {
            Issue.record("expected .failed"); return
        }
    }

    @Test func cancellingUploadMapsToActivity() {
        guard case .activity = FileRowAccessoryView.Model(status: .cancellingUpload) else {
            Issue.record("expected .activity"); return
        }
    }

    @Test func uploadingMapsToProgressWithFractionAndChunkLabel() {
        let p = TransferProgress(bytesTransferred: 3_000_000, totalBytes: 12_000_000, completedChunks: 1, totalChunks: 4)
        guard case let .progress(fraction, label) = FileRowAccessoryView.Model(status: .uploading(p)) else {
            Issue.record("expected .progress"); return
        }
        #expect(fraction == 0.25)
        #expect(label == "1/4")
    }

    @Test func downloadingMapsToProgress() {
        let p = TransferProgress(bytesTransferred: 6_000_000, totalBytes: 12_000_000, completedChunks: 2, totalChunks: 4)
        guard case let .progress(fraction, label) = FileRowAccessoryView.Model(status: .downloading(p)) else {
            Issue.record("expected .progress"); return
        }
        #expect(fraction == 0.5)
        #expect(label == "2/4")
    }

    @Test func zeroTotalBytesGivesZeroFraction() {
        let p = TransferProgress(bytesTransferred: 0, totalBytes: 0, completedChunks: 0, totalChunks: 0)
        guard case let .progress(fraction, _) = FileRowAccessoryView.Model(status: .uploading(p)) else {
            Issue.record("expected .progress"); return
        }
        #expect(fraction == 0)
    }
}
