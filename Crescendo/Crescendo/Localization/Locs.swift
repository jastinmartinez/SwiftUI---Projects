import Foundation

/// Typed access to every user-facing string. Nested enums mirror features;
/// keys resolve through Localizable.xcstrings.
enum Locs {
    enum App {
        static let title = String(localized: "app.title")
    }
}

extension Locs {
    enum Common {
        static let retry = String(localized: "common.retry")
    }

    enum Search {
        static let prompt = String(localized: "search.prompt")
        static let emptyTitle = String(localized: "search.empty_title")
        static let searching = String(localized: "search.searching")
        static let unavailableTitle = String(localized: "search.unavailable_title")
        static let videoStillAvailable = String(localized: "search.video_still_available")
    }

    enum MusicAccess {
        static let subscriptionRequired = String(
            localized: "music_access.subscription_required"
        )
        static let availabilityUnknown = String(
            localized: "music_access.availability_unknown"
        )
    }
}
