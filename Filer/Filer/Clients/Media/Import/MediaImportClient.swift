import Dependencies
import Foundation
import PhotosUI
import SwiftUI

struct MediaImportClient: Sendable {
    typealias Load = @Sendable (_ items: [PhotosPickerItem]) async throws -> [LoadedMedia]

    var load: Load

    init(load: @escaping Load) {
        self.load = load
    }
}

extension MediaImportClient {
    struct LoadedMedia: Equatable, Sendable {
        let metadata: MediaMetadata
        let data: Data
    }

    struct Unimplemented: Error {}
}

extension DependencyValues {
    var mediaImport: MediaImportClient {
        get { self[MediaImportClient.self] }
        set { self[MediaImportClient.self] = newValue }
    }
}
