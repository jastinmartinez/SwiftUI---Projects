import Foundation
import SwiftUI

/// Displays and edits playback position without owning workflow state.
struct PlaybackSlider: View {
    let model: Model

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = model.scale.progress(for: model.value)
            let thumbSize: CGFloat = 20
            let thumbOffset = max(width - thumbSize, 0) * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 6)

                Capsule()
                    .fill(LinearGradient.crescendoSpectrum)
                    .frame(width: width * progress, height: 6)

                Circle()
                    .fill(LinearGradient.crescendoSpectrum)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbOffset)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.interaction, Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.onValueChanged(
                            model.scale.value(
                                at: value.location.x,
                                width: width
                            )
                        )
                    }
                    .onEnded { value in
                        model.onValueChanged(
                            model.scale.value(
                                at: value.location.x,
                                width: width
                            )
                        )
                        model.onInteractionEnded()
                    },
                including: model.isEnabled ? .all : .none
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel(model.strings.accessibilityLabel)
        .accessibilityValue(model.strings.accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard model.isEnabled else { return }
            let delta: TimeInterval
            switch direction {
            case .increment:
                delta = model.accessibilityStep
            case .decrement:
                delta = -model.accessibilityStep
            @unknown default:
                return
            }
            model.onValueChanged(model.scale.clamp(model.value + delta))
            model.onInteractionEnded()
        }
        .accessibilityRespondsToUserInteraction(model.isEnabled)
    }
}

extension PlaybackSlider {
    struct Model {
        let value: TimeInterval
        let scale: Scale
        let accessibilityStep: TimeInterval
        let isEnabled: Bool
        let strings: Strings
        let onValueChanged: (TimeInterval) -> Void
        let onInteractionEnded: () -> Void
    }
}

extension PlaybackSlider.Model {
    struct Strings {
        let accessibilityLabel: String
        let accessibilityValue: String
    }

    struct Scale: Equatable {
        let range: ClosedRange<TimeInterval>

        /// Returns a playback value constrained to the scale's range.
        ///
        /// - Parameter value: The playback value to constrain.
        /// - Returns: `value` when it is inside `range`; otherwise, the nearest
        ///   range boundary.
        func clamp(_ value: TimeInterval) -> TimeInterval {
            min(max(value, range.lowerBound), range.upperBound)
        }

        /// Converts a playback value into normalized slider progress.
        ///
        /// - Parameter value: The playback value to locate within `range`.
        /// - Returns: A value from `0` through `1`. Returns `0` when the range
        ///   has no positive distance.
        func progress(for value: TimeInterval) -> CGFloat {
            let distance = range.upperBound - range.lowerBound
            guard distance > 0 else { return 0 }
            return CGFloat((clamp(value) - range.lowerBound) / distance)
        }

        /// Converts a horizontal slider location into a playback value.
        ///
        /// - Parameters:
        ///   - horizontalLocation: The horizontal location in the slider's local
        ///     coordinate space.
        ///   - width: The slider's available track width.
        /// - Returns: The corresponding value constrained to `range`, or the
        ///   lower bound when `width` is not positive.
        func value(at horizontalLocation: CGFloat, width: CGFloat) -> TimeInterval {
            guard width > 0 else { return range.lowerBound }
            let progress = min(max(horizontalLocation / width, 0), 1)
            let distance = range.upperBound - range.lowerBound
            return range.lowerBound + (distance * TimeInterval(progress))
        }
    }
}
