import SwiftUI

struct FilesErrorView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.filerPurple)
            Text("Couldn't load files")
                .font(.system(size: 19, weight: .semibold))
            Text(model.message)
                .font(.system(size: 14))
                .foregroundStyle(Color.filerGray)
                .multilineTextAlignment(.center)
            Button("Try Again") { model.send(.retryTapped) }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FilesErrorView(model: .init(message: "The network connection was lost.", send: { _ in }))
        .background(Color.filerGroupedBackground)
}
