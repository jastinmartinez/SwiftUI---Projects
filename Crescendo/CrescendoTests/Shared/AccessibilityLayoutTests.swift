import SwiftUI
import Testing

@testable import Crescendo

struct AccessibilityLayoutTests {
    @Test
    func regularDynamicTypeUsesStandardLayout() {
        let layout = AccessibilityLayout(dynamicTypeSize: .large)

        #expect(layout == .standard)
    }

    @Test
    func accessibilityDynamicTypeUsesExpandedLayout() {
        let layout = AccessibilityLayout(dynamicTypeSize: .accessibility1)

        #expect(layout == .expanded)
    }
}
