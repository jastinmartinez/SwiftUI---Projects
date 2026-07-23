import SwiftUI

/// Displays the user-facing consequence of the current playback eligibility.
///
/// The adapter selects one mutually exclusive presentation. The view renders that
/// value directly and never inspects provider or feature state.
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

extension PlaybackEligibilityNoticeView {
    /// The immutable presentation contract for playback eligibility messaging.
    struct Model: Equatable {
        let presentation: Presentation
    }
}

extension PlaybackEligibilityNoticeView.Model {
    /// The mutually exclusive eligibility message rendered by the view.
    enum Presentation: Equatable {
        case hidden
        case subscriptionRequired
        case availabilityUnknown
    }
}
