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

#Preview("Ready") {
    FilesFeatureView(store: Store(
        initialState: FilesFeature.State(
            files: IdentifiedArray(uniqueElements: [
                FileFeature.State(item: FileItem(id: "1.jpg", name: "Sunset", kind: .image, size: 2_400_000, status: .remote)),
                FileFeature.State(item: FileItem(id: "2.mov", name: "Clip", kind: .video, size: 12_000_000, status: .local(URL(filePath: "/tmp/2.mov")))),
            ], id: \.item.id),
            loadPhase: .ready
        )
    ) { FilesFeature() })
}

#Preview("Empty") {
    FilesFeatureView(store: Store(
        initialState: FilesFeature.State(loadPhase: .ready)
    ) { FilesFeature() })
}

#Preview("Loading") {
    FilesFeatureView(store: Store(
        initialState: FilesFeature.State(loadPhase: .loading)
    ) { FilesFeature() })
}

#Preview("Failed") {
    FilesFeatureView(store: Store(
        initialState: FilesFeature.State(loadPhase: .failed("The network connection was lost."))
    ) { FilesFeature() })
}
