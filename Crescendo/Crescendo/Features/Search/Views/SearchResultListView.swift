import SwiftUI

/// Displays a grouped collection of tappable catalog results.
struct SearchResultListView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.summary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVStack(spacing: 0) {
                ForEach(model.rows) { row in
                    Button {
                        model.onSongTapped(row.id)
                    } label: {
                        SongRowView(model: row.song)
                    }
                    .buttonStyle(.plain)
                    .task(id: row.paginationTriggerID) {
                        guard row.paginationTriggerID != nil else { return }
                        model.onLoadNextPage()
                    }

                    if row.id != model.rows.last?.id {
                        Divider()
                            .padding(.leading, 92)
                    }
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24)
            )

            SearchPaginationFooterView(model: model.footer)
        }
    }
}

extension SearchResultListView {
    struct Model {
        let summary: String
        let rows: [Row]
        let footer: SearchPaginationFooterView.Model
        let onSongTapped: (MusicItemID) -> Void
        let onLoadNextPage: () -> Void
    }
}

extension SearchResultListView.Model {
    struct Row: Equatable, Identifiable {
        let id: MusicItemID
        let song: SongRowView.Model
        let paginationTriggerID: String?
    }
}
