import ComposableArchitecture

extension ProviderSelectionView.Model {
    @MainActor
    init(_ store: StoreOf<AppFeature>) {
        self.init(
            providers: store.providerConnection.providers,
            activeProviderID: store.providerConnection.connection.providerID,
            isSelectionEnabled: store.providerSwitch == nil
                && store.playbackStart == nil,
            onSelect: { store.send(.providerSelected($0)) }
        )
    }
}
