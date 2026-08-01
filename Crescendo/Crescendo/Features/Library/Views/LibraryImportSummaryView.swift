import SwiftUI

/// Renders current Library import progress or a retained terminal summary.
///
/// The view owns summary-card layout only. It does not hold a Store, run the
/// import state machine, invoke clients, localize failures, or decide whether
/// cancellation is accepted.
struct LibraryImportSummaryView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.title)
                    .font(.headline)
                Spacer()
                if let cancelTitle = model.cancelTitle,
                    let onCancel = model.onCancel
                {
                    Button(cancelTitle, action: onCancel)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Text(model.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(model.issueMessages, id: \.self) { issue in
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

extension LibraryImportSummaryView {
    /// The immutable presentation contract for one import lifecycle summary.
    struct Model {
        let title: String
        let detail: String
        let issueMessages: [String]
        let cancelTitle: String?
        let onCancel: (() -> Void)?
    }
}
