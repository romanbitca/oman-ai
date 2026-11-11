import AppKit
import OmanCore
import SwiftUI

struct ContextSectionView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.gap) {
            HStack(spacing: 6) {
                if model.capture.app != nil, !model.usesLocalModel {
                    ContextChip(title: "Screen", symbol: "macwindow", isOn: model.includeScreen) {
                        model.setIncludeScreen(!model.includeScreen)
                    }
                }
                ContextChip(title: "Messages", symbol: "text.alignleft", isOn: model.includesMessages) {
                    model.setIncludesMessages(!model.includesMessages)
                }
                if model.hasClipboardCandidate {
                    ContextChip(title: "Clipboard", symbol: "doc.on.clipboard", isOn: model.includesClipboard) {
                        model.setIncludesClipboard(!model.includesClipboard)
                    }
                }
            }

            if let hint = model.screenHint {
                NoticeText(text: hint).padding(.horizontal, 6)
            }

            if let screenshot = model.screenshot {
                ScreenshotThumbnail(screenshot: screenshot)
                    .transition(.opacity)
            }

            if model.includesMessages {
                TextEditor(text: $model.contextText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focusEffectDisabled()
                    .frame(height: 84)
                    .padding(9)
                    .panelSurface(in: PanelShape.tile, reading: true)
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
                    .transition(.opacity)
            }

            if let clipboard = model.clipboardContext {
                ClipboardPreview(text: clipboard)
                    .transition(.opacity)
            }
        }
        .animation(Liquid.morph, value: model.includesMessages)
        .animation(Liquid.morph, value: model.clipboardContext)
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
            .foregroundStyle(isOn ? Color.black : Color.secondary)
            .contentShape(Capsule())
            .toggleSurface(isOn: isOn)
        }
        .buttonStyle(GlassPressStyle())
        .animation(Liquid.press, value: isOn)
    }
}

/// All of the clipboard's text that will be sent, to read before sending.
private struct ClipboardPreview: View {
    let text: String

    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 84)
        .fixedSize(horizontal: false, vertical: true)
        .panelSurface(in: PanelShape.tile, reading: true)
    }
}

/// The picture that will be sent, to look at before sending. The Screen chip turns it off again.
private struct ScreenshotThumbnail: View {
    let screenshot: ScreenshotAttachment

    var body: some View {
        if let image = NSImage(data: screenshot.jpegData) {
            // The whole picture, uncropped: this is exactly what will be sent.
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .keepingOwnColors()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: 180)
                .padding(7)
                .panelSurface(in: PanelShape.tile)
        }
    }
}
