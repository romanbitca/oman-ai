import AppKit
import OmanCore
import SwiftUI

/// The person's own actions: instructions written once and run on a selection, from the panel or a shortcut.
struct ActionsSettingsView: View {
    let model: SettingsViewModel
    @State private var editedID: UUID?

    private var editedAction: CustomAction? {
        model.customActions.first { $0.id == editedID }
    }

    var body: some View {
        SettingsForm {
            Section {
                ForEach(model.customActions) { action in
                    LabeledContent {
                        Button("Edit…") { editedID = action.id }
                    } label: {
                        Text(action.displayName)
                        Text(summary(of: action))
                    }
                }
                Button("Add an Action…") {
                    editedID = model.createCustomAction()
                }
                if let error = model.customActionError {
                    SettingsError(text: error)
                }
            } header: {
                Text("Your actions")
            } footer: {
                Text("An action is an instruction you write once, such as “Make it shorter” or “Turn into bullet points”. It runs on the text you select, from the panel or from its shortcut.")
            }
        }
        .sheet(isPresented: Binding(get: { editedAction != nil }, set: { if !$0 { editedID = nil } })) {
            if let action = editedAction {
                ActionEditorView(model: model, action: action) { editedID = nil }
            }
        }
    }

    private func summary(of action: CustomAction) -> String {
        guard !action.instruction.trimmed.isEmpty else { return "No instruction yet, so the panel doesn't show it" }
        var parts = [ActionEditorView.title(of: action.output)]
        if let combo = model.preferences.combo(for: .custom(action.id)) {
            parts.append(combo.displayString)
        }
        return parts.joined(separator: " · ")
    }
}

/// One action, edited in a sheet over Settings. Every change is saved as it is made.
struct ActionEditorView: View {
    let model: SettingsViewModel
    let action: CustomAction
    let onClose: () -> Void

    static func title(of output: CustomAction.Output) -> String {
        switch output {
        case .paste: "Replace or Insert"
        case .read: "Only to read"
        }
    }

    private var outputDetail: String {
        switch action.output {
        case .paste: "Replace puts the result over your selection, as with Rewrite. It is written with your template and context."
        case .read: "The answer is only shown in the panel, to read and copy, as with Explain. It uses your context but not your template."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(text: binding(\.name), prompt: Text("Make it shorter")) {
                        Text("Name")
                    }
                }
                Section {
                    TextEditor(text: binding(\.instruction))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(height: 76)
                        .overlay(alignment: .topLeading) {
                            if action.instruction.isEmpty {
                                Text("Shorten it to two sentences and keep every fact")
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Instruction")
                } footer: {
                    Text("Write it as you would in the panel’s Describe your change.")
                }
                Section {
                    Picker(selection: binding(\.output)) {
                        ForEach(CustomAction.Output.allCases) { output in
                            Text(Self.title(of: output)).tag(output)
                        }
                    } label: {
                        Text("Result")
                        Text(outputDetail)
                    }
                    .pickerStyle(.radioGroup)
                    ShortcutRow(model: model, action: .custom(action.id), title: "Shortcut")
                    ShortcutMessages(model: model)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Delete Action…", role: .destructive, action: askToDelete)
                Spacer()
                // Escape closes the sheet, unless a shortcut is being recorded, which Escape stops instead.
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 520, height: 480)
        .recordsShortcuts(model)
        .withoutSystemWritingTools()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CustomAction, Value> & Sendable) -> Binding<Value> {
        Binding(
            get: { action[keyPath: keyPath] },
            set: { value in model.updateCustomAction(id: action.id) { $0[keyPath: keyPath] = value } }
        )
    }

    /// An action can't be brought back, so macOS's own alert asks first. Cancel is the button that Return presses.
    private func askToDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete “\(action.displayName)”?"
        alert.informativeText = "Its shortcut goes with it. This can't be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        onClose()
        model.deleteCustomAction(id: action.id)
    }
}
