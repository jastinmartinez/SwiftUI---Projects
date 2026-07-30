import ComposableArchitecture

extension SearchHeaderView.Model {
    @MainActor
    init(_ store: StoreOf<SearchReducer>) {
        self.init(
            query: store.query,
            isSearchEnabled: !store.query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
            strings: Strings(
                title: Locs.App.title,
                prompt: Locs.Search.prompt,
                clear: Locs.Search.clear,
                action: Locs.Search.action
            ),
            onQueryChanged: { store.send(.queryChanged($0)) },
            onSubmit: { store.send(.submitButtonTapped) }
        )
    }
}
