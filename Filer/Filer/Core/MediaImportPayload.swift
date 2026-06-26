import Foundation

struct MediaImportPayload: Equatable, Sendable {
    let id: String
    let name: String
    let data: Data
    let contentType: String
    let kind: FileItem.Kind

    nonisolated init(
        id: String,
        name: String,
        data: Data,
        contentType: String,
        kind: FileItem.Kind
    ) {
        self.id = id
        self.name = name
        self.data = data
        self.contentType = contentType
        self.kind = kind
    }
}
