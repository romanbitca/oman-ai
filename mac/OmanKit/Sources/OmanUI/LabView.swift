import AppKit
import Charts
import OmanCore
import SwiftUI

/// The Lab's window: a plain macOS window, opened from the menu bar icon's menu or by opening OmanAI again.
public enum LabWindow {
    public static func make(model: LabViewModel) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: LabView(model: model)))
        window.title = "OmanAI Lab"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 780))
        window.contentMinSize = NSSize(width: 640, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// What OmanAI did for the person, how their writing goes, and their transcripts.
struct LabView: View {
    @Bindable var model: LabViewModel

    private var summary: LabSummary { model.summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                tiles
                LabCard(title: "The last two weeks", note: "Dictations and fixes put back, day by day.") {
                    activity
                }
                LabCard(
                    title: "Your writing",
                    note: "How many places a proofread changed, on average, week by week. Fewer is better."
                ) {
                    writing
                }
                transcripts
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your OmanAI").font(.largeTitle.weight(.bold))
            Text("Counted on this Mac from what OmanAI keeps, never from the words of your texts.")
                .foregroundStyle(.secondary)
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
            LabTile(
                symbol: "waveform", tint: .teal, value: summary.dictations.formatted(), title: "Dictations",
                detail: "\(summary.wordsDictated.formatted()) words · \(LabFormat.spoken(summary.secondsDictated))"
            )
            LabTile(
                symbol: "checkmark.circle.fill", tint: .green, value: summary.fixes.formatted(), title: "Fixes put back",
                detail: SpendingFormat.ofTextsWritten(summary.written)
            )
            LabTile(
                symbol: "text.badge.checkmark", tint: .purple,
                value: summary.changesThisWeek.map(LabFormat.changes) ?? "–",
                title: "Changes per proofread",
                detail: LabFormat.trend(thisWeek: summary.changesThisWeek, lastWeek: summary.changesLastWeek)
                    ?? (summary.proofreads == 0 ? "Proofread a message to start" : "This week")
            )
            LabTile(
                symbol: "dollarsign.circle.fill", tint: .blue, value: SpendingFormat.amount(summary.spentThisMonth),
                title: "Spent this month", detail: "\(SpendingFormat.amount(summary.spentInAll)) in all"
            )
        }
    }

    @ViewBuilder
    private var activity: some View {
        if summary.days.allSatisfy({ $0.dictations == 0 && $0.fixes == 0 }) {
            LabEmpty(symbol: "chart.bar", text: "Nothing in the last two weeks yet.")
        } else {
            Chart(summary.days) { day in
                BarMark(x: .value("Day", day.start, unit: .day), y: .value("Count", day.dictations))
                    .foregroundStyle(by: .value("What", "Dictations"))
                    .position(by: .value("What", "Dictations"))
                    .cornerRadius(2)
                BarMark(x: .value("Day", day.start, unit: .day), y: .value("Count", day.fixes))
                    .foregroundStyle(by: .value("What", "Fixes put back"))
                    .position(by: .value("What", "Fixes put back"))
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale(["Dictations": Color.teal, "Fixes put back": Color.green])
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 170)
        }
    }

    @ViewBuilder
    private var writing: some View {
        if summary.proofreads == 0 {
            LabEmpty(
                symbol: "text.badge.checkmark",
                text: "Proofread a few messages, and this shows how many places each one needed to change."
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    if let share = summary.cleanShare {
                        LabFigure(
                            value: share.formatted(.percent.precision(.fractionLength(0))),
                            caption: "of your proofreads found nothing to change"
                        )
                    }
                    LabFigure(value: summary.proofreads.formatted(), caption: "proofreads counted")
                }
                Chart(summary.weeks.filter { $0.changesPerProofread != nil }) { week in
                    LineMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Changes", week.changesPerProofread ?? 0))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.purple)
                    PointMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Changes", week.changesPerProofread ?? 0))
                        .foregroundStyle(Color.purple)
                        .annotation(position: .top) {
                            Text(LabFormat.changes(week.changesPerProofread ?? 0)).font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartYScale(domain: 0...max((summary.weeks.compactMap(\.changesPerProofread).max() ?? 1) * 1.25, 1))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private var transcripts: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Transcripts").font(.title3.weight(.semibold))
                Spacer()
                TextField("Search", text: $model.search, prompt: Text("Search"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Picker("Keep", selection: Binding(
                    get: { model.history },
                    set: { history in if confirmKeeping(history) { model.setHistory(history) } }
                )) {
                    ForEach(DictationHistory.allCases) { history in
                        Text(history.displayName).tag(history)
                    }
                }
                .fixedSize()
                .help("How many transcripts to keep. Only the text is kept, on this Mac; the sound never is.")
            }
            VStack(spacing: 0) {
                if model.shownTranscripts.isEmpty {
                    LabEmpty(
                        symbol: "text.quote",
                        text: model.transcripts.isEmpty
                            ? (model.history == .off ? "Transcripts aren't kept. Choose how many to keep." : "No transcripts yet.")
                            : "No transcript has those words."
                    )
                    .padding(16)
                } else {
                    ForEach(Array(model.shownTranscripts.enumerated()), id: \.element.id) { index, dictation in
                        if index > 0 { Divider().padding(.leading, 16) }
                        TranscriptRow(dictation: dictation, isCopied: model.copiedID == dictation.id) {
                            model.copy(dictation)
                        } delete: {
                            model.delete(id: dictation.id)
                        }
                    }
                }
            }
            .background(LabCardBackground())
            if !model.transcripts.isEmpty {
                HStack {
                    Text("\(model.transcripts.count.formatted()) kept").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete All Transcripts…", role: .destructive) { confirmDeleteAll() }
                }
            }
        }
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
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            model.deleteAll()
        }
    }
}

/// One number on the Lab's first row, with what it counts.
private struct LabTile: View {
    let symbol: String
    let tint: Color
    let value: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.gradient))
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                // Every note gets the room of two real lines, so one that wraps doesn't make its tile taller than the
                // rest. Reserving the lines with lineLimit left the wrapped tile a point taller.
                ZStack(alignment: .topLeading) {
                    Text(" \n ").hidden().accessibilityHidden(true)
                    Text(detail).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(LabCardBackground())
        .accessibilityElement(children: .combine)
    }
}

private struct LabCard<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LabCardBackground())
    }
}

private struct LabCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

private struct LabFigure: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LabEmpty: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranscriptRow: View {
    let dictation: SavedDictation
    let isCopied: Bool
    let copy: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dictation.text)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dictation.labDetail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: copy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
            .accessibilityLabel("Copy")
            Button(action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete")
            .accessibilityLabel("Delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

extension SavedDictation {
    /// When it was said, where it went and how long it took, under the words in the Lab.
    var labDetail: String {
        var parts = [date.formatted(date: .abbreviated, time: .shortened)]
        if let appName { parts.append(appName) }
        let seconds = Int(duration.rounded())
        parts.append(seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s")
        return parts.joined(separator: " · ")
    }
}
