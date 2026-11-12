import AppKit
import OmanCore
import SwiftUI

struct DictationSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsForm {
            switch model.dictationPage {
            case .transcripts: transcriptsPage
            case .model: modelPage
            case .look: lookPage
            case .words: wordsPage
            case .sound: soundPage
            }
        }
        .onAppear { model.reloadDictation() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadDictation()
        }
    }

    /// The parts of the page, above the first section of each.
    private var pagePicker: some View {
        Picker("Show", selection: $model.dictationPage) {
            ForEach(DictationPage.allCases) { page in
                Text(page.title).tag(page)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    // MARK: Transcripts

    @ViewBuilder
    private var transcriptsPage: some View {
        Section {
            Picker(selection: model.preference(\.dictationHistory)) {
                ForEach(DictationHistory.allCases) { history in
                    Text(history.displayName).tag(history)
                }
            } label: {
                Text("Keep")
                Text("Only the text is kept, on this Mac. The sound never is.")
            }
        } header: {
            pagePicker
        }
        Section {
            if model.savedDictations.isEmpty {
                Text(model.preferences.dictationHistory == .off ? "Transcripts aren't kept." : "No transcripts yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.savedDictations) { dictation in
                    transcriptRow(dictation)
                }
            }
        } header: {
            Text("Transcripts")
        } footer: {
            if !model.savedDictations.isEmpty {
                HStack {
                    Spacer()
                    Button("Delete All Transcripts…", role: .destructive) { confirmDeleteAll() }
                }
            }
        }
        if let error = model.dictationError {
            Section { SettingsError(text: error) }
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

    // MARK: Model

    @ViewBuilder
    private var modelPage: some View {
        let chosen = model.preferences.dictationModel
        Section {
            Picker(selection: Binding(
                get: { model.dictationLanguage ?? .automatic },
                set: { model.setDictationLanguage($0) }
            )) {
                if model.dictationLanguages.isEmpty {
                    Text((model.dictationLanguage ?? .automatic).displayName).tag(model.dictationLanguage ?? .automatic)
                }
                ForEach(model.dictationLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            } label: {
                Text("Language")
                Text("What \(chosen.displayName) listens for.")
            }
            .disabled(model.dictationLanguages.count < 2)
            if chosen == .apple, case .needsDownload = model.dictationStatus {
                LabeledContent {
                    if model.downloadingModel == .apple, let progress = model.downloadProgress {
                        ProgressView(value: progress).frame(width: 120)
                    } else {
                        Button("Download") { model.downloadModel(.apple) }
                    }
                } label: {
                    Text("This language isn't on this Mac yet")
                    Text("macOS downloads it once, for every app that uses it.")
                }
            }
            Picker(selection: model.preference(\.modelUnloadDelay)) {
                ForEach(ModelUnloadDelay.allCases) { delay in
                    Text(delay.displayName).tag(delay)
                }
            } label: {
                Text("Free the memory")
                Text("A model kept in memory starts at once. macOS looks after Apple's itself.")
            }
            if let error = model.dictationError {
                SettingsError(text: error)
            }
        } header: {
            pagePicker
        }
        ForEach(DictationModel.Group.allCases, id: \.self) { group in
            Section {
                ForEach(DictationModel.allCases.filter { $0.group == group }) { candidate in
                    ModelRow(model: model, candidate: candidate)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                    Text(group.explanation)
                        .font(.callout)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if group == DictationModel.Group.allCases.last {
                    Text("Every model runs on this Mac, so what you say never leaves it.")
                }
            }
        }
    }

    // MARK: Look

    @ViewBuilder
    private var lookPage: some View {
        Section {
            LookChoice(model: model)
        } header: {
            pagePicker
        }
        Section {
            Picker("Show the words", selection: model.preference(\.dictationPillPosition)) {
                ForEach(DictationPillPosition.allCases) { position in
                    Text(position.displayName).tag(position)
                }
            }
        } footer: {
            Text("In OmanAI's panel, your words go straight into the field you're typing in.")
        }
    }

    // MARK: Words

    @ViewBuilder
    private var wordsPage: some View {
        Section {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField("Add a word", text: $model.newDictationWord)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit { model.addDictationWords() }
                    Button("Add") { model.addDictationWords() }
                        .disabled(model.newDictationWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } label: {
                Text("Your words")
                Text("Names and words a model may not know, such as an app's name. They're written your way.")
            }
            if !model.preferences.dictationWords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(model.preferences.dictationWords, id: \.self) { word in
                        WordChip(word: word) { model.removeDictationWord(word) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            pagePicker
        }
        Section {
            Toggle(isOn: model.preference(\.removesFillerWords)) {
                Text("Remove filler words")
                Text("Takes out um, uh, er and the like.")
            }
            Toggle(isOn: model.preference(\.addsSpaceAfterDictation)) {
                Text("Add a space after")
                Text("So the next words you type or say don't run into these.")
            }
            Picker(selection: model.preference(\.dictationSubmit)) {
                ForEach(DictationSubmit.allCases) { submit in
                    Text(submit.displayName).tag(submit)
                }
            } label: {
                Text("Then press")
                Text("Sends a message in apps where Return or ⌘Return sends, once your words are in.")
            }
        } header: {
            Text("When your words go in")
        }
    }

    // MARK: Sound

    @ViewBuilder
    private var soundPage: some View {
        Section {
            Picker(selection: model.preference(\.dictationMicrophone)) {
                Text("As in System Settings").tag(String?.none)
                if let chosen = model.preferences.dictationMicrophone,
                   !model.microphones.contains(where: { $0.id == chosen }) {
                    Text("A microphone that isn't connected").tag(String?.some(chosen))
                }
                ForEach(model.microphones) { microphone in
                    Text(microphone.name).tag(String?.some(microphone.id))
                }
            } label: {
                Text("Microphone")
                Text("While the one chosen here isn't connected, the one in System Settings listens.")
            }
            if model.microphoneAccess != .granted {
                LabeledContent {
                    Button(model.microphoneAccess == .denied ? "Open System Settings" : "Allow") {
                        model.allowMicrophone()
                    }
                } label: {
                    Text("OmanAI can't use the microphone yet")
                    Text("Dictation needs it. What you say is turned into text on this Mac.")
                }
            }
        } header: {
            pagePicker
        }
        Section {
            Toggle(isOn: model.preference(\.playsDictationSounds)) {
                Text("Play a sound when listening starts and stops")
            }
            Toggle(isOn: model.preference(\.mutesAudioWhileDictating)) {
                Text("Mute the Mac while you dictate")
                Text("Music and videos go quiet while you speak, and come back when you finish.")
            }
        }
    }
}

/// One model in the list, in plain words: what it's good at, how soon its words show, which of the person's
/// languages it knows and how big it is. A click chooses it, downloading it first if needed.
private struct ModelRow: View {
    let model: SettingsViewModel
    let candidate: DictationModel

    private var status: DictationModelStatus? { model.modelStatuses[candidate] }
    private var isChosen: Bool { model.preferences.dictationModel == candidate }
    private var isDownloading: Bool { model.downloadingModel == candidate }
    private var isUnavailable: Bool {
        if case .unavailable = status { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isChosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName)
                    .fontWeight(.medium)
                    .foregroundStyle(isUnavailable ? .secondary : .primary)
                Text(candidate.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(facts)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDownloading, !isUnavailable else { return }
            model.chooseModel(candidate)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? [.isSelected, .isButton] : .isButton)
    }

    /// How soon the words show, the person's languages, and the size, in one line.
    private var facts: String {
        var parts = [candidate.pace]
        if let codes = model.modelLanguageCodes[candidate], !codes.isEmpty {
            parts.append(DictationModel.languageFit(codes: codes, personLanguages: model.personLanguages))
        }
        if let size = candidate.downloadSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        } else {
            parts.append("Part of macOS")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        if isDownloading, let progress = model.downloadProgress {
            HStack(spacing: 6) {
                // The files are in; the model is being prepared for the Neural Engine, which takes a while once.
                Text(progress >= 0.9 ? "Preparing…" : progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                ProgressView(value: progress).frame(width: 80)
                Button {
                    model.cancelDownload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop the download")
                .accessibilityLabel("Stop the download")
            }
        } else if case .unavailable(let reason) = status {
            Text(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < candidate.minimumMacOS
                ? "Needs macOS \(candidate.minimumMacOS)" : "Not available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(reason)
        } else if case .needsDownload = status, candidate.isDownloaded {
            Button("Download") { model.downloadModel(candidate) }
                .disabled(model.downloadingModel != nil)
        } else if candidate.isDownloaded, status == .ready {
            Menu {
                Button("Delete Download…", role: .destructive) { confirmRemove() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("More")
            .accessibilityLabel("More for \(candidate.displayName)")
        }
    }

    private func confirmRemove() {
        let alert = NSAlert()
        alert.messageText = "Delete \(candidate.displayName)?"
        alert.informativeText = "Its files are deleted from this Mac. You can download it again at any time."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            model.removeModel(candidate)
        }
    }
}

private struct WordChip: View {
    let word: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove \(word)")
            .accessibilityLabel("Remove \(word)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

extension DictationModel.Group {
    var title: String {
        switch self {
        case .live: "Live"
        case .accurate: "Accurate"
        case .small: "Small"
        }
    }

    var explanation: String {
        switch self {
        case .live: "Your words appear while you speak."
        case .accurate: "Your words follow a moment later, read again as you go, which makes them more accurate."
        case .small: "Smaller downloads, for a Mac short on space."
        }
    }
}

extension DictationModel {
    /// Which of the person's languages a model knows, as a phrase such as "25 languages, including English but
    /// not Japanese" or "English only".
    static func languageFit(codes: Set<String>, personLanguages: [String], locale: Locale = .current) -> String {
        func name(_ code: String) -> String {
            locale.localizedString(forLanguageCode: code) ?? code
        }
        func list(_ codes: [String], _ joiner: String) -> String {
            let names = codes.map(name)
            guard let last = names.last, names.count > 1 else { return names.first ?? "" }
            return names.dropLast().joined(separator: ", ") + " \(joiner) " + last
        }
        if codes.count == 1, let only = codes.first {
            return "\(name(only)) only"
        }
        let count = codes.count >= 90 ? "About \(Int((Double(codes.count) / 10).rounded()) * 10) languages"
            : "\(codes.count) languages"
        let known = personLanguages.filter(codes.contains)
        let missing = personLanguages.filter { !codes.contains($0) }
        switch (known.isEmpty, missing.isEmpty) {
        case (false, true): return "\(count), including \(list(known, "and"))"
        case (false, false): return "\(count), including \(list(known, "and")) but not \(list(missing, "or"))"
        case (true, false): return "\(count), but not \(list(missing, "or"))"
        case (true, true): return count
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
