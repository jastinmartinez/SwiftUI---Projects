import SwiftUI

struct FilesLoadingView: View {
    var body: some View {
        ProgressView("Loading…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FilesLoadingView()
        .background(Color.filerGroupedBackground)
}
