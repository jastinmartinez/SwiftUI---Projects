@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation
import SwiftUI

/// The Crescendo application entry point and composition root.
@main
struct CrescendoApp: App {
    let store: StoreOf<AppReducer>

    init() {
        let player = AVPlayer()
        let preparer = AVPlayerItemPreparer.live()
        let jamendoClientID =
            Bundle.main.object(forInfoDictionaryKey: "JamendoClientID")
            as? String
        let composition = AppComposition.live(
            jamendoClientID: jamendoClientID,
            player: player,
            preparer: preparer,
            data: { try await URLSession.shared.data(for: $0) }
        )
        self.store = composition.store()
    }

    var body: some Scene {
        WindowGroup {
            AppFeatureView(store: store)
        }
    }
}
