import SwiftUI

#Preview {
    List {
        FileRowView(model: .init(
            name: "Sunset", subtitle: "2.4 MB · Photo",
            accessory: .remote, send: { _ in }
        ))
        FileRowView(model: .init(
            name: "Clip", subtitle: "Uploading 3 MB / 12 MB",
            accessory: .progress(fraction: 0.25, label: "1/4"), send: { _ in }
        ))
        FileRowView(model: .init(
            name: "Saved", subtitle: "8 MB · Video",
            accessory: .local, send: { _ in }
        ))
        FileRowView(model: .init(
            name: "Broken", subtitle: "Failed · Tap to retry",
            accessory: .failed, send: { _ in }
        ))
    }
    .listStyle(.insetGrouped)
}
