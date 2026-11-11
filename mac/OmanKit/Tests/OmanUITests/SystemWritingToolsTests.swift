import AppKit
import OmanCore
import SwiftUI
import Testing
@testable import OmanUI

private func textViews(in view: NSView) -> [NSTextView] {
    (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
}

private func firstEditableField(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable { return field }
    return view.subviews.lazy.compactMap(firstEditableField).first
}

@MainActor
@Suite struct SystemWritingToolsTests {
    /// Apple's Writing Tools button floated over the panel and took clicks meant for Back.
    @available(macOS 15.0, *)
    @Test func thePanelTurnsAppleWritingToolsOffForItsText() async throws {
        let model = Harness().makePanel()
        model.begin(with: SelectionCapture(app: Harness.slack, text: "hey can u send it"))
        model.isContextExpanded = true
        let host = NSHostingView(rootView: PanelRootView(model: model))
        host.frame = CGRect(origin: .zero, size: PanelRootView.windowSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()

        let editors = textViews(in: host)
        try #require(!editors.isEmpty)
        #expect(editors.allSatisfy { $0.writingToolsBehavior == .none })

        // A one-line field only has its text view while someone is typing in it.
        let field = try #require(firstEditableField(in: host))
        window.makeFirstResponder(field)
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        #expect(fieldEditor.writingToolsBehavior == .none)
    }
}
