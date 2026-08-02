import SwiftUI

/// Renders the stateless Library overview and its primary affordances.
///
/// The view owns overview layout, loading and empty presentation, counts, and
/// the limited Recently Added list. It does not hold a Store, localize text,
/// sort or count Library data, present the file picker, navigate, or control
/// playback.
struct LibraryOverviewView: View {
    let model: Model

    var body: some View {
        Group {
            switch model.loadingPresentation {
            case .initial:
                ProgressView(model.strings.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .refreshing, .hidden:
                overview
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(model.strings.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.loadingPresentation == .refreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(model.strings.importMusic, action: model.onImport)
                    .disabled(!model.isImportEnabled)
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                counts

                if model.isEmpty {
                    ContentUnavailableView {
                        Label(model.strings.emptyTitle, systemImage: "music.note.list")
                    } description: {
                        Text(model.strings.emptyMessage)
                    } actions: {
                        Button(model.strings.importMusic, action: model.onImport)
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.isImportEnabled)
                    }
                } else {
                    recentlyAdded
                }
            }
            .padding(20)
        }
    }

    private var counts: some View {
        HStack(spacing: 12) {
            countCard(
                value: model.songCount,
                title: model.strings.songs,
                action: model.onOpenSongs
            )
            countCard(
                value: model.albumCount,
                title: model.strings.albums,
                action: nil
            )
        }
    }

    private var recentlyAdded: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.strings.recentlyAdded)
                    .font(.title2.bold())
                Spacer()
                Button(model.strings.songs, action: model.onOpenSongs)
                    .font(.subheadline.weight(.semibold))
            }

            LazyVStack(spacing: 0) {
                ForEach(model.recentlyAdded) { track in
                    LibraryTrackRowView(model: track)

                    if track.id != model.recentlyAdded.last?.id {
                        Divider()
                            .padding(.leading, 88)
                    }
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24)
            )
        }
    }

    private func countCard(
        value: Int,
        title: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(value, format: .number)
                    .font(.title.bold())
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

extension LibraryOverviewView {
    /// The immutable presentation contract for the Library overview.
    struct Model {
        let songCount: Int
        let albumCount: Int
        let recentlyAdded: [LibraryTrackRowView.Model]
        let isEmpty: Bool
        let isImportEnabled: Bool
        let loadingPresentation: LoadingPresentation
        let strings: Strings
        let onImport: () -> Void
        let onOpenSongs: () -> Void
    }
}

extension LibraryOverviewView.Model {
    /// Describes how loading appears with or without confirmed Library content.
    enum LoadingPresentation: Equatable {
        case initial
        case refreshing
        case hidden
    }

    /// Contains every localized string rendered by the Library overview.
    struct Strings: Equatable {
        let title: String
        let songs: String
        let albums: String
        let recentlyAdded: String
        let importMusic: String
        let emptyTitle: String
        let emptyMessage: String
        let loading: String
    }
}
