import ComposableArchitecture
import SwiftUI

struct FilesFeatureView: View {
    let store: StoreOf<FilesFeature>

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Files")
                .toolbar {
                    PhotoLibraryPickerView(
                        model: .init(store.scope(state: \.importer, action: \.importer))
                    )
                }
                .sheet(item: Binding(
                    get: { store.preview },
                    set: { if $0 == nil { store.send(.previewDismissed) } }
                )) { item in
                    FilePreviewView(model: .init(item))
                }
                .onAppear { store.send(.onAppear) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadPhase {
        case .loading:
            FilesLoadingView()
        case let .failed(message):
            FilesErrorView(model: .init(message: message, send: { _ in store.send(.onAppear) }))
        case .ready:
            if store.files.isEmpty {
                FilesEmptyView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.filerGroupedBackground)
            } else {
                List {
                    ForEach(store.scope(state: \.files, action: \.rows)) { rowStore in
                        FileRowView(model: .init(rowStore))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}
