import AVKit
import Dispatch
import MediaPlayer
import QuartzCore
import SwiftUI
import UIKit

/// Presents the operating system's output-volume and route controls.
///
/// MediaPlayer owns the displayed volume while AVKit owns route presentation
/// and selection. This boundary applies Crescendo's appearance through public
/// native APIs without copying system output state into the application or
/// sending playback actions.
struct PlaybackSystemOutputView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        ControlView(frame: .zero)
    }

    func updateUIView(
        _ view: UIView,
        context: Context
    ) {}
}

/// Owns the decorative volume symbol and native output controls in one layout
/// boundary so the symbol can follow the system slider's actual geometry.
///
/// `MPVolumeView` remains responsible for volume behavior and
/// `AVRoutePickerView` remains responsible for route behavior. This view only
/// lays out those native controls and its decorative symbol using their public
/// alignment geometry.
extension PlaybackSystemOutputView {
    @MainActor
    private final class ControlView: UIView {
        private let volumeIconView: UIImageView = {
            let configuration = UIImage.SymbolConfiguration(
                pointSize: 16,
                weight: .semibold
            )
            let imageView = UIImageView(
                image: UIImage(
                    systemName: "speaker.wave.2.fill",
                    withConfiguration: configuration
                )
            )
            imageView.contentMode = .center
            imageView.tintColor = .secondaryLabel
            imageView.isAccessibilityElement = false
            return imageView
        }()

        private let volumeView = MPVolumeView(frame: .zero)
        private let routePickerView: AVRoutePickerView = {
            let routePickerView = AVRoutePickerView(frame: .zero)
            routePickerView.tintColor = .secondaryLabel
            routePickerView.activeTintColor = UIColor(CrescendoSpectrum.violet)
            return routePickerView
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            Appearance.apply(to: volumeView)
            addSubview(volumeIconView)
            addSubview(volumeView)
            addSubview(routePickerView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()

            guard window != nil else { return }

            // MPVolumeView publishes its slider geometry after the first
            // attached layout. Request one follow-up pass so the output row
            // can align every element with that public geometry.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let volumeViewOriginX = Layout.iconWidth + Layout.spacing
            let routePickerOriginX = max(
                volumeViewOriginX,
                bounds.width - Layout.routePickerWidth
            )
            let volumeViewMaxX = max(
                volumeViewOriginX,
                routePickerOriginX - Layout.routePickerSpacing
            )
            volumeView.frame = CGRect(
                x: volumeViewOriginX,
                y: 0,
                width: volumeViewMaxX - volumeViewOriginX,
                height: bounds.height
            )
            routePickerView.frame = CGRect(
                x: routePickerOriginX,
                y: 0,
                width: Layout.routePickerWidth,
                height: bounds.height
            )
            volumeView.layoutIfNeeded()

            let sliderRect = volumeView.volumeSliderRect(
                forBounds: volumeView.bounds
            )

            // Early layout can report zero width while preserving the native
            // track's vertical geometry, so width must not select the fallback.
            let volumeTrackCenterY: CGFloat
            if sliderRect.height > 0 {
                // Center the native track in the row so the decorative symbol
                // and route picker can retain full, in-bounds frames.
                volumeView.frame.origin.y = bounds.midY - sliderRect.midY
                volumeTrackCenterY = bounds.midY
            } else {
                volumeTrackCenterY = bounds.midY
            }

            let volumeIconFrame = CGRect(
                x: 0,
                y: volumeTrackCenterY - (Layout.iconHeight / 2),
                width: Layout.iconWidth,
                height: Layout.iconHeight
            )
            let volumeIconAlignmentRect = volumeIconView.alignmentRect(
                forFrame: volumeIconFrame
            )
            volumeIconView.frame = volumeIconFrame.offsetBy(
                dx: 0,
                dy: volumeTrackCenterY - volumeIconAlignmentRect.midY
            )

            let routePickerAlignmentRect = routePickerView.alignmentRect(
                forFrame: routePickerView.frame
            )
            routePickerView.frame = routePickerView.frame.offsetBy(
                dx: 0,
                dy: volumeTrackCenterY - routePickerAlignmentRect.midY
            )
        }
    }

    private enum Layout {
        static let iconWidth: CGFloat = 24
        static let iconHeight: CGFloat = 24
        static let spacing: CGFloat = 12
        static let routePickerSpacing: CGFloat = 8
        static let routePickerWidth: CGFloat = 44
    }
}

/// Produces decorative images for the public `MPVolumeView` appearance API.
///
/// The renderer does not inspect native subviews, handle gestures, read or
/// write system volume, or alter the separate system-owned route picker.
extension PlaybackSystemOutputView {
    @MainActor
    private enum Appearance {
        static func apply(to volumeView: MPVolumeView) {
            volumeView.setMinimumVolumeSliderImage(
                minimumTrackImage,
                for: .normal
            )
            volumeView.setMaximumVolumeSliderImage(
                maximumTrackImage,
                for: .normal
            )
            volumeView.setVolumeThumbImage(
                thumbImage,
                for: .normal
            )
        }

        private static let minimumTrackImage = makeSpectrumImage(
            size: CGSize(width: 256, height: 6)
        )
        .resizableImage(
            withCapInsets: UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3),
            resizingMode: .stretch
        )

        private static let thumbImage = makeSpectrumImage(
            size: CGSize(width: 20, height: 20)
        )

        private static let maximumTrackImage = makeMaximumTrackImage()

        private static func makeSpectrumImage(size: CGSize) -> UIImage {
            UIGraphicsImageRenderer(size: size).image { context in
                let bounds = CGRect(origin: .zero, size: size)
                let gradient = CAGradientLayer()
                gradient.frame = bounds
                gradient.colors = CrescendoSpectrum.colors.map {
                    UIColor($0).cgColor
                }
                gradient.startPoint = CGPoint(x: 0, y: 0.5)
                gradient.endPoint = CGPoint(x: 1, y: 0.5)
                gradient.cornerRadius = min(size.width, size.height) / 2
                gradient.masksToBounds = true
                gradient.render(in: context.cgContext)
            }
        }

        private static func makeMaximumTrackImage() -> UIImage {
            let secondaryColor = UIColor.secondaryLabel.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .light)
            )
            let color = secondaryColor.withAlphaComponent(
                secondaryColor.cgColor.alpha * 0.2
            )
            let size = CGSize(width: 7, height: 6)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                let bounds = CGRect(origin: .zero, size: size)
                context.cgContext.setFillColor(color.cgColor)
                context.cgContext.addPath(
                    UIBezierPath(
                        roundedRect: bounds,
                        cornerRadius: 3
                    ).cgPath
                )
                context.cgContext.fillPath()
            }
            return image.resizableImage(
                withCapInsets: UIEdgeInsets(
                    top: 0,
                    left: 3,
                    bottom: 0,
                    right: 3
                ),
                resizingMode: .stretch
            )
        }
    }
}
