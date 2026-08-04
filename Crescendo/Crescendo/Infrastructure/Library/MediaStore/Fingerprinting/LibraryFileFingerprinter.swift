import CryptoKit
import Foundation

/// Produces stable content identities from Library file bytes.
///
/// This concrete mechanism reads files in bounded chunks and encodes their
/// incremental SHA-256 digest as an opaque Library content identity. It does
/// not decide duplicates, stage or move files, or manage security-scoped
/// resource access.
struct LibraryFileFingerprinter: Sendable {
    private static let chunkByteCount = 64 * 1024

    /// Identifies the complete contents of one readable file.
    ///
    /// - Parameter fileURL: The file whose bytes define the identity.
    /// - Returns: The stable identity, or `.fileReadFailed` when the file cannot
    ///   be opened or completely read.
    func fingerprint(_ fileURL: URL) async -> Result<Library.ContentIdentity, LibraryFailure> {
        do {
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }

            var hasher = SHA256()
            while let chunk = try fileHandle.read(upToCount: Self.chunkByteCount), !chunk.isEmpty {
                hasher.update(data: chunk)
            }

            let encodedDigest = hasher.finalize()
                .map { String(format: "%02x", $0) }
                .joined()
            return .success(
                Library.ContentIdentity(rawValue: encodedDigest)
            )
        } catch {
            return .failure(.fileReadFailed)
        }
    }
}
