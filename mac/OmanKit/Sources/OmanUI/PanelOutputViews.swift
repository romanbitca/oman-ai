import SwiftUI

struct PanelWorkingView: View {
    let model: PanelViewModel
    private let minimumHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.gap) {
            ScrollView(.vertical) {
                Text(model.draft.isEmpty ? " " : model.draft)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    // The scroll view keeps the newest words in view, so it lines up a text shorter than the box
                    // with the box's bottom. Filling the box keeps a short text at the top.
                    .frame(minHeight: minimumHeight, alignment: .top)
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(minHeight: minimumHeight, maxHeight: 340)
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
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.gap) {
            GlassTile(id: LiquidID.header, padding: 10) { header }

            ScrollView(.vertical) {
                resultText
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(model.showOriginal ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .id(shownAs)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(minHeight: 60, maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
            .liquidGlass(in: PanelShape.tile, id: LiquidID.body, reading: true)
            .animation(.easeOut(duration: 0.18), value: shownAs)

            if let notice = model.notice {
                NoticeText(text: notice).padding(.horizontal, 6)
            }

            HStack(spacing: PanelMetrics.gap) {
                // An explanation is only for reading, and a quick fix that went in is in the app already, so there
                // is nothing to put back.
                if !model.isExplanation, !model.showsQuickFixInPlace {
                    LiquidButton(title: model.primaryActionTitle, prominent: true) { model.applyResult() }
                        .disabled(!model.canApplyResult)
                }
                LiquidButton(title: "Copy", symbol: "doc.on.doc") { model.copyResult() }
                if !model.showsQuickFixInPlace {
                    LiquidButton(title: "Try again", symbol: "arrow.trianglehead.2.clockwise") { model.tryAgain() }
                }
            }
            .labelStyle(.titleOnly)

            if !model.isExplanation, !model.showsQuickFixInPlace {
                PanelInputField(
                    symbol: "sparkle",
                    prompt: "Make a change…",
                    text: $model.adjustment,
                    dictation: model.dictation,
                    field: .adjustment
                ) {
                    model.applyAdjustment()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            PanelIconButton(symbol: "chevron.left", label: "Back") { model.goBack() }
            if model.offersChanges, let changes = model.proofreadChanges {
                headerToggle(changesTitle(changes.count), isOn: model.showChanges) { model.showChanges.toggle() }
                    .help(model.showChanges ? "Hide the words that were replaced" : "Show the words that were replaced")
            } else if model.offersOriginal {
                headerToggle(model.showOriginal ? "Show result" : "Show original", isOn: model.showOriginal) {
                    model.showOriginal.toggle()
                }
            } else if model.proofreadChanges != nil {
                Text("No changes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            }
            Spacer(minLength: 0)
            PanelHeaderButtons(model: model)
        }
    }

    private func headerToggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.primary.opacity(isOn ? 0.1 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(LiquidPressStyle())
    }

    private func changesTitle(_ count: Int) -> String {
        switch model.proofreadChangesDisplay {
        case .atOnce: count == 1 ? "1 change" : "\(count) changes"
        case .whenAsked: model.showChanges ? "Hide changes" : "Show changes"
        }
    }

    /// What the text area shows, so switching between them can fade one into the other.
    private enum ShownAs: Hashable { case result, original, marked, markedWithOldWords }

    private var shownAs: ShownAs {
        if model.showOriginal, model.offersOriginal { return .original }
        guard model.offersChanges else { return .result }
        if model.showChanges { return .markedWithOldWords }
        return model.proofreadChangesDisplay == .atOnce ? .marked : .result
    }

    @ViewBuilder private var resultText: some View {
        switch shownAs {
        case .result:
            Text(model.draft).textSelection(.enabled)
        case .original:
            Text(model.originalText ?? "").textSelection(.enabled)
        case .marked:
            // Only the corrected text is on show, so selecting and copying it gives exactly the result.
            Text(marks(showingOldWords: false)).textSelection(.enabled)
        case .markedWithOldWords:
            // The old words are on show too, so a selection would mix both texts. Copy gives the result.
            Text(marks(showingOldWords: true))
                .accessibilityLabel(model.proofreadChanges?.spoken ?? model.draft)
        }
    }

    private func marks(showingOldWords: Bool) -> AttributedString {
        guard let changes = model.proofreadChanges else { return AttributedString(model.draft) }
        return changes.marked(showingOldWords: showingOldWords, underliningNewWords: differentiateWithoutColor)
    }
}

extension TextChanges {
    /// The corrected text with each new word tinted. With `showingOldWords`, the words they replaced are struck
    /// through just before them. Spacing that changed is shown as it is now, since it is not counted as a change.
    func marked(showingOldWords: Bool, underliningNewWords: Bool) -> AttributedString {
        var marked = AttributedString()
        var followsOldWords = false
        for piece in pieces {
            switch piece {
            case .same(let text):
                marked += AttributedString(text)
                followsOldWords = false
            case .removed(let text):
                guard showingOldWords, piece.hasText else { continue }
                var old = AttributedString(text)
                old.swiftUI.foregroundColor = .red
                old.swiftUI.backgroundColor = Color.red.opacity(0.14)
                old.swiftUI.strikethroughStyle = Text.LineStyle(pattern: .solid, color: .red)
                marked += old
                followsOldWords = !(text.last?.isWhitespace ?? true)
            case .added(let text):
                if followsOldWords, text.first?.isWhitespace == false {
                    marked += AttributedString(" ")
                }
                var new = AttributedString(text)
                if piece.hasText {
                    new.swiftUI.backgroundColor = Color.green.opacity(0.3)
                    if underliningNewWords {
                        new.swiftUI.underlineStyle = .single
                    }
                }
                marked += new
                followsOldWords = false
            }
        }
        return marked
    }

    /// The marked text as VoiceOver reads it, with each change named.
    var spoken: String {
        pieces.map { piece in
            switch piece {
            case .same(let text): text
            case .removed(let text): piece.hasText ? " removed: \(text.trimmingCharacters(in: .whitespaces)), " : ""
            case .added(let text): piece.hasText ? " added: \(text.trimmingCharacters(in: .whitespaces)), " : text
            }
        }.joined()
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
