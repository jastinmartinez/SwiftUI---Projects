import Dependencies
import DependenciesMacros
import Foundation
import PhotosUI
import SwiftUI

@DependencyClient
struct MediaImportClient {
    var load: (_ items: [PhotosPickerItem]) async throws -> [MediaImportPayload] = { _ in [] }
}
