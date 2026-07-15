import SwiftUI

/// Presents subscription eligibility without owning feature state.
struct PlaybackEligibilityNotice: View {
    let eligibility: CatalogPlaybackEligibility
    let showsUnknown: Bool

    var body: some View {
        switch eligibility {
        case .eligible:
            EmptyView()
        case .ineligible:
            Text(Locs.MusicAccess.subscriptionRequired)
        case .unknown:
            if showsUnknown {
                Text(Locs.MusicAccess.availabilityUnknown)
            }
        }
    }
}
