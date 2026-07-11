import PhotosUI
import SwiftUI

struct PhotoLibraryPickerView: View {
    let model: Model

    var body: some View {
        PhotosPicker(
            // Write-only: each pick is consumed immediately and never retained,
            // so the bound selection is always empty.
            selection: .init(get: { [] }, set: { if !$0.isEmpty { model.send(.picked($0)) } }),
            maxSelectionCount: 0,
            matching: .any(of: [.images, .videos])
        ) {
            if model.isLoading {
                ProgressView()
            } else {
                Image(systemName: "plus")
            }
        }
        .disabled(model.isLoading)
        .accessibilityLabel("Add photos or videos")
    }
}
