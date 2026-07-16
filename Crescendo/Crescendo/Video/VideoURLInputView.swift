import SwiftUI

/// Renders Video URL entry and loading feedback from explicit values and callbacks.
struct VideoURLInputView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                Locs.Video.urlPrompt,
                text: Binding(
                    get: { model.urlText },
                    set: { model.onURLChanged($0) }
                )
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .disabled(model.isLoading)
            .onSubmit(model.onLoad)

            Text(Locs.Video.urlGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Button(
                Locs.Video.loadAction,
                action: model.onLoad
            )
            .disabled(model.isLoadDisabled)

            if model.isLoading {
                ProgressView(Locs.Video.loading)
            }
        }
    }
}

extension VideoURLInputView {
    struct Model {
        let urlText: String
        let isLoading: Bool
        let errorMessage: String?
        let isLoadDisabled: Bool
        let onURLChanged: (String) -> Void
        let onLoad: () -> Void
    }
}
