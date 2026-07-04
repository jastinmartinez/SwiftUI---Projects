import Foundation

// MARK: - FileItem

/// A file managed by the Files feature.
struct FileItem: Equatable {
    let metadata: MediaMetadata
    let status: Status
}

// MARK: - Metadata accessors

extension FileItem {
    var id: String { metadata.id }
    var name: String { metadata.name }
    var contentType: String { metadata.contentType }
    var kind: MediaKind { metadata.kind }
    var size: Int64? { metadata.size }
}

// MARK: - Status

extension FileItem {
    enum Status: Equatable {
        case remote
        case uploading(TransferProgress)
        case cancellingUpload
        case downloading(TransferProgress)
        case local(URL)
        case failed(TransferError)
    }
}

// MARK: - Transitions

extension FileItem {
    /// Returns a copy of this item with only the status replaced.
    func with(status: Status) -> FileItem {
        FileItem(metadata: metadata, status: status)
    }
}

// MARK: - ImportedMedia Inits

extension FileItem {
    init(importing media: ImportedMedia) {
        self.init(metadata: media.metadata, status: .uploading(.pending(total: media.metadata.size)))
    }

    init(uploaded media: ImportedMedia) {
        self.init(metadata: media.metadata, status: .local(media.fileURL))
    }

    init(remote metadata: MediaMetadata) {
        self.init(metadata: metadata, status: .remote)
    }
}
