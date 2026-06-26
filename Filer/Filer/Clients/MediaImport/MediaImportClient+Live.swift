import Dependencies
import Foundation
import PhotosUI
import SwiftUI

extension MediaImportClient: DependencyKey {
    static let liveValue: MediaImportClient = {
        @Dependency(\.uuid) var uuid
        return MediaImportClient(
            load: { items in
                var loaded: [MediaImportPayload] = []
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    guard let contentType = item.supportedContentTypes.first?.preferredMIMEType,
                          let kind = FileItem.Kind(mimeType: contentType),
                          let objectID = objectID(uuid(), contentType: contentType) else { continue }

                    let name = item.itemIdentifier ?? objectID

                    loaded.append(
                        MediaImportPayload(
                            id: objectID,
                            name: name,
                            data: data,
                            contentType: contentType,
                            kind: kind
                        )
                    )
                }
                return loaded
            }
        )
    }()
}
