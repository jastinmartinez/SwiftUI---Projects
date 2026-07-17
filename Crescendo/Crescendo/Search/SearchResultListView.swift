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

            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    Button {
                        model.onSongTapped(row.songID)
                    } label: {
                        SongRowView(model: row)
                    }
                    .buttonStyle(.plain)

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
        }
    }
}

extension SearchResultListView {
    struct Model {
        let summary: String
        let rows: [SongRowView.Model]
        let onSongTapped: (MusicItemID) -> Void
    }
}
