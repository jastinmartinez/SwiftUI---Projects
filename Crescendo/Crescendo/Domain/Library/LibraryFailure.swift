/// The stable failures that Library clients and workflows can exchange.
///
/// SDK errors, diagnostic logging, and localized presentation remain outside
/// this domain vocabulary.
enum LibraryFailure: Error, Equatable, Sendable {
    case accessDenied
    case unsupportedFile
    case fileReadFailed
    case fileWriteFailed
    case metadataReadFailed
    case catalogReadFailed
    case catalogWriteFailed
    case invalidManagedFile
}
