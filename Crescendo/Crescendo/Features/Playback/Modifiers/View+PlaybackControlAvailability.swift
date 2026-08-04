import SwiftUI

extension View {
    /// Applies playback interaction and accessibility behavior while preserving
    /// the visual weight of controls blocked only by an in-flight transition.
    ///
    /// - Parameter availability: The command policy result to apply.
    /// - Returns: A view with matching interaction and accessibility behavior.
    func playbackControlAvailability(
        _ availability: PlaybackCommandPolicy.Availability
    ) -> some View {
        disabled(availability == .disabled)
            .allowsHitTesting(availability.isEnabled)
            .accessibilityRespondsToUserInteraction(
                availability.isEnabled
            )
    }
}
