import AppKit
import OmanCore
import SwiftUI

/// Everything dictated and kept, day by day, each a click away from the clipboard.
struct HomeTranscripts: View {
    @Bindable var model: HomeViewModel
    @State private var hovered: UUID?

    /// `pointingAt` starts with the pointer on a transcript, for drawing the list with its Copy button showing.
    init(model: HomeViewModel, pointingAt: UUID? = nil) {
        self.model = model
        _hovered = State(initialValue: pointingAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Transcripts").font(.system(size: 19, weight: .bold))
                Spacer(minLength: 8)
                keepMenu
            }
            sheet
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var sheet: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        let days = model.days
        return VStack(alignment: .leading, spacing: 0) {
            if days.isEmpty {
                Text(emptyText)
                    .foregroundStyle(HomePalette.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
            }
            ForEach(days) { day in
                Text(day.title.uppercased())
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(HomePalette.soft)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                ForEach(Array(day.items.enumerated()), id: \.element.id) { index, dictation in
                    let isHovered = hovered == dictation.id
                    // The line between two rows goes while either is under the pointer, so the highlight stands alone.
                    let above = index > 0 ? day.items[index - 1].id : nil
                    HomeTranscriptRow(
                        dictation: dictation,
                        appURL: model.appURL(named: dictation.appName),
                        isHovered: isHovered,
                        isCopied: model.copiedID == dictation.id,
                        isExpanded: model.expanded.contains(dictation.id),
                        showsLine: index > 0 && !isHovered && hovered != above,
                        copy: { model.copy(dictation) },
                        toggle: { model.toggleExpanded(dictation.id) },
                        delete: { model.delete(id: dictation.id) }
                    )
                    .onHover { inside in
                        if inside { hovered = dictation.id } else if hovered == dictation.id { hovered = nil }
                    }
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.card)
        .clipShape(shape)
        .overlay { shape.strokeBorder(HomePalette.edge, lineWidth: 1) }
        .shadow(color: HomePalette.shadow, radius: 12, x: 0, y: 8)
    }

    private var emptyText: String {
        if !model.transcripts.isEmpty { return "No transcript has those words." }
        return model.history == .off ? "Transcripts aren't kept. Choose how many to keep." : "No transcripts yet."
    }

    /// How many are kept, which is also where to choose how many to keep and to delete them all.
    private var keepMenu: some View {
        Menu {
            Picker("Keep", selection: Binding(
                get: { model.history },
                set: { history in if confirmKeeping(history) { model.setHistory(history) } }
            )) {
                ForEach(DictationHistory.allCases) { history in
                    Text(history.displayName).tag(history)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Delete All Transcripts…", role: .destructive) { confirmDeleteAll() }
                .disabled(model.transcripts.isEmpty)
        } label: {
            HStack(spacing: 4) {
                Text(keptText)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(HomePalette.dim)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(HomePalette.chip))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("How many transcripts to keep. Only the text is kept, on this Mac; the sound never is.")
    }

    private var keptText: String {
        let count = model.transcripts.count
        if count == 0 { return model.history == .off ? "None kept" : "Nothing kept yet" }
        return "\(count.formatted()) kept on this Mac"
    }

    /// Keeping fewer transcripts deletes the older ones, so it asks first.
    private func confirmKeeping(_ history: DictationHistory) -> Bool {
        let count = model.transcriptsDeleted(by: history)
        guard count > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = "Keep only \(history.displayName.lowercased())?"
        alert.informativeText = count == 1
            ? "The oldest transcript is deleted. This can't be undone."
            : "The \(count) oldest transcripts are deleted. This can't be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func confirmDeleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all transcripts?"
        alert.informativeText = "This can't be undone. The numbers above stay: they are counted without the words."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            model.deleteAll()
        }
    }
}

private struct HomeTranscriptRow: View {
    let dictation: SavedDictation
    let appURL: URL?
    let isHovered: Bool
    let isCopied: Bool
    let isExpanded: Bool
    let showsLine: Bool
    let copy: () -> Void
    let toggle: () -> Void
    let delete: () -> Void

    private var detail: String {
        var parts: [String] = []
        if let app = dictation.appName, !app.isEmpty { parts.append(app) }
        parts.append(HomeFormat.length(dictation.duration))
        let words = DictationCount.words(in: dictation.text)
        parts.append(words == 1 ? "1 word" : "\(words.formatted()) words")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(dictation.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(HomePalette.soft)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(dictation.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isExpanded {
                    Text(detail).font(.system(size: 12)).foregroundStyle(HomePalette.soft)
                }
            }
            // The same room whichever is shown, so the words don't move when the pointer comes.
            ZStack(alignment: .topTrailing) {
                if isHovered || isCopied {
                    Button(action: copy) {
                        HStack(spacing: 5) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc").font(.system(size: 10.5, weight: .bold))
                            Text(isCopied ? "Copied" : "Copy").font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(HomePalette.copy).shadow(color: HomePalette.copy.opacity(0.5), radius: 5, y: 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy")
                } else {
                    HomeAppIcon(url: appURL, name: dictation.appName ?? "", size: 20)
                        .opacity(dictation.appName == nil ? 0 : 1)
                        .padding(.top, 1)
                }
            }
            .frame(width: 84, alignment: .topTrailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isHovered ? HomePalette.hover : .clear)
        }
        .overlay(alignment: .top) {
            if showsLine {
                Rectangle().fill(HomePalette.line).frame(height: 1).padding(.horizontal, 14)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .contextMenu {
            Button("Copy", action: copy)
            Button(isExpanded ? "Show Less" : "Show All of It", action: toggle)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
        .help(dictation.appName.map { "Dictated into \($0). Click to see all of it." } ?? "Click to see all of it.")
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Copy", copy)
    }
}
