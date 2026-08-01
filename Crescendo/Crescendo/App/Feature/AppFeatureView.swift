import ComposableArchitecture
import SwiftUI

/// The application feature boundary that owns Crescendo's root store.
struct AppFeatureView: View {
    let store: StoreOf<AppReducer>

    var body: some View {
        TabView(selection: selectedTab) {
            SearchFeatureView(
                store: store.scope(state: \.search, action: \.search)
            )
            .tabItem {
                Label(Locs.Search.action, systemImage: "magnifyingglass")
            }
            .tag(AppTab.search)

            LibraryFeatureView(
                store: store.scope(state: \.library, action: \.library)
            )
            .tabItem {
                Label(Locs.Library.title, systemImage: "music.note.list")
            }
            .tag(AppTab.library)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let model = PlaybackNowPlayingView.Model(
                store.scope(state: \.playback, action: \.playback)
            ) {
                PlaybackNowPlayingView(
                    model: model
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .task {
            await store.send(.task).finish()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.playback.isPlayerPresented },
                set: { store.send(.playback(.setPlayerPresented($0))) }
            )
        ) {
            PlaybackFeatureView(
                store: store.scope(state: \.playback, action: \.playback)
            )
        }
    }

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { store.selectedTab },
            set: { store.send(.selectedTabChanged($0)) }
        )
    }
}
