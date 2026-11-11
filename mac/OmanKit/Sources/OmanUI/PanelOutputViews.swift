import SwiftUI

struct PanelWorkingView: View {
    let model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.gap) {
            ScrollView(.vertical) {
                Text(model.draft.isEmpty ? " " : model.draft)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(minHeight: 84, maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            .liquidGlass(in: PanelShape.tile, id: LiquidID.body, reading: true)
            .overlay { LiquidGlow(shape: PanelShape.tile) }

            HStack(spacing: 8) {
                Text("Writing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Spacer()
                LiquidButton(title: "Stop", symbol: "stop.fill") { model.stop() }
            }
        }
    }
}

struct PanelResultView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.gap) {
            GlassTile(id: LiquidID.header, padding: 10) { header }

            ScrollView(.vertical) {
                Text(displayedText)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(model.showOriginal ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .id(model.showOriginal)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(minHeight: 60, maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
            .liquidGlass(in: PanelShape.tile, id: LiquidID.body, reading: true)
            .animation(.easeOut(duration: 0.18), value: model.showOriginal)

            if let notice = model.notice {
                NoticeText(text: notice).padding(.horizontal, 6)
            }

            HStack(spacing: PanelMetrics.gap) {
                // An explanation is only for reading, so there is nothing to put back in the app.
                if !model.isExplanation {
                    LiquidButton(title: model.primaryActionTitle, prominent: true) { model.applyResult() }
                        .disabled(!model.canApplyResult)
                }
                LiquidButton(title: "Copy", symbol: "doc.on.doc") { model.copyResult() }
                LiquidButton(title: "Try again", symbol: "arrow.trianglehead.2.clockwise") { model.tryAgain() }
            }
            .labelStyle(.titleOnly)

            if !model.isExplanation {
                PanelInputField(symbol: "sparkle", prompt: "Make a change…", text: $model.adjustment) {
                    model.applyAdjustment()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            PanelIconButton(symbol: "chevron.left", label: "Back") { model.goBack() }
            if model.originalText != nil {
                Button {
                    model.showOriginal.toggle()
                } label: {
                    Text(model.showOriginal ? "Show result" : "Show original")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.primary.opacity(model.showOriginal ? 0.1 : 0), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(LiquidPressStyle())
            }
            Spacer(minLength: 0)
            PanelHeaderButtons(model: model)
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
        VStack(alignment: .leading, spacing: PanelMetrics.gap) {
            GlassTile(id: LiquidID.body, reading: true) {
                Label(model.errorMessage ?? "Something went wrong.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: PanelMetrics.gap) {
                LiquidButton(title: "Try again", prominent: true) { model.retryFailed() }
                LiquidButton(title: "Back") { model.goBack() }
                if model.offersSettings {
                    LiquidButton(title: "Open Settings") { model.openSettings() }
                }
            }
        }
    }
}
