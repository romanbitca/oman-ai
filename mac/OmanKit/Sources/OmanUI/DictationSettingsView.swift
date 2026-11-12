import AppKit
import OmanCore
import SwiftUI

struct DictationSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsForm {
            Section {
                switch model.dictationPage {
                case .model: modelRows
                case .look: LookChoice(model: model)
                case .words: wordsRows
                case .transcripts: transcriptRows
                }
            } header: {
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
            extraSections
        }
        .onAppear { model.reloadDictation() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadDictation()
        }
    }

    // MARK: Model

    @ViewBuilder
    private var modelRows: some View {
        ForEach(DictationModel.allCases) { candidate in
            ModelRow(model: model, candidate: candidate)
        }
        if let error = model.dictationError {
            SettingsError(text: error)
        }
    }

    @ViewBuilder
    private var extraSections: some View {
        switch model.dictationPage {
        case .model:
            Section {
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
                if model.preferences.dictationModel == .apple, case .needsDownload = model.dictationStatus {
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
                    Text("Unload the model")
                    Text("A loaded model starts at once but takes memory. macOS looks after Apple's itself.")
                }
            } header: {
                Text("\(model.preferences.dictationModel.displayName)")
            } footer: {
                Text("Every model runs on this Mac, so what you say never leaves it.")
            }
        case .look:
            Section {
                Picker("Show the words", selection: model.preference(\.dictationPillPosition)) {
                    ForEach(DictationPillPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
            } footer: {
                Text("In OmanAI's panel, your words go straight into the field you're typing in.")
            }
        case .words:
            Section {
                Toggle(isOn: model.preference(\.removesFillerWords)) {
                    Text("Remove filler words")
                    Text("Takes out um, uh, er and the like.")
                }
            }
        case .transcripts:
            EmptyView()
        }
    }

    // MARK: Words

    @ViewBuilder
    private var wordsRows: some View {
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
    }

    // MARK: Transcripts

    @ViewBuilder
    private var transcriptRows: some View {
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
}

/// One model in the list: what it is, whether it is live, which of the person's languages it knows, how fast it
/// is and how big. A click chooses it, downloading it first if needed.
private struct ModelRow: View {
    let model: SettingsViewModel
    let candidate: DictationModel

    private var status: DictationModelStatus? { model.modelStatuses[candidate] }
    private var isChosen: Bool { model.preferences.dictationModel == candidate }
    private var isDownloading: Bool { model.downloadingModel == candidate }
    private var isReady: Bool { status == .ready || (candidate == .apple && status != nil && !isUnavailable) }
    private var isUnavailable: Bool {
        if case .unavailable = status { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isChosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(candidate.displayName).fontWeight(.medium)
                    if candidate.isLive {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                            .help("Words appear while you speak")
                    }
                }
                Text(candidate.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                facts
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDownloading, !isUnavailable else { return }
            model.chooseModel(candidate)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? [.isSelected, .isButton] : .isButton)
    }

    /// The person's languages, ticked where the model knows them, then its speed and size.
    private var facts: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(model.personLanguages, id: \.self) { code in
                    let knows = model.modelLanguageCodes[candidate]?.contains(code) ?? false
                    Text(code.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .foregroundStyle(knows ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .background(knows ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .overlay {
                            if !knows {
                                RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary, lineWidth: 0.5)
                            }
                        }
                        .help(knows ? "Knows \(Locale.current.localizedString(forLanguageCode: code) ?? code)"
                            : "Doesn't know \(Locale.current.localizedString(forLanguageCode: code) ?? code)")
                }
            }
            SpeedBars(level: candidate.speed)
                .help("Speed: \(candidate.speed) of 4")
            if let size = candidate.downloadSize {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Built in").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isDownloading, let progress = model.downloadProgress {
            HStack(spacing: 6) {
                ProgressView(value: progress).frame(width: 90)
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
            Text("Not available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(reason)
        } else if case .needsDownload = status, candidate.isDownloaded {
            Button("Download") { model.downloadModel(candidate) }
                .disabled(model.downloadingModel != nil)
        } else if candidate.isDownloaded, status == .ready {
            Button {
                confirmRemove()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete the download")
            .accessibilityLabel("Delete the download")
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

/// Four bars, filled up to `level`, as a signal strength shows.
private struct SpeedBars: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= level ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                    .frame(width: 3, height: CGFloat(3 + bar * 2))
            }
        }
        .accessibilityHidden(true)
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

/// Lays its children out in rows, starting a new row when the next one would not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                let next = Row(indices: [], y: row.y + row.height + spacing)
                rows.append(next)
                row = next
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
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
