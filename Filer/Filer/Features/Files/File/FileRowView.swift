import SwiftUI

struct FileRowView: View {
    let model: Model

    var body: some View {
        Button { model.send(.tapped) } label: {
            HStack(spacing: 13) {
                FileRowAccessoryView(model: model.accessory)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(model.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.filerGray)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Cancel", role: .destructive) { model.send(.cancelTapped) }
            Button("Retry") { model.send(.retryTapped) }
        }
    }
}
