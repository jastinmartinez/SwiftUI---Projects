import SwiftUI

/// Presents subscription eligibility without owning feature state.
struct PlaybackEligibilityNoticeView: View {
    let model: Model

    var body: some View {
        switch model.presentation {
        case .hidden:
            EmptyView()
        case .subscriptionRequired:
            Text(Locs.MusicAccess.subscriptionRequired)
        case .availabilityUnknown:
            Text(Locs.MusicAccess.availabilityUnknown)
        }
    }
}
