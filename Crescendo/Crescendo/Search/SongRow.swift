import SwiftUI

/// Displays provider-neutral song metadata without owning feature state.
struct SongRow: View {
    let song: SongSummary

    var body: some View {
        VStack(alignment: .leading) {
            Text(song.title)
            Text(song.artistName).foregroundStyle(.secondary)
        }
    }
}
