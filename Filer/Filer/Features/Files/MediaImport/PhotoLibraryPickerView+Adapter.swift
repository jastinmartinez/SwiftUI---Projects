import ComposableArchitecture

extension PhotoLibraryPickerView.Model {
    init(_ store: StoreOf<MediaImportFeature>) {
        self.init(
            isLoading: store.phase == .loading,
            send: { action in
                switch action {
                case let .picked(items): store.send(.picked(items))
                }
            }
        )
    }
}
