import ComposableArchitecture

extension ProviderSelectionView.Model {
    @MainActor
    init(_ store: StoreOf<AppFeature>) {
        self.init(
            providers: store.registeredProviders,
            activeProviderID: store.activeProviderID,
            isSelectionEnabled: store.providerSwitchRequestID == nil
                && store.playbackTransition == nil,
            onSelect: { store.send(.providerSelected($0)) }
        )
    }
}
