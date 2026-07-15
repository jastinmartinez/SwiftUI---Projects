import ComposableArchitecture
import SwiftUI

struct AppView: View {
  let store: StoreOf<AppFeature>

  var body: some View {
    Text(Locs.App.title)
      .task { await store.send(.task).finish() }
  }
}
