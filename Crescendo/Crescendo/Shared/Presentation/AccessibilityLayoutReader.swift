import SwiftUI

/// Converts SwiftUI's Dynamic Type environment value into app-owned layout semantics.
struct AccessibilityLayoutReader<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let content: (AccessibilityLayout) -> Content

    init(@ViewBuilder content: @escaping (AccessibilityLayout) -> Content) {
        self.content = content
    }

    var body: some View {
        content(AccessibilityLayout(dynamicTypeSize: dynamicTypeSize))
    }
}
