import AppKit
import OmanCore
import SwiftUI

struct ContextSectionView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.capture.app != nil {
                Toggle(
                    "Include screen",
                    isOn: Binding(get: { model.includeScreen }, set: { model.setIncludeScreen($0) })
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                if let hint = model.screenHint {
                    NoticeText(text: hint)
                }
                if let screenshot = model.screenshot {
                    ScreenshotThumbnail(screenshot: screenshot) {
                        model.setIncludeScreen(false)
                    }
                }
            }

            DisclosureGroup("Add messages", isExpanded: $model.isContextExpanded) {
                TextEditor(text: $model.contextText)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(height: 80)
                    .padding(4)
                    .background(
                        Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            .font(.system(size: 12))

            if model.clipboardCandidate != nil {
                Button {
                    model.useClipboard()
                } label: {
                    Label("Use clipboard", systemImage: "doc.on.clipboard")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
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
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            PanelIconButton(symbol: "xmark.circle.fill", label: "Remove screenshot", action: onRemove)
        }
    }
}
