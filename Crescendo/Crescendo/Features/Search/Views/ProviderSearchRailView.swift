import SwiftUI

/// Renders one provider's first-page search state as a horizontal rail.
///
/// The view receives immutable presentation values and interaction callbacks.
/// It owns no Store, provider request, continuation trigger, localization
/// lookup, navigation, Library routing, or playback behavior.
struct ProviderSearchRailView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 20)

            content
        }
        .onAppear(perform: model.onAppear)
    }

    private var header: some View {
        HStack {
            Text(model.title)
                .font(.title2.bold())

            Spacer()

            if case .loaded = model.content {
                Button(model.strings.seeAll, action: model.onSeeAll)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .inactive:
            EmptyView()

        case .loading:
            ProgressView(model.strings.searching)
                .frame(maxWidth: .infinity, minHeight: 120)

        case .loaded(let tracks):
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(tracks) { track in
                        Button {
                            model.onTrackTapped(track.id)
                        } label: {
                            TrackRowView(model: track)
                                .frame(width: 300, alignment: .leading)
                                .background(
                                    Color(
                                        uiColor:
                                            .secondarySystemGroupedBackground
                                    ),
                                    in: RoundedRectangle(cornerRadius: 20)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

        case .empty(let showsLibraryAction):
            if showsLibraryAction {
                ContentUnavailableView {
                    Label(
                        model.strings.localEmptyTitle,
                        systemImage: "music.note.list"
                    )
                } description: {
                    Text(model.strings.localEmptyMessage)
                } actions: {
                    Button(
                        model.strings.openLibrary,
                        action: model.onOpenLibrary
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .padding(.horizontal, 20)
            } else {
                ContentUnavailableView.search
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .padding(.horizontal, 20)
            }

        case .failed:
            VStack(spacing: 8) {
                Text(model.strings.failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(model.strings.retry, action: model.onRetry)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(.horizontal, 20)
        }
    }
}

extension ProviderSearchRailView {
    /// The complete presentation and interaction contract for one rail.
    struct Model {
        let id: ProviderID
        let title: String
        let content: Content
        let strings: Strings
        let onAppear: () -> Void
        let onRetry: () -> Void
        let onSeeAll: () -> Void
        let onOpenLibrary: () -> Void
        let onTrackTapped: (TrackID) -> Void
    }
}

extension ProviderSearchRailView.Model {
    /// Describes mutually exclusive first-page presentation without pagination.
    enum Content: Equatable {
        case inactive
        case loading
        case loaded([TrackRowView.Model])
        case empty(showsLibraryAction: Bool)
        case failed
    }

    /// Contains every localized string rendered by a provider rail.
    struct Strings: Equatable {
        let searching: String
        let seeAll: String
        let localEmptyTitle: String
        let localEmptyMessage: String
        let openLibrary: String
        let failure: String
        let retry: String
    }
}
