import ComposableArchitecture
import SwiftUI

/// Connects the playback store to stateless playback controls.
struct MusicPlaybackFeatureView: View {
    let store: StoreOf<MusicPlaybackFeature>

    var body: some View {
        let snapshot = store.phase.snapshot

        VStack(spacing: 20) {
            Text(store.selectedSong?.title ?? Locs.MusicPlayback.noSelection)
                .font(.title2)
            Text(store.selectedSong?.artistName ?? "")
                .foregroundStyle(.secondary)
            Text(MusicPlaybackControlsView.Model.localizedStatus(for: store.phase))
            Text(snapshot.currentTime.formatted(.number.precision(.fractionLength(0))))
            MusicPlaybackControlsView(model: .init(store))
            PlaybackEligibilityNoticeView(model: .init(store))
            if store.capabilities.supportsSeeking {
                Slider(
                    value: Binding(
                        get: { store.phase.snapshot.currentTime },
                        set: { store.send(.seekRequested($0)) }
                    ),
                    in: 0...max(1, snapshot.currentTime + 60)
                )
            }
        }
        .padding()
    }
}
