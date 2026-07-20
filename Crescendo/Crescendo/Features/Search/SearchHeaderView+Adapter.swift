import ComposableArchitecture

extension SearchHeaderView.Model {
    @MainActor
    init(
        _ store: StoreOf<SearchFeature>,
        providerSelection: ProviderSelectionView.Model
    ) {
        self.init(
            query: store.query,
            providerSelection: providerSelection,
            isSearchEnabled: store.providerAccess?.authorization == .authorized
                && !store.query
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty,
            onQueryChanged: { store.send(.queryChanged($0)) },
            onSubmit: { store.send(.submitButtonTapped) }
        )
    }
}
