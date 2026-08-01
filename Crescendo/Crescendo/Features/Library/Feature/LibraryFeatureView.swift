import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

/// The Library feature boundary for navigation, task lifecycle, and file import.
///
/// This is the only Library view that holds a Store. It bridges SwiftUI file
/// selection into reducer actions and composes stateless Library views. It does
/// not open security-scoped resources, import files, compute Library policy,
/// localize rows, control playback, or persist data.
struct LibraryFeatureView: View {
    let store: StoreOf<LibraryReducer>

    var body: some View {
        NavigationStack(path: path) {
            ZStack(alignment: .bottom) {
                LibraryOverviewView(model: .init(store))

                if let summary = LibraryImportSummaryView.Model(store) {
                    LibraryImportSummaryView(model: summary)
                        .padding(20)
                }
            }
            .navigationDestination(for: LibraryReducer.Destination.self) {
                destination in
                switch destination {
                case .songs:
                    LibrarySongsView(model: .init(store))
                }
            }
        }
        .task {
            store.send(.task)
        }
        .fileImporter(
            isPresented: fileImporterPresentation,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true,
            onCompletion: handleFileSelection,
            onCancellation: {
                store.send(.setFileImporterPresented(false))
            }
        )
    }

    private var path: Binding<[LibraryReducer.Destination]> {
        Binding(
            get: { store.path },
            set: { store.send(.pathChanged($0)) }
        )
    }

    private var fileImporterPresentation: Binding<Bool> {
        Binding(
            get: { store.isFileImporterPresented },
            set: { store.send(.setFileImporterPresented($0)) }
        )
    }

    private func handleFileSelection(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            store.send(.filesSelected(urls))
        case .failure:
            store.send(.fileSelectionFailed(.fileReadFailed))
        }
    }
}
