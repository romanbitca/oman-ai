import AppKit
import OmanCore
import SwiftUI

struct ContextSectionView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.gap) {
            HStack(spacing: 6) {
                if model.capture.app != nil {
                    ContextChip(title: "Screen", symbol: "macwindow", isOn: model.includeScreen) {
                        model.setIncludeScreen(!model.includeScreen)
                    }
                }
                ContextChip(title: "Messages", symbol: "text.alignleft", isOn: model.isContextExpanded) {
                    model.isContextExpanded.toggle()
                }
                if model.clipboardCandidate != nil {
                    ContextChip(title: "Clipboard", symbol: "doc.on.clipboard", isOn: false) {
                        model.useClipboard()
                    }
                }
            }

            if let hint = model.screenHint {
                NoticeText(text: hint).padding(.horizontal, 6)
            }

            if let screenshot = model.screenshot {
                ScreenshotThumbnail(screenshot: screenshot) {
                    model.setIncludeScreen(false)
                }
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }

            if model.isContextExpanded {
                TextEditor(text: $model.contextText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focusEffectDisabled()
                    .frame(height: 84)
                    .padding(9)
                    .liquidGlass(in: PanelShape.tile)
                    .overlay(alignment: .topLeading) {
                        if model.contextText.isEmpty {
                            Text("Paste messages for context")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 9)
                                .allowsHitTesting(false)
                        }
                    }
                    .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(Liquid.morph, value: model.isContextExpanded)
        .animation(Liquid.morph, value: model.screenshot)
    }
}

private struct ContextChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(isOn ? Color.white : Color.secondary)
            .contentShape(Capsule())
            .liquidGlass(in: Capsule(), tint: isOn ? Liquid.accent : nil, interactive: true)
        }
        .buttonStyle(LiquidPressStyle())
        .animation(Liquid.press, value: isOn)
    }
}

private struct ScreenshotThumbnail: View {
    let screenshot: ScreenshotAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = NSImage(data: screenshot.jpegData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            PanelIconButton(symbol: "xmark.circle.fill", label: "Remove screenshot", action: onRemove)
                .padding(3)
        }
        .padding(7)
        .liquidGlass(in: PanelShape.tile)
    }
}
