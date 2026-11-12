import AppKit
import OmanCore
import SwiftUI

struct DictationSettingsView: View {
    let model: SettingsViewModel

    var body: some View {
        SettingsForm {
            Section {
                Picker(selection: Binding(
                    get: { model.preferences.dictationModel },
                    set: { model.setDictationModel($0) }
                )) {
                    ForEach(DictationModel.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                } label: {
                    Text("Model")
                    Text(model.preferences.dictationModel.explanation)
                }

                statusRow

                Picker("Language", selection: Binding(
                    get: { model.dictationLanguage ?? .automatic },
                    set: { model.setDictationLanguage($0) }
                )) {
                    if model.dictationLanguages.isEmpty {
                        Text((model.dictationLanguage ?? .automatic).displayName).tag(model.dictationLanguage ?? .automatic)
                    }
                    ForEach(model.dictationLanguages) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .disabled(model.dictationLanguages.count < 2)

                if let error = model.dictationError {
                    SettingsError(text: error)
                }
            } header: {
                Text("Speech model")
            } footer: {
                Text("Every model runs on this Mac, so what you say never leaves it.")
            }

            Section {
                ForEach(ShortcutAction.dictationActions, id: \.self) { action in
                    ShortcutRow(model: model, action: action)
                }
                LabeledContent("Cancel a dictation") {
                    Text("Esc").foregroundStyle(.secondary)
                }
                ShortcutMessages(model: model)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Hold the first shortcut while you speak, and let go to put the words in. For a longer dictation, press the second one to start, and again to finish.")
            }

            Section {
                Picker(selection: model.preference(\.dictationPillStyle)) {
                    ForEach(DictationPillStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                } label: {
                    Text("Look")
                    Text(model.preferences.dictationPillStyle.explanation)
                }
                Picker("Show the words", selection: model.preference(\.dictationPillPosition)) {
                    ForEach(DictationPillPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                microphoneRow
            } header: {
                Text("While you dictate")
            } footer: {
                Text("In OmanAI's panel, your words go straight into the field you're typing in.")
            }

            Section {
                Toggle(isOn: model.preference(\.keepsDictations)) {
                    Text("Keep transcripts")
                    Text("Only the text is kept, on this Mac. The sound never is.")
                }
                if model.savedDictations.isEmpty {
                    Text("No transcripts yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.savedDictations) { dictation in
                        transcriptRow(dictation)
                    }
                    Button("Delete All Transcripts…", role: .destructive) { confirmDeleteAll() }
                }
            } header: {
                Text("Transcripts")
            }
        }
        .recordsShortcuts(model)
        .onAppear { model.reloadDictation() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadDictation()
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        let chosen = model.preferences.dictationModel
        if let progress = model.downloadProgress {
            LabeledContent {
                Button("Cancel") { model.cancelDownload() }
            } label: {
                Text("Downloading…")
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
            }
        } else {
            switch model.dictationStatus {
            case nil:
                LabeledContent("Status") {
                    ProgressView().controlSize(.small)
                }
            case .ready:
                LabeledContent {
                    if chosen.isDownloaded {
                        Button("Remove Download…") { confirmRemove(chosen) }
                    }
                } label: {
                    Text("Ready")
                    Text(chosen.isDownloaded ? "Downloaded to this Mac." : "Part of macOS.")
                }
            case .needsDownload(let bytes):
                LabeledContent {
                    Button("Download") { model.downloadDictationModel() }
                } label: {
                    Text("Needs a download")
                    Text(downloadDetail(bytes: bytes, model: chosen))
                }
            case .unavailable(let reason):
                LabeledContent("Status") {
                    Text(reason)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func downloadDetail(bytes: Int64?, model chosen: DictationModel) -> String {
        let size = bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        switch (chosen.isDownloaded, size) {
        case (false, _): return "macOS downloads this language once."
        case (true, let size?): return "\(size), downloaded once."
        case (true, nil): return "Downloaded once."
        }
    }

    @ViewBuilder
    private var microphoneRow: some View {
        LabeledContent {
            switch model.microphoneAccess {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            case .notDetermined, .denied:
                Button("Allow…") { model.allowMicrophone() }
            }
        } label: {
            Text("Microphone")
            if model.microphoneAccess == .denied {
                Text("Turn on OmanAI in System Settings, under Privacy & Security, then Microphone.")
            }
        }
    }

    private func transcriptRow(_ dictation: SavedDictation) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Button {
                    model.copyDictation(dictation)
                } label: {
                    Image(systemName: model.copiedDictationID == dictation.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
                .accessibilityLabel("Copy")
                Button {
                    model.deleteDictation(id: dictation.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
        } label: {
            Text(dictation.text)
                .lineLimit(4)
                .textSelection(.enabled)
            Text(dictation.detail)
        }
    }

    private func confirmRemove(_ chosen: DictationModel) {
        let alert = NSAlert()
        alert.messageText = "Remove \(chosen.displayName)?"
        alert.informativeText = "Its files are deleted from this Mac. You can download it again at any time."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            model.removeDictationModel()
        }
    }

    private func confirmDeleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all transcripts?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            model.deleteAllDictations()
        }
    }
}

extension DictationModel {
    fileprivate var explanation: String {
        switch self {
        case .apple:
            "Built into macOS 26 and later. It downloads each language the first time."
        case .parakeet:
            "Fast and accurate in 25 European languages, and works out which one you speak."
        case .whisper:
            "Knows about a hundred languages and can work out which one you speak. Slower than Parakeet."
        }
    }
}

extension DictationPillStyle {
    fileprivate var explanation: String {
        switch self {
        case .card:
            "The seconds and Done above, and your words below in a glass card."
        case .floating:
            "Your words float on a soft blur with no box around them, above the seconds and Done."
        }
    }
}

extension SavedDictation {
    /// When it was said and where it went, under the words in the list.
    var detail: String {
        let when = date.formatted(date: .abbreviated, time: .shortened)
        guard let appName else { return when }
        return "\(when) · \(appName)"
    }
}
