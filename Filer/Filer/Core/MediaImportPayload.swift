import Foundation

struct MediaImportPayload: Equatable, Sendable {
    let id: String
    let name: String
    let data: Data
    let contentType: String
    let kind: FileItem.Kind
}
