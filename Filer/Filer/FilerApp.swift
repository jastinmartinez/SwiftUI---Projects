import ComposableArchitecture
import Foundation
import SwiftUI

@main
struct FilerApp: App {
    var body: some Scene {
        WindowGroup {
            FilesFeatureView(store: filesStore)
        }
    }

    private var filesStore: StoreOf<FilesFeature> {
        Store(initialState: FilesFeature.State()) {
            FilesFeature()
        } withDependencies: {
            #if DEBUG
                if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                    $0.mediaRemoteStorage = MediaRemoteStorageClient()
                }
            #endif
        }
    }
}
