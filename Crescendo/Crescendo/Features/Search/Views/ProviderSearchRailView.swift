import SwiftUI

/// Renders one provider's nonempty first-page results as a horizontal rail.
///
/// The view receives immutable presentation values and interaction callbacks.
/// Loading, empty, and failure presentation belong to the aggregate Search
/// feature. This view owns no Store, provider request, continuation trigger,
/// localization lookup, navigation, or playback behavior.
struct ProviderSearchRailView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.tracks) { track in
                        Button {
                            model.onTrackTapped(track.id)
                        } label: {
                            TrackRowView(model: track)
                                .frame(width: 300, alignment: .leading)
                                .background {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            Color(uiColor: .secondarySystemGroupedBackground)
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(
                                    red: 251.0 / 255.0,
                                    green: 104.0 / 255.0,
                                    blue: 120.0 / 255.0
                                ),
                                Color(
                                    red: 128.0 / 255.0,
                                    green: 92.0 / 255.0,
                                    blue: 215.0 / 255.0
                                ),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                Text(model.title)
                    .font(.headline.bold())
            }

            Spacer()

            Button(model.seeAllTitle, action: model.onSeeAll)
                .font(.caption.bold())
                .tint(
                    Color(
                        red: 156.0 / 255.0,
                        green: 57.0 / 255.0,
                        blue: 115.0 / 255.0
                    )
                )
        }
    }
}

extension ProviderSearchRailView {
    /// The complete result presentation and interaction contract for one rail.
    struct Model {
        let id: ProviderID
        let title: String
        let tracks: [TrackRowView.Model]
        let seeAllTitle: String
        let onSeeAll: () -> Void
        let onTrackTapped: (TrackID) -> Void
    }
}
