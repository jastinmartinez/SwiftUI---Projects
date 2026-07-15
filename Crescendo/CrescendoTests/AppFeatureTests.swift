import ComposableArchitecture
import Testing
@testable import Crescendo

@MainActor
struct AppFeatureTests {
  @Test
  func appLifecycleActionIsHandled() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.task)
  }
}
