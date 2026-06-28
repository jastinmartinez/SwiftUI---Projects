import Dependencies
import Foundation
import PhotosUI
import SwiftUI

extension MediaImportClient: DependencyKey {
    static let liveValue: MediaImportClient = {
        @Dependency(\.uuid) var uuid
        return MediaImportClient(
            load: { items in
                var loaded: [MediaImportClient.LoadedMedia] = []
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    guard let contentType = item.supportedContentTypes.first?.preferredMIMEType,
                          let kind = MediaKind(mimeType: contentType),
                          let objectID = objectID(uuid(), contentType: contentType) else { continue }

                    let name = item.itemIdentifier ?? objectID
                    let metadata = MediaMetadata(
                        id: objectID,
                        name: name,
                        contentType: contentType,
                        kind: kind,
                        size: nil
                    )

                    loaded.append(
                        MediaImportClient.LoadedMedia(metadata: metadata, data: data)
                    )
                }
                return loaded
            }
        )
    }()
}
