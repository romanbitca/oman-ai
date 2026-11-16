#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import OmanCore
import SwiftUI

struct StylesSettingsView: View {
    let model: SettingsViewModel
    @State private var editedID: UUID?

    private var editedStyle: WritingStyle? {
        model.styles.first { $0.id == editedID }
    }

    var body: some View {
        SettingsForm {
            Section {
                ForEach(model.styles) { style in
                    LabeledContent {
                        Button("Edit…") { edit(style.id) }
                    } label: {
                        Text(style.displayName)
                        Text(summary(of: style))
                    }
                }
                Button("Add a Style…") {
                    model.createStyle()
                    editedID = model.selectedStyleID
                }
                if let error = model.styleError {
                    SettingsError(text: error)
                }
            } header: {
                Text("Your styles")
            } footer: {
                Text("A style is a handful of messages you wrote. OmanAI writes in their voice when you choose it.")
            }

            if !model.styles.isEmpty {
                Section("Choosing a style") {
                    Picker(selection: model.preference(\.defaultStyleID)) {
                        Text("As written").tag(UUID?.none)
                        ForEach(model.styles) { style in
                            Text(style.displayName).tag(UUID?.some(style.id))
                        }
                    } label: {
                        Text("Default style")
                        Text("Chosen when an app has no style of its own yet.")
                    }
                    Toggle(isOn: model.preference(\.remembersStylePerApp)) {
                        Text("Remember the last style in each app")
                        Text("Slack can keep one style and Mail another.")
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { editedStyle != nil }, set: { if !$0 { editedID = nil } })) {
            if let style = editedStyle {
                StyleEditorView(model: model, style: style) { editedID = nil }
            }
        }
    }

    private func edit(_ id: UUID) {
        model.selectStyle(id)
        editedID = id
    }

    private func summary(of style: WritingStyle) -> String {
        switch style.samples.count {
        case 0: "No messages yet"
        case 1: "1 message"
        default: "\(style.samples.count) messages"
        }
    }
}

/// One style, edited in a sheet over Settings. Every change is saved as it is made.
private struct StyleEditorView: View {
    @Bindable var model: SettingsViewModel
    let style: WritingStyle
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(text: Binding(get: { style.name }, set: { model.updateName($0) }), prompt: Text("Style name")) {
                        Text("Name")
                    }
                    TextField(
                        text: Binding(get: { style.note }, set: { model.updateNote($0) }),
                        prompt: Text("For example: no emoji with clients")
                    ) {
                        Text("Note")
                    }
                }
                messages
            }
            .formStyle(.grouped)

            Divider()

            // Below the list instead of at its end, so a style with many messages can still be tried without
            // scrolling past all of them.
            Form {
                tryIt
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Delete Style…", role: .destructive, action: askToDelete)
                Spacer()
                // Escape closes the sheet. Return is left to the fields, where it adds a line or tries the style.
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 520, height: 600)
        .withoutSystemWritingTools()
    }

    /// A style and its messages can't be brought back, so macOS's own alert asks first. Cancel is the button
    /// that Return presses.
    private func askToDelete() {
        Platform.confirm(
            "Delete “\(style.displayName)”?",
            detail: "Its messages and its shortcut go with it. This can't be undone."
        ) {
            onClose()
            model.deleteSelectedStyle()
        }
    }

    private var messages: some View {
        Section {
            // The box comes first and the newest message lands right under it, so adding several in a row
            // never needs scrolling.
            TextEditor(text: $model.newSampleText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(height: 58)
                .overlay(alignment: .topLeading) {
                    if model.newSampleText.isEmpty {
                        Text("Paste a real message you wrote")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            LabeledContent {
                Button("Add Message") { model.addSample() }
                    .disabled(model.newSampleText.trimmed.isEmpty)
            } label: {
                Text("\(model.sampleSummary). Five or more work best.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(style.samples.reversed()) { sample in
                HStack(alignment: .top, spacing: 8) {
                    Text(sample.text)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        model.removeSample(id: sample.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove message")
                    .accessibilityLabel("Remove message")
                }
            }
        } header: {
            Text("Your messages")
        }
    }

    private var tryIt: some View {
        Section("Try it") {
            HStack(spacing: 8) {
                TextField("Sentence", text: $model.tryItText, prompt: Text("Type a sentence to rewrite in this style"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.tryIt() }
                Button("Try") { model.tryIt() }
                    .disabled(model.tryItText.trimmed.isEmpty || model.isTrying)
            }
            if model.isTrying, model.tryItResult.isEmpty {
                Text("Writing…").foregroundStyle(.secondary)
            }
            if !model.tryItResult.isEmpty {
                // A long result scrolls in place, so the sheet doesn't change shape while it is written.
                ScrollView(.vertical) {
                    Text(model.tryItResult)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 88)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.tryItError {
                SettingsError(text: error)
            }
        }
    }
}
