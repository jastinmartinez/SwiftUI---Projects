import SwiftUI

#Preview {
    FilesErrorView(model: .init(message: "The network connection was lost.", send: { _ in }))
        .background(Color.filerGroupedBackground)
}
