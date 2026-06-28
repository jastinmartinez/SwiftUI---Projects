import Foundation

// MARK: - FileItem

/// A file managed by the Files feature.
struct FileItem: Equatable {
    let id: String // storage object path — stable identity (minted at import for new files)
    let name: String // display filename (from import or list metadata)
    let kind: Kind // .image / .video
    let size: Int64? // bytes (always known from import; from list metadata otherwise)
    let status: Status // immutable — transitions replace the whole value
}

// MARK: - Kind

extension FileItem {
    /// The photo-library media type represented by a Files row.
    enum Kind: Equatable, Sendable {
        case image
        case video
    }
}

// MARK: - Kind classification

extension FileItem.Kind {
    /// Framework → domain: MIME type prefix → Kind; non-media → nil (filtered out by list).
    init?(mimeType: String?) {
        guard let mimeType, !mimeType.isEmpty else { return nil }
        if mimeType.hasPrefix("image/") { self = .image }
        else if mimeType.hasPrefix("video/") { self = .video }
        else { return nil }
    }
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
        FileItem(id: id, name: name, kind: kind, size: size, status: status)
    }
}

// MARK: - ImportedMedia Inits

extension FileItem {
    init(importing media: ImportedMedia) {
        self.init(id: media.id, name: media.name, kind: .init(media.kind), size: media.size,
                  status: .uploading(.start(total: media.size)))
    }

    init(uploaded media: ImportedMedia) {
        self.init(id: media.id, name: media.name, kind: .init(media.kind), size: media.size,
                  status: .local(media.fileURL))
    }
}

private extension FileItem.Kind {
    init(_ mediaKind: MediaKind) {
        switch mediaKind {
        case .image:
            self = .image
        case .video:
            self = .video
        }
    }
}
