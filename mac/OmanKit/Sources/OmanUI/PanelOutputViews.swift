import SwiftUI

struct PanelWorkingView: View {
    let model: PanelViewModel
    private let endID = "end"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.draft.isEmpty ? " " : model.draft)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id(endID)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 300)
                .onChange(of: model.draft) {
                    proxy.scrollTo(endID, anchor: .bottom)
                }
            }

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Writing…").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { model.stop() }
            }
        }
    }
}

struct PanelResultView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                PanelIconButton(symbol: "chevron.left", label: "Back") { model.goBack() }
                if model.originalText != nil {
                    Toggle("Show original", isOn: $model.showOriginal)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.caption)
                }
                Spacer(minLength: 0)
                PanelHeaderButtons(model: model)
            }

            ScrollView(.vertical) {
                Text(displayedText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 260)

            if let notice = model.notice {
                NoticeText(text: notice)
            }

            HStack(spacing: 8) {
                Button(model.primaryActionTitle) { model.applyResult() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canApplyResult)
                Button("Copy") { model.copyResult() }
                Button("Try again") { model.tryAgain() }
            }

            PanelInputField(symbol: "pencil", prompt: "Make a change…", text: $model.adjustment) {
                model.applyAdjustment()
            }
        }
    }

    private var displayedText: String {
        if model.showOriginal, let original = model.originalText {
            return original
        }
        return model.draft
    }
}

struct PanelFailedView: View {
    let model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.errorMessage ?? "Something went wrong.", systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Try again") { model.retryFailed() }
                    .buttonStyle(.borderedProminent)
                Button("Back") { model.goBack() }
                if model.offersSettings {
                    Button("Open Settings") { model.openSettings() }
                }
            }
        }
    }
}
