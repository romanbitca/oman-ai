import AppKit
import OmanCore
import SwiftUI

struct DictationSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsForm {
            switch model.dictationPage {
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
        let suggested = DictationModel.suggested(
            for: model.personLanguages,
            knows: model.modelLanguageCodes,
            unavailable: Set(DictationModel.allCases.filter {
                if case .unavailable = model.modelStatuses[$0] { return true }
                return false
            })
        )
        ForEach(DictationModel.Group.allCases, id: \.self) { group in
            Section {
                ForEach(DictationModel.allCases.filter { $0.group == group }) { candidate in
                    ModelRow(model: model, candidate: candidate, isSuggested: candidate == suggested)
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                        Text(group.explanation)
                            .font(.callout)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if group == DictationModel.Group.allCases.first {
                        ModelLegendButton()
                    }
                }
            } footer: {
                if group == DictationModel.Group.allCases.last {
                    Text("Every model runs on this Mac, so what you say never leaves it. Your transcripts are in OmanAI's window: right-click the wave in the menu bar and choose Open OmanAI.")
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
            HStack(spacing: 8) {
                Image(systemName: "character.cursor.ibeam")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Add a word", text: $model.newDictationWord, prompt: Text("Add a name or a word, such as OmanAI"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .onSubmit { model.addDictationWords() }
                Button("Add") { model.addDictationWords() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.newDictationWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 3)
            if model.preferences.dictationWords.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No words yet").foregroundStyle(.secondary)
                        Text("Names, brands and terms, such as Priya, Kubernetes or your app's name.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(model.preferences.dictationWords, id: \.self) { word in
                        WordToken(word: word) { model.removeDictationWord(word) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        } header: {
            VStack(alignment: .leading, spacing: 10) {
                pagePicker
                HStack {
                    Text("Your words")
                    Spacer()
                    if !model.preferences.dictationWords.isEmpty {
                        Text(model.preferences.dictationWords.count.formatted())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text("Words a model may not know. When it hears something close, it writes them your way. Add several at once with commas between them.")
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

/// One model in the list. It says what Handy's list says, in a look of its own: who made it, whether it is live,
/// how fast and how accurate it is, which of the person's languages it knows, how big its download is, and
/// whether it is in use, downloading or ready. A click chooses it, downloading it first if needed.
private struct ModelRow: View {
    let model: SettingsViewModel
    let candidate: DictationModel
    let isSuggested: Bool
    @State private var showsDetails = false

    private var status: DictationModelStatus? { model.modelStatuses[candidate] }
    private var isChosen: Bool { model.preferences.dictationModel == candidate }
    private var isDownloading: Bool { model.downloadingModel == candidate }
    private var isUnavailable: Bool {
        if case .unavailable = status { return true }
        return false
    }
    private var needsDownload: Bool {
        if case .needsDownload = status { return true }
        return false
    }
    private var codes: Set<String> { model.modelLanguageCodes[candidate] ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModelIcon(candidate: candidate)
                .opacity(isUnavailable ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    titleLine
                    Text(candidate.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 20) {
                    ModelMeter(title: "Speed", symbol: "hare.fill", level: candidate.speed,
                               word: DictationModel.speedWord(candidate.speed), tint: .orange)
                    ModelMeter(title: "Accuracy", symbol: "scope", level: candidate.accuracy,
                               word: DictationModel.accuracyWord(candidate.accuracy), tint: .blue)
                    ModelFact(title: "Download", symbol: "arrow.down.circle", value: candidate.sizeText)
                }
                if !codes.isEmpty {
                    languages
                }
                if let line = statusLine {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDownloading, !isUnavailable, !isChosen else { return }
            model.chooseModel(candidate)
        }
        .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
            ModelDetails(candidate: candidate, codes: codes, personLanguages: model.personLanguages)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(candidate.displayName)
                .font(.headline)
                .foregroundStyle(isUnavailable ? .secondary : .primary)
            if candidate.isLive {
                ModelTag(text: "Live", symbol: "dot.radiowaves.left.and.right", tint: .green)
                    .help("Your words appear while you speak")
            }
            if isSuggested {
                ModelTag(text: "Best for your languages", symbol: "star.fill", tint: .orange)
                    .help("Live, and knows every language in your Language & Region settings")
            }
            Button {
                showsDetails = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("About \(candidate.displayName)")
            .accessibilityLabel("About \(candidate.displayName)")
        }
    }

    /// The person's languages, ticked where the model knows them, then all of its languages, which open its
    /// details.
    private var languages: some View {
        FlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(model.personLanguages, id: \.self) { code in
                LanguageChip(name: Locale.current.localizedString(forLanguageCode: code) ?? code, knows: codes.contains(code))
            }
            Button {
                showsDetails = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(DictationModel.languageCount(codes))
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Every language \(candidate.displayName) knows")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String? {
        if isDownloading, let progress = model.downloadProgress {
            // The files are in; the model is being prepared for the Neural Engine, which takes a while once.
            guard progress < 0.9 else { return "Preparing for this Mac's Neural Engine. This happens once." }
            let percent = (progress / 0.9).formatted(.percent.precision(.fractionLength(0)))
            return "Downloading \(percent) of \(candidate.sizeText), then in use"
        }
        if case .unavailable(let reason) = status {
            return reason
        }
        if candidate == .apple, needsDownload {
            return "macOS downloads this language once, for every app that uses it."
        }
        return nil
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            if isDownloading {
                ProgressView(value: min((model.downloadProgress ?? 0) / 0.9, 1))
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Button {
                    model.cancelDownload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop the download")
                .accessibilityLabel("Stop the download")
            } else if isChosen {
                Label("In use", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else if needsDownload {
                Button("Download") { model.chooseModel(candidate) }
                    .disabled(model.downloadingModel != nil)
            } else if !isUnavailable, status != nil {
                Button("Use") { model.chooseModel(candidate) }
            }
            if candidate.isDownloaded, status == .ready, !isDownloading {
                Menu {
                    Button("About \(candidate.displayName)") { showsDetails = true }
                    Divider()
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

/// A tile in the model's colour with its family's symbol, so the list can be read at a glance.
private struct ModelIcon: View {
    let candidate: DictationModel

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(
                colors: [candidate.tint, candidate.tint.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: candidate.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: candidate.tint.opacity(0.28), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

/// Five steps, filled up to the level, with the level in words under them.
private struct ModelMeter: View {
    let title: String
    let symbol: String
    let level: Int
    let word: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            MeterSteps(level: level, tint: tint)
            Text(word).font(.caption.weight(.medium))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(word)")
    }
}

private struct MeterSteps: View {
    let level: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(1...5, id: \.self) { step in
                Capsule(style: .circular)
                    .fill(step <= level ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(width: 10, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ModelFact: View {
    let title: String
    let symbol: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct ModelTag: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(Capsule(style: .circular).fill(tint.opacity(0.14)))
    }
}

/// One of the person's languages, with a tick where the model knows it.
private struct LanguageChip: View {
    let name: String
    let knows: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: knows ? "checkmark" : "xmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(knows ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
            Text(name)
                .foregroundStyle(knows ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule(style: .circular).fill(knows ? Color.green.opacity(0.13) : Color.primary.opacity(0.06)))
        .help(knows ? "Knows \(name)" : "Doesn't know \(name)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(knows ? "Knows \(name)" : "Doesn't know \(name)")
    }
}

/// Everything about one model, with all of its languages.
struct ModelDetails: View {
    let candidate: DictationModel
    let codes: Set<String>
    let personLanguages: [String]

    private var names: [(code: String, name: String)] {
        codes.map { ($0, Locale.current.localizedString(forLanguageCode: $0) ?? $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ModelIcon(candidate: candidate)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.displayName).font(.headline)
                    Text(candidate.maker).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(candidate.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                row("Speed") {
                    HStack(spacing: 6) {
                        MeterSteps(level: candidate.speed, tint: .orange)
                        Text("\(DictationModel.speedWord(candidate.speed)): \(candidate.pace.lowercased())")
                    }
                }
                row("Accuracy") {
                    HStack(spacing: 6) {
                        MeterSteps(level: candidate.accuracy, tint: .blue)
                        Text(DictationModel.accuracyWord(candidate.accuracy))
                    }
                }
                row("Live") { Text(candidate.isLive ? "Yes, your words appear while you speak" : "No, it reads what you said again about every second") }
                row("Language") { Text(candidate.languageChoice) }
                row("Download") { Text(candidate.sizeText) }
                if candidate.minimumMacOS > 14 {
                    row("Needs") { Text("macOS \(candidate.minimumMacOS) or later") }
                }
                row("Licence") { Text(candidate.license) }
                row("Runs") { Text("On this Mac. What you say never leaves it.") }
            }
            .font(.callout)
            Divider()
            Text(DictationModel.languageCount(codes))
                .font(.subheadline.weight(.semibold))
            // A long list scrolls, so the popover stays a size that fits beside the window.
            if names.count > 30 {
                ScrollView { languageList }
                    .frame(height: 150)
            } else {
                languageList
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var languageList: some View {
        FlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(names, id: \.code) { language in
                let isTheirs = personLanguages.contains(language.code)
                Text(language.name)
                    .font(.caption.weight(isTheirs ? .semibold : .regular))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .circular).fill(isTheirs ? Color.green.opacity(0.15) : Color.primary.opacity(0.06)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, @ViewBuilder _ value: () -> some View) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value().fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The question mark over the list: what Speed, Accuracy, Live and the languages mean.
private struct ModelLegendButton: View {
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Label("How to read the list", systemImage: "questionmark.circle")
                .labelStyle(.iconOnly)
                .font(.body)
        }
        .buttonStyle(.borderless)
        .help("How to read the list")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ModelLegend()
        }
    }
}

struct ModelLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            scale(
                "Speed", note: "How soon your words show.", tint: .orange,
                words: DictationModel.speedWord, meaning: DictationModel.speedMeaning
            )
            Divider()
            scale(
                "Accuracy", note: "How often it writes what you said, judged from published tests and OmanAI's own.",
                tint: .blue, words: DictationModel.accuracyWord, meaning: DictationModel.accuracyMeaning
            )
            Divider()
            Label("Live models show your words while you speak. The others read what you said again about every second, which is often more accurate.", systemImage: "dot.radiowaves.left.and.right")
                .fixedSize(horizontal: false, vertical: true)
            Label("Your languages are the ones in macOS's Language & Region settings.", systemImage: "globe")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(16)
        .frame(width: 380)
    }

    private func scale(
        _ title: String,
        note: String,
        tint: Color,
        words: @escaping (Int) -> String,
        meaning: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { level in
                    GridRow {
                        MeterSteps(level: level, tint: tint)
                        Text(words(level)).fontWeight(.medium)
                        Text(meaning(level)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// One of the person's own words, with a button that takes it out.
private struct WordToken: View {
    let word: String
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Text(word)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isHovered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.borderless)
            .help("Remove \(word)")
            .accessibilityLabel("Remove \(word)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(Capsule(style: .circular).fill(Color.accentColor.opacity(isHovered ? 0.2 : 0.12)))
        .overlay(Capsule(style: .circular).strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.5))
        .onHover { isHovered = $0 }
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
    static func speedWord(_ level: Int) -> String {
        switch level {
        case 5...: "Instant"
        case 4: "Very fast"
        case 3: "Fast"
        case 2: "Moderate"
        default: "Slow"
        }
    }

    static func speedMeaning(_ level: Int) -> String {
        switch level {
        case 5...: "As you speak"
        case 4: "Within a second"
        case 3: "A moment later"
        case 2: "A second or two later"
        default: "A few seconds later"
        }
    }

    static func accuracyWord(_ level: Int) -> String {
        switch level {
        case 5...: "Excellent"
        case 4: "Very good"
        case 3: "Good"
        case 2: "Fair"
        default: "Basic"
        }
    }

    static func accuracyMeaning(_ level: Int) -> String {
        switch level {
        case 5...: "Rarely a word wrong"
        case 4: "A slip now and then"
        case 3: "Fine for everyday messages"
        case 2: "Check names and numbers"
        default: "Rough"
        }
    }

    /// "English only", "25 languages" or "About 100 languages".
    static func languageCount(_ codes: Set<String>) -> String {
        if codes.count == 1, let only = codes.first {
            return "\(Locale.current.localizedString(forLanguageCode: only) ?? only) only"
        }
        return codes.count >= 90 ? "About \(Int((Double(codes.count) / 10).rounded()) * 10) languages" : "\(codes.count) languages"
    }

    /// The model to suggest for the person: the first live one that knows every one of their languages, from
    /// the fastest down. None when they have no languages listed, or no live model knows them all.
    static func suggested(
        for personLanguages: [String],
        knows: [DictationModel: Set<String>],
        unavailable: Set<DictationModel>
    ) -> DictationModel? {
        guard !personLanguages.isEmpty else { return nil }
        return [DictationModel.parakeetEnglish, .nemotron, .apple].first { candidate in
            !unavailable.contains(candidate)
                && personLanguages.allSatisfy { knows[candidate]?.contains($0) ?? false }
        }
    }

    var sizeText: String {
        downloadSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Built in"
    }

    /// The symbol of its family: Apple's, NVIDIA's Parakeet, Nemotron or OpenAI's Whisper.
    var symbol: String {
        switch self {
        case .apple: "laptopcomputer"
        case .parakeetEnglish, .parakeet, .parakeetEnglishV2, .parakeetSmall: "bird.fill"
        case .nemotron: "globe.europe.africa.fill"
        case .whisperLarge, .whisper, .whisperSmall: "wind"
        }
    }

    var tint: Color {
        switch self {
        case .apple: .gray
        case .parakeetEnglish, .parakeet, .parakeetEnglishV2, .parakeetSmall: .green
        case .nemotron: .teal
        case .whisperLarge, .whisper, .whisperSmall: .indigo
        }
    }

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
