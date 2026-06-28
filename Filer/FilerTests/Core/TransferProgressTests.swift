@testable import Filer
import Testing

struct TransferProgressTests {
    @Test func startZeroesProgressAndComputesChunkCount() {
        // 14 MB with 6 MB chunks → ceil(14/6) = 3 chunks
        let p = TransferProgress.start(total: 14 * 1024 * 1024)
        #expect(p.bytesTransferred == 0)
        #expect(p.totalBytes == 14 * 1024 * 1024)
        #expect(p.completedChunks == 0)
        #expect(p.totalChunks == 3)
    }

    @Test func startExactMultipleHasNoPartialChunk() {
        let p = TransferProgress.start(total: 12 * 1024 * 1024) // exactly 2 chunks
        #expect(p.totalChunks == 2)
    }

    @Test func startWithNilTotalIsZeroChunks() {
        let p = TransferProgress.start(total: nil)
        #expect(p.totalBytes == 0)
        #expect(p.totalChunks == 0)
    }

    @Test func startRespectsCustomChunkSize() {
        let p = TransferProgress.start(total: 10, chunkSize: 4) // ceil(10/4) = 3
        #expect(p.totalChunks == 3)
    }

    @Test func transferErrorCarriesOperationAndMessage() {
        let e = TransferError(operation: .download, message: "404")
        #expect(e.operation == .download)
        #expect(e.message == "404")
    }

    @Test func transferErrorFactoriesKeepRetryOperation() {
        struct Boom: Error {}

        #expect(TransferError.upload(Boom()).operation == .upload)
        #expect(TransferError.download(Boom()).operation == .download)
    }
}
