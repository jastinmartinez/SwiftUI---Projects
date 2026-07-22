import Foundation
import Testing

@testable import Crescendo

struct PlaybackSliderViewTests {
    @Test
    func scaleMapsAndClampsTrackLocations() {
        let scale = PlaybackSliderView.Model.Scale(range: 20...120)

        #expect(scale.value(at: -10, width: 200) == 20)
        #expect(scale.value(at: 100, width: 200) == 70)
        #expect(scale.value(at: 240, width: 200) == 120)
        #expect(scale.value(at: 10, width: 0) == 20)
    }

    @Test
    func scaleMapsAndClampsPlaybackProgress() {
        let scale = PlaybackSliderView.Model.Scale(range: 20...120)

        #expect(scale.progress(for: 0) == 0)
        #expect(scale.progress(for: 70) == 0.5)
        #expect(scale.progress(for: 140) == 1)
    }
}
