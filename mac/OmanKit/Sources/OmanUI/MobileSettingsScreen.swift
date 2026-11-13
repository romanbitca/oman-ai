#if os(iOS)
import OmanCore
import SwiftUI

/// Settings on the iPhone: the same choices as the Mac's, in the phone's own lists, and nothing that only a Mac has,
/// such as shortcuts, the pill's place or Accessibility.
struct MobileSettingsScreen: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                writing
                Section {
                    Picker("Show what Proofread changed", selection: model.preference(\.proofreadChanges)) {
                        ForEach(ProofreadChanges.allCases) { Text($0.displayName).tag($0) }
                    }
                } footer: {
                    Text("At once marks the changed words as soon as a proofread is done. When I ask keeps the result plain.")
                }
                styles
                actions
                if model.offersDictation { dictation }
                about
            }
            .navigationTitle("Settings")
            .navigationDestination(for: MobileSettingsPage.self) { page in
                switch page {
                case .style(let id): MobileStyleEditor(model: model, id: id)
                case .action(let id): MobileActionEditor(model: model, id: id)
                case .dictationModels: MobileDictationModels(model: model)
                case .dictationWords: MobileDictationWords(model: model)
                }
            }
        }
        .onAppear { model.reload() }
    }

    // MARK: Writing

    private var writing: some View {
        Section {
            Picker("Model", selection: Binding(get: { model.selectedModel }, set: { model.setModel($0) })) {
                ForEach(WritingModel.allCases) { writingModel in
                    Text(writingModel.displayName).tag(writingModel)
                }
            }
            if let error = model.modelError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if model.hasAPIKey {
                LabeledContent("Anthropic API key", value: "Saved in the Keychain")
                Button("Remove Key", role: .destructive) { model.removeAPIKey() }
            } else {
                SecureField("Anthropic API key", text: $model.apiKeyDraft)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button(model.isValidatingKey ? "Checking…" : "Save Key") {
                    Task { await model.saveAPIKey() }
                }
                .disabled(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isValidatingKey)
            }
            if let error = model.apiKeyError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Writing")
        } footer: {
            Text(model.selectedModel.isLocal
                ? "Apple's model runs on this iPhone. Nothing you write leaves it."
                : "Claude writes with your own key, from console.anthropic.com. The key stays in this iPhone's Keychain.")
        }
    }

    // MARK: Styles and actions

    private var styles: some View {
        Section {
            ForEach(model.styles) { style in
                NavigationLink(value: MobileSettingsPage.style(style.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.displayName)
                        Text(style.samples.count == 1 ? "1 message" : "\(style.samples.count) messages")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Add a Style") { model.createStyle() }
        } header: {
            Text("Styles")
        } footer: {
            Text("A style rewrites in the voice of real messages you paste into it.")
        }
    }

    private var actions: some View {
        Section {
            ForEach(model.customActions) { action in
                NavigationLink(value: MobileSettingsPage.action(action.id)) {
                    Text(action.displayName)
                }
            }
            Button("Add an Action") { _ = model.createCustomAction() }
        } header: {
            Text("Actions")
        } footer: {
            Text("Your own instructions, such as Make it shorter, run from the panel's first screen.")
        }
    }

    // MARK: Dictation

    private var dictation: some View {
        Section {
            NavigationLink(value: MobileSettingsPage.dictationModels) {
                LabeledContent("Model", value: model.preferences.dictationModel.displayName)
            }
            if !model.dictationLanguages.isEmpty {
                Picker("Language", selection: Binding(
                    get: { model.dictationLanguage ?? .automatic },
                    set: { model.setDictationLanguage($0) }
                )) {
                    ForEach(model.dictationLanguages, id: \.id) { Text($0.displayName).tag($0) }
                }
            }
            NavigationLink(value: MobileSettingsPage.dictationWords) {
                LabeledContent("Your words", value: model.preferences.dictationWords.isEmpty
                    ? "None" : "\(model.preferences.dictationWords.count)")
            }
            Toggle("Remove filler words", isOn: model.preference(\.removesFillerWords))
            if let error = model.dictationError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Dictation")
        } footer: {
            Text("Every model runs on this iPhone, so the sound never leaves it and is never kept.")
        }
        .onAppear { model.reloadDictation() }
    }

    // MARK: About

    private var about: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            Link("Website", destination: URL(string: "https://oman-ai.romanbitca.com")!)
            Link("Source code", destination: URL(string: "https://github.com/romanbitca/oman-ai")!)
        } header: {
            Text("OmanAI")
        } footer: {
            Text("Free and open source. No account, no analytics.")
        }
    }
}

enum MobileSettingsPage: Hashable {
    case style(UUID)
    case action(UUID)
    case dictationModels
    case dictationWords
}

/// A style: its name, a note, and the real messages it is built from.
private struct MobileStyleEditor: View {
    @Bindable var model: SettingsViewModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let style = model.selectedStyle, style.id == id {
                Section("Name") {
                    TextField("Name", text: Binding(get: { style.name }, set: { model.updateName($0) }))
                }
                Section {
                    TextField("Such as: no emoji, sign with my first name", text: Binding(
                        get: { style.note }, set: { model.updateNote($0) }
                    ), axis: .vertical)
                } header: {
                    Text("Note")
                }
                Section {
                    TextField("Paste a message you wrote", text: $model.newSampleText, axis: .vertical)
                        .lineLimit(2...8)
                    Button("Add Message") { model.addSample() }
                        .disabled(model.newSampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(style.samples.reversed()) { sample in
                        Text(sample.text).font(.callout)
                    }
                    .onDelete { offsets in
                        let reversed = Array(style.samples.reversed())
                        for index in offsets { model.removeSample(id: reversed[index].id) }
                    }
                } header: {
                    Text("Messages")
                } footer: {
                    Text(model.sampleSummary)
                }
                Section {
                    Button("Delete Style", role: .destructive) {
                        Platform.confirm(
                            "Delete “\(style.displayName)”?",
                            detail: "Its messages go with it. This can't be undone."
                        ) {
                            model.deleteSelectedStyle()
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(model.selectedStyle?.displayName ?? "Style")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.selectStyle(id) }
    }
}

/// One of the person's own actions: its name, its instruction and what becomes of its result.
private struct MobileActionEditor: View {
    @Bindable var model: SettingsViewModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let action = model.customActions.first(where: { $0.id == id }) {
                Section("Name") {
                    TextField("Such as Make it shorter", text: binding(\.name, in: action))
                }
                Section {
                    TextField("What should it do with the text?", text: binding(\.instruction, in: action), axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Instruction")
                }
                Section("Result") {
                    Picker("Result", selection: binding(\.output, in: action)) {
                        Text("To use").tag(CustomAction.Output.paste)
                        Text("Only to read").tag(CustomAction.Output.read)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Delete Action", role: .destructive) {
                        Platform.confirm("Delete “\(action.displayName)”?", detail: "This can't be undone.") {
                            model.deleteCustomAction(id: id)
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle("Action")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CustomAction, Value> & Sendable, in action: CustomAction) -> Binding<Value> {
        Binding(
            get: { model.customActions.first(where: { $0.id == id })?[keyPath: keyPath] ?? action[keyPath: keyPath] },
            set: { value in model.updateCustomAction(id: id) { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The speech models, in their groups, each said in words: how soon words show, and how big it is.
private struct MobileDictationModels: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        List {
            ForEach(DictationModel.Group.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(DictationModel.allCases.filter { $0.group == group }) { dictationModel in
                        row(dictationModel)
                    }
                }
            }
        }
        .navigationTitle("Dictation Model")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reloadDictation() }
    }

    private func row(_ dictationModel: DictationModel) -> some View {
        let status = model.modelStatuses[dictationModel]
        let isChosen = model.preferences.dictationModel == dictationModel
        return Button {
            model.chooseModel(dictationModel)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dictationModel.displayName).foregroundStyle(.primary)
                    Text(dictationModel.summary).font(.footnote).foregroundStyle(.secondary)
                    Text(detail(dictationModel, status)).font(.caption).foregroundStyle(.secondary)
                    if model.downloadingModel == dictationModel, let progress = model.downloadProgress {
                        ProgressView(value: progress)
                    }
                }
                Spacer(minLength: 0)
                if isChosen {
                    Image(systemName: "checkmark").foregroundStyle(MobilePalette.accent)
                }
            }
        }
        .disabled({ if case .unavailable = status { return true }; return false }())
        .swipeActions {
            if dictationModel.isDownloaded, case .ready = status, !isChosen {
                Button("Delete", role: .destructive) {
                    Platform.confirm(
                        "Delete \(dictationModel.displayName)?",
                        detail: "Its files are deleted from this iPhone. You can download it again at any time."
                    ) { model.removeModel(dictationModel) }
                }
            }
        }
    }

    private func detail(_ dictationModel: DictationModel, _ status: DictationModelStatus?) -> String {
        switch status {
        case .unavailable(let reason): return reason
        case .needsDownload(let bytes):
            let size = (bytes ?? dictationModel.downloadSize).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            return [dictationModel.pace, size.map { "Download \($0)" }].compactMap { $0 }.joined(separator: " · ")
        default:
            return dictationModel.pace
        }
    }
}

/// Names and words a model should write the person's way.
private struct MobileDictationWords: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        List {
            Section {
                TextField("Such as a name, OmanAI or Kubernetes", text: $model.newDictationWord)
                    .onSubmit { model.addDictationWords() }
                Button("Add") { model.addDictationWords() }
                    .disabled(model.newDictationWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("When a model hears something close, it writes these your way.")
            }
            Section {
                ForEach(model.preferences.dictationWords, id: \.self) { Text($0) }
                    .onDelete { offsets in
                        let words = model.preferences.dictationWords
                        for index in offsets { model.removeDictationWord(words[index]) }
                    }
            }
        }
        .navigationTitle("Your Words")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
