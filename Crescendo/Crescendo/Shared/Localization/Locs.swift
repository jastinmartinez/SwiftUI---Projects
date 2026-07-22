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
        static let action = String(localized: "search.action")
        static let clear = String(localized: "search.clear")
        static let prompt = String(localized: "search.prompt")
        static let emptyTitle = String(localized: "search.empty_title")
        static let searching = String(localized: "search.searching")
        static let loadingMore = String(localized: "search.loading_more")
        static let loadMoreFailed = String(localized: "search.load_more_failed")
        static let requiresProviderTitle = String(
            localized: "search.requires_provider.title"
        )
        static let requiresProviderMessage = String(
            localized: "search.requires_provider.message"
        )

        static func resultsSummary(
            count: Int,
            providerName: String?
        ) -> String {
            let countFormat =
                count == 1
                ? String(localized: "search.result_count")
                : String(localized: "search.results_count")
            let countText = String(format: countFormat, Int64(count))
            guard let providerName else { return countText }
            return String(
                format: String(localized: "search.results_provider"),
                countText,
                providerName
            )
        }
    }

    enum MusicAccess {
        static let subscriptionRequired = String(
            localized: "music_access.subscription_required"
        )
        static let availabilityUnknown = String(
            localized: "music_access.availability_unknown"
        )
    }

    enum Playback {
        static let noSelection = String(localized: "music_playback.no_selection")
        static let play = String(localized: "music_playback.play")
        static let pause = String(localized: "music_playback.pause")
        static let position = String(localized: "music_playback.position")
        static let stop = String(localized: "music_playback.stop")
        static let restart = String(localized: "music_playback.restart")
        static let backwardFifteenSeconds = String(
            localized: "music_playback.backward_fifteen_seconds"
        )
        static let forwardFifteenSeconds = String(
            localized: "music_playback.forward_fifteen_seconds"
        )

        static func positionValue(
            elapsedTime: String,
            durationTime: String
        ) -> String {
            String(
                format: String(localized: "music_playback.position_value"),
                elapsedTime,
                durationTime
            )
        }

        static func playingFrom(_ providerName: String) -> String {
            String(
                format: String(localized: "music_playback.playing_from"),
                providerName
            )
        }

        enum Status {
            static let idle = String(localized: "music_playback.status.idle")
            static let loading = String(localized: "music_playback.status.loading")
            static let playing = String(localized: "music_playback.status.playing")
            static let paused = String(localized: "music_playback.status.paused")
            static let stopped = String(localized: "music_playback.status.stopped")
            static let failed = String(localized: "music_playback.status.failed")
            static let unavailable = String(localized: "music_playback.status.unavailable")
        }
    }

    enum ProviderSelection {
        static let menuTitle = String(localized: "provider_selection.menu_title")
        static let connect = String(localized: "provider_selection.connect")
        static let connecting = String(localized: "provider_selection.connecting")
        static let needsAccessIndicator = String(
            localized: "provider_selection.needs_access_indicator"
        )
        static let restrictedIndicator = String(
            localized: "provider_selection.restricted_indicator"
        )
        static let connectionFailedIndicator = String(
            localized: "provider_selection.connection_failed_indicator"
        )
        static let openSettings = String(
            localized: "provider_selection.open_settings"
        )
        static let tryAgain = String(localized: "provider_selection.try_again")

        static func connectingTo(_ providerName: String) -> String {
            String(
                format: String(localized: "provider_selection.connecting_to"),
                providerName
            )
        }

        static func needsAccess(_ providerName: String) -> String {
            String(
                format: String(localized: "provider_selection.needs_access"),
                providerName
            )
        }

        static func restricted(_ providerName: String) -> String {
            String(
                format: String(localized: "provider_selection.restricted"),
                providerName
            )
        }

        static func connectionFailed(_ providerName: String) -> String {
            String(
                format: String(
                    localized: "provider_selection.connection_failed"
                ),
                providerName
            )
        }
    }
}
