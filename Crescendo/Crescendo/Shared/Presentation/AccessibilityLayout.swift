import SwiftUI

/// Describes the amount of space presentation components need for Dynamic Type.
enum AccessibilityLayout: Equatable, Sendable {
    case standard
    case expanded

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize.isAccessibilitySize ? .expanded : .standard
    }
}
