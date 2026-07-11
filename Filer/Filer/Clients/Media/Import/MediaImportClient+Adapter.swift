import Foundation
import UniformTypeIdentifiers

extension MediaImportClient {
    static func fileExtension(forContentType contentType: String) -> String? {
        UTType(mimeType: contentType)?.preferredFilenameExtension
    }

    static func objectID(_ uuid: UUID, contentType: String) -> String? {
        fileExtension(forContentType: contentType).map { "\(uuid.uuidString).\($0)" }
    }
}
