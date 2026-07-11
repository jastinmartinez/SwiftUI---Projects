import SwiftUI

struct FilesEmptyView: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.filerGray.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: "folder")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.filerIconTint)
            }
            VStack(spacing: 6) {
                Text("No Files")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Tap + to add photos or videos\nfrom your library.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.filerGray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    FilesEmptyView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.filerGroupedBackground)
}
