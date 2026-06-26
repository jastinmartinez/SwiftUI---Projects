import SwiftUI

struct FileRowAccessoryView: View {
    let model: Model

    var body: some View {
        switch model {
        case .remote:
            Image(systemName: "cloud")
                .font(.system(size: 18))
                .foregroundStyle(Color.filerGray)
        case let .progress(fraction, label):
            ZStack {
                Circle()
                    .stroke(Color.filerGray.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.filerIconTint, style: .init(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.filerGray)
            }
            .frame(width: 26, height: 26)
        case .local:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.filerGreen)
        case .failed:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 18))
                .foregroundStyle(Color.filerPurple)
        }
    }
}
