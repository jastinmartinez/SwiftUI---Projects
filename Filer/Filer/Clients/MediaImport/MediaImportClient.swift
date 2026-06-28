import Dependencies
import Foundation
import PhotosUI
import SwiftUI

struct MediaImportClient: Sendable {
    typealias Load = @Sendable (_ items: [PhotosPickerItem]) async throws -> [Payload]

    var load: Load = { _ in [] }
}

extension MediaImportClient {
    struct Payload: Equatable, Sendable {
        let metadata: MediaMetadata
        let data: Data
    }
}

extension DependencyValues {
    var mediaImport: MediaImportClient {
        get { self[MediaImportClient.self] }
        set { self[MediaImportClient.self] = newValue }
    }
}
