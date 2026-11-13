import AppKit
import OmanCore
import SwiftUI

/// Everything dictated and kept, day by day, each a click away from the clipboard.
struct HomeTranscripts: View {
    @Bindable var model: HomeViewModel
    @State private var hovered: UUID?

    static let timeFontSize: CGFloat = 13
    @MainActor private static var timeWidths: [String: CGFloat] = [:]

    /// Wide enough for the longest time the clock writes in `locale`, such as "12:58 PM" where it has twelve hours,
    /// and never narrower than the 44 points a 24-hour clock needs.
    static func timeWidth(locale: Locale) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: timeFontSize, weight: .regular)
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: .gmt)
        // Each hour of a day at :58 takes in the widest hours and both halves of a 12-hour clock.
        let widest = (0..<24).map { hour in
            let time = Date(timeIntervalSinceReferenceDate: Double(hour * 3600 + 58 * 60)).formatted(style)
            return NSAttributedString(string: time, attributes: [.font: font]).size().width
        }.max() ?? 0
        return max(44, (widest + 2).rounded(.up))
    }

    /// `timeWidth(locale:)` for this Mac's clock, worked out once for each region and hour cycle.
    @MainActor static func currentTimeWidth() -> CGFloat {
        let locale = Locale.current
        let key = "\(locale.identifier) \(locale.hourCycle)"
        if let width = timeWidths[key] { return width }
        let width = timeWidth(locale: locale)
        timeWidths[key] = width
        return width
    }

    /// `pointingAt` starts with the pointer on a transcript, for drawing the list with its Copy button showing.
    init(model: HomeViewModel, pointingAt: UUID? = nil) {
        self.model = model
        _hovered = State(initialValue: pointingAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Transcripts").font(.system(size: 19, weight: .bold))
                Spacer(minLength: 8)
                HomeSearchField(text: $model.search)
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
                let timeWidth = Self.currentTimeWidth()
                ForEach(Array(day.items.enumerated()), id: \.element.id) { index, dictation in
                    let isHovered = hovered == dictation.id
                    // The line between two rows goes while either is under the pointer, so the highlight stands alone.
                    let above = index > 0 ? day.items[index - 1].id : nil
                    HomeTranscriptRow(
                        dictation: dictation,
                        timeWidth: timeWidth,
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
    let timeWidth: CGFloat
    let appURL: URL?
    let isHovered: Bool
    let isCopied: Bool
    let isExpanded: Bool
    let showsLine: Bool
    let copy: () -> Void
    let toggle: () -> Void
    let delete: () -> Void

    private static let verticalPadding: CGFloat = 11
    private static let cornerWidth: CGFloat = 84
    private static let copyHeight: CGFloat = 26
    private static let iconSize: CGFloat = 20
    /// Half the height of a line of the words, at 14 points.
    private static let firstLineMiddle: CGFloat = 9

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
                .font(.system(size: HomeTranscripts.timeFontSize))
                .monospacedDigit()
                .foregroundStyle(HomePalette.soft)
                .frame(width: timeWidth, alignment: .leading)
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
            // Room for Copy or the app's icon, which lie over this corner of the row. Laid out here, the taller
            // Copy button made a row of one line taller under the pointer, and every row below it jumped.
            Color.clear.frame(width: Self.cornerWidth, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Self.verticalPadding)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isHovered ? HomePalette.hover : .clear)
        }
        .overlay(alignment: .topTrailing) {
            Group {
                if isHovered || isCopied {
                    Button(action: copy) {
                        HStack(spacing: 5) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc").font(.system(size: 10.5, weight: .bold))
                            Text(isCopied ? "Copied" : "Copy").font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: Self.copyHeight)
                        .background(Capsule().fill(HomePalette.copy).shadow(color: HomePalette.copy.opacity(0.5), radius: 5, y: 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy")
                    // Centred on the first line of the words.
                    .padding(.top, Self.verticalPadding + Self.firstLineMiddle - Self.copyHeight / 2)
                } else {
                    HomeAppIcon(url: appURL, name: dictation.appName ?? "", size: Self.iconSize)
                        .opacity(dictation.appName == nil ? 0 : 1)
                        .padding(.top, Self.verticalPadding + Self.firstLineMiddle - Self.iconSize / 2)
                }
            }
            .padding(.trailing, 14)
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

/// The search field over the transcripts: a capsule in the page's own look.
struct HomeSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    private static let height: CGFloat = 28
    /// With plain round ends. A capsule's usual continuous corners, stroked, drew a short stray line at each end.
    private var shape: Capsule { Capsule(style: .circular) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HomePalette.soft)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .focusEffectDisabled()
                .onExitCommand {
                    text = ""
                    isFocused = false
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(HomePalette.soft)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 200, height: Self.height)
        .background(shape.fill(HomePalette.card))
        .overlay {
            shape.strokeBorder(isFocused ? HomePalette.copy : HomePalette.edge, lineWidth: isFocused ? 1.5 : 1)
        }
        .contentShape(shape)
        .onTapGesture { isFocused = true }
        .animation(.easeOut(duration: 0.14), value: isFocused)
        .help("Search your transcripts, by their words or the app they went into")
    }
}
