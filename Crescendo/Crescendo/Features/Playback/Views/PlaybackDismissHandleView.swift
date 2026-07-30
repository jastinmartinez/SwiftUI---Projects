import SwiftUI

/// Displays the full-screen player's explicit dismissal affordance.
///
/// A tap dismisses immediately. A downward drag dismisses only after crossing
/// the view-owned gesture threshold.
struct PlaybackDismissHandleView: View {
    let model: Model

    var body: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(model.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                model.onDismiss()
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        guard value.translation.height >= 60 else { return }
                        model.onDismiss()
                    }
                    .exclusively(
                        before: TapGesture()
                            .onEnded {
                                model.onDismiss()
                            }
                    )
            )
    }
}

extension PlaybackDismissHandleView {
    /// The localized label and reducer-routed dismissal callback.
    struct Model {
        let accessibilityLabel: String
        let onDismiss: () -> Void
    }
}
