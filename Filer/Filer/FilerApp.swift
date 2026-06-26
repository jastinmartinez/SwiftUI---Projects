import ComposableArchitecture
import SwiftUI

@main
struct FilerApp: App {
    var body: some Scene {
        WindowGroup {
            FilesFeatureView(
                store: Store(initialState: FilesFeature.State()) {
                    FilesFeature()
                }
            )
        }
    }
}
