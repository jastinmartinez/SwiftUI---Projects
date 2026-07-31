import Foundation
import Testing

@testable import Crescendo

/// Proves stable whole-file SHA-256 identities and read-failure mapping.
///
/// The suite isolates fingerprint mechanics from staging, managed storage, and
/// the Library aggregate's duplicate-content policy.
struct LibraryFileFingerprinterTests {
    @Test(
        arguments: [
            (
                Data(),
                "e3b0c44298fc1c149afbf4c8996fb924"
                    + "27ae41e4649b934ca495991b7852b855"
            ),
            (
                Data("abc".utf8),
                "ba7816bf8f01cfea414140de5dae2223"
                    + "b00361a396177a9cb410ff61f20015ad"
            ),
        ]
    )
    func standardSHA256VectorsProduceOpaqueContentIdentities(
        contents: Data,
        expectedIdentity: String
    ) async throws {
        let fileURL = try temporaryFileURL(contents: contents)
        defer { try? FileManager().removeItem(at: fileURL) }

        let result = await LibraryFileFingerprinter().fingerprint(fileURL)

        #expect(
            result
                == .success(
                    Library.ContentIdentity(rawValue: expectedIdentity)
                )
        )
    }

    @Test
    func everyChunkContributesToTheContentIdentity() async throws {
        let contents = Data(repeating: 0x61, count: 1_000_000)
        let fileURL = try temporaryFileURL(contents: contents)
        defer { try? FileManager().removeItem(at: fileURL) }

        let result = await LibraryFileFingerprinter().fingerprint(fileURL)

        #expect(
            result
                == .success(
                    Library.ContentIdentity(
                        rawValue: "cdc76e5c9914fb9281a1c7e284d73e67"
                            + "f1809a48a497200e046d39ccc7112cd0"
                    )
                )
        )
    }

    @Test
    func unreadableFileMapsToFileReadFailure() async {
        let missingURL = URL.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).m4a")

        let result = await LibraryFileFingerprinter().fingerprint(missingURL)

        #expect(result == .failure(.fileReadFailed))
    }

    private func temporaryFileURL(contents: Data) throws -> URL {
        let fileURL = URL.temporaryDirectory
            .appending(path: "LibraryFileFingerprinterTests-\(UUID().uuidString)")
        try contents.write(to: fileURL)
        return fileURL
    }
}
