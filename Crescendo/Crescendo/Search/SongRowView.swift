import SwiftUI

/// Displays provider-neutral song metadata without owning feature state.
struct SongRowView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading) {
            Text(model.title)
            Text(model.artistName).foregroundStyle(.secondary)
        }
    }
}

extension SongRowView {
    /// The immutable presentation contract for a catalog result row.
    struct Model: Equatable, Identifiable {
        let songID: MusicItemID
        let title: String
        let artistName: String

        var id: MusicItemID { songID }
    }
}
