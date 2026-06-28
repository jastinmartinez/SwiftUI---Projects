import Foundation

// MARK: - FileItem

/// A file managed by the Files feature.
struct FileItem: Equatable {
    let metadata: MediaMetadata
    let status: Status // immutable — transitions replace the whole value
}

// MARK: - Metadata accessors

extension FileItem {
    var id: String { metadata.id } // storage object path — stable identity (minted at import for new files)
    var name: String { metadata.name } // display filename (from import or list metadata)
    var contentType: String { metadata.contentType }
    var kind: MediaKind { metadata.kind }
    var size: Int64? { metadata.size } // bytes (always known from import; from list metadata otherwise)
}

// MARK: - Status

extension FileItem {
    enum Status: Equatable {
        case remote // in bucket, not downloaded
        case uploading(TransferProgress)
        case downloading(TransferProgress)
        case local(URL) // cached locally → previewable
        case failed(TransferError) // retriable
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
        self.init(metadata: media.metadata, status: .uploading(.start(total: media.metadata.size)))
    }

    init(uploaded media: ImportedMedia) {
        self.init(metadata: media.metadata, status: .local(media.fileURL))
    }

    init(remote metadata: MediaMetadata) {
        self.init(metadata: metadata, status: .remote)
    }
}
