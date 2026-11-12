import Charts
import OmanCore
import SwiftUI

struct SpendingSettingsView: View {
    let model: SettingsViewModel
    @State private var period = SpendingSummary.Period.thisMonth

    private var summary: SpendingSummary.PeriodSummary { model.spending[period] }

    private var spentDetail: String {
        guard summary.requests > 0 else { return "spent · no Claude requests" }
        return [
            "spent",
            SpendingFormat.requests(summary.requests),
            "\(SpendingFormat.average(summary.averageCost)) each",
        ].joined(separator: " · ")
    }

    private var fixesDetail: String {
        summary.fixes == 1 ? "fix put back" : "fixes put back"
    }

    private var writtenDetail: String {
        guard summary.written > 0 else { return "Nothing written yet" }
        return "of \(summary.written.formatted()) texts written"
    }

    private var note: String {
        let counted = "A fix is a text OmanAI wrote that you put back into an app with Replace or Insert, with any "
            + "model. Fixes are counted from version 0.4.1 on. Money is estimated from the tokens Anthropic reports "
            + "for each Claude request, at list prices; Apple's on-device model is free. Only OmanAI on this Mac "
            + "is counted, and never the text itself."
        return model.spending.hasEntries ? counted : "Nothing yet. " + counted
    }

    var body: some View {
        SettingsForm {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(SpendingSummary.Period.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(alignment: .top, spacing: 32) {
                    SpendingFigure(
                        color: SpendingChart.spentColor,
                        value: SpendingFormat.amount(summary.cost),
                        detail: spentDetail,
                        secondary: summary.tokens > 0 ? SpendingFormat.tokens(summary.tokens) : nil
                    )
                    SpendingFigure(
                        color: SpendingChart.fixesColor,
                        value: summary.fixes.formatted(),
                        detail: fixesDetail,
                        secondary: writtenDetail
                    )
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)

                SpendingChart(bars: summary.bars, period: period)

                if let error = model.spendingError {
                    SettingsError(text: error)
                }
            } footer: {
                Text(note)
            }

            if !summary.kinds.isEmpty || summary.unsplitCost > 0 {
                Section("By action") {
                    ForEach(summary.kinds) { kind in
                        LabeledContent(kind.kind.displayName) {
                            HStack(spacing: 14) {
                                Text(Self.detail(of: kind)).foregroundStyle(.tertiary)
                                Text(SpendingFormat.amount(kind.cost))
                                    .monospacedDigit()
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                        }
                    }
                    if summary.unsplitCost > 0 {
                        LabeledContent {
                            Text(SpendingFormat.amount(summary.unsplitCost))
                                .monospacedDigit()
                                .frame(minWidth: 64, alignment: .trailing)
                        } label: {
                            Text("Earlier requests")
                            Text("From before OmanAI noted what each request was for.")
                        }
                    }
                }
            }

            if !summary.apps.isEmpty {
                Section("By app") {
                    ForEach(summary.apps.prefix(6)) { app in
                        LabeledContent(app.name) {
                            Text("\(SpendingFormat.fixes(app.fixes)) · \(SpendingFormat.written(app.written))")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if !summary.models.isEmpty {
                Section("By model") {
                    ForEach(summary.models) { share in
                        LabeledContent(share.name) {
                            HStack(spacing: 14) {
                                Text(SpendingFormat.requests(share.requests)).foregroundStyle(.tertiary)
                                Text(SpendingFormat.amount(share.cost))
                                    .monospacedDigit()
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { model.reloadSpending() }
    }

    /// "12 written · 9 put back", or for Explain, whose answers are never put back, only how many.
    static func detail(of kind: SpendingSummary.KindCount) -> String {
        guard kind.written > 0 else { return "" }
        guard kind.kind != .explain else { return SpendingFormat.written(kind.written) }
        return "\(SpendingFormat.written(kind.written)) · \(kind.fixes.formatted()) put back"
    }
}

/// One of the two figures over the chart, with the colour of its bars.
private struct SpendingFigure: View {
    let color: Color
    let value: String
    let detail: String
    let secondary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text(value)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
            }
            Text(detail).foregroundStyle(.secondary)
            if let secondary {
                Text(secondary).font(.callout).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A pair of bars for every hour, day or month: the fixes put back, and what Claude cost. Each has its own scale,
/// money on the left and fixes on the right. Pointing at a pair shows what is behind it.
struct SpendingChart: View {
    let bars: [SpendingSummary.Bar]
    let period: SpendingSummary.Period
    @State private var hovered: SpendingSummary.Bar?

    static let fixesColor = Color.teal
    static let spentColor = Color.accentColor
    private static let fixesSeries = "Fixes put back"
    private static let spentSeries = "Spent"

    private var labelFormat: Date.FormatStyle {
        switch period {
        case .today: .dateTime.hour()
        case .thisWeek: .dateTime.weekday(.abbreviated)
        case .thisMonth, .lastMonth: .dateTime.day().month(.abbreviated)
        case .allTime: bars.count > 12 ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.abbreviated)
        }
    }

    var body: some View {
        let countScale = SpendingSummary.countScale(for: bars.map(\.fixes).max() ?? 0)
        let costScale = SpendingSummary.costScale(for: bars.map(\.cost).max() ?? 0)
        Chart {
            if let hovered {
                RectangleMark(xStart: .value("Start", hovered.start), xEnd: .value("End", hovered.end))
                    .foregroundStyle(Color.primary.opacity(0.07))
            }
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Date", bar.start, unit: period.barUnit),
                    y: .value("Share", Double(bar.fixes) / Double(countScale))
                )
                .foregroundStyle(by: .value("Series", Self.fixesSeries))
                .position(by: .value("Series", Self.fixesSeries))
                .cornerRadius(2)
                .accessibilityLabel(SpendingFormat.title(of: bar, in: period))
                .accessibilityValue(SpendingFormat.fixes(bar.fixes))

                BarMark(
                    x: .value("Date", bar.start, unit: period.barUnit),
                    y: .value("Share", bar.cost / costScale)
                )
                .foregroundStyle(by: .value("Series", Self.spentSeries))
                .position(by: .value("Series", Self.spentSeries))
                .cornerRadius(2)
                .accessibilityLabel(SpendingFormat.title(of: bar, in: period))
                .accessibilityValue("\(SpendingFormat.precise(bar.cost)) spent")
            }
        }
        .chartForegroundStyleScale([Self.fixesSeries: Self.fixesColor, Self.spentSeries: Self.spentColor])
        // The two figures above the chart, each with its colour, say what the bars are.
        .chartLegend(.hidden)
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let share = value.as(Double.self) {
                        Text(SpendingFormat.axis(share * costScale)).foregroundStyle(Self.spentColor)
                    }
                }
            }
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisValueLabel {
                    if let share = value.as(Double.self) {
                        Text((share * Double(countScale)).rounded().formatted()).foregroundStyle(Self.fixesColor)
                    }
                }
            }
        }
        .chartXAxis {
            // Each label is centred under its own bar. Charts would otherwise start it at the bar, which runs the
            // last one off the chart, or centre it between marks, days away from its bar. The aligned preset also
            // moves a label at either end inwards far enough to stay on the chart.
            AxisMarks(preset: .aligned, values: SpendingSummary.labelledBars(bars, for: period).map(\.middle)) { _ in
                AxisValueLabel(format: labelFormat)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hovered = bar(at: location.x - plot.minX, within: plot.width, proxy: proxy)
                        case .ended:
                            hovered = nil
                        }
                    }
                if let hovered, let x = proxy.position(forX: hovered.middle) {
                    detailCard(for: hovered, atX: plot.minX + x, plot: plot, width: geometry.size.width)
                }
            }
        }
        .frame(height: 170)
        .padding(.vertical, 4)
    }

    private func bar(at x: CGFloat, within width: CGFloat, proxy: ChartProxy) -> SpendingSummary.Bar? {
        guard x >= 0, x <= width, let date = proxy.value(atX: x, as: Date.self) else { return nil }
        return bars.first { $0.start <= date && date < $0.end }
    }

    /// Beside the pair pointed at, on whichever side has more room, so the pointer never covers it.
    private func detailCard(
        for bar: SpendingSummary.Bar,
        atX x: CGFloat,
        plot: CGRect,
        width: CGFloat
    ) -> some View {
        let cardWidth: CGFloat = 250
        let gap: CGFloat = 16
        let leading = x > width / 2 ? x - gap - cardWidth : x + gap
        return SpendingBarDetail(bar: bar, period: period)
            .frame(width: cardWidth)
            .offset(x: min(max(leading, 0), max(width - cardWidth, 0)), y: plot.minY)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// What is behind one pair of bars: what was written and put back, and what it cost.
struct SpendingBarDetail: View {
    let bar: SpendingSummary.Bar
    let period: SpendingSummary.Period

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SpendingFormat.title(of: bar, in: period))
                .font(.headline)
            if bar.isEmpty {
                Text("Nothing written, nothing spent.").foregroundStyle(.secondary)
            } else {
                line(
                    color: SpendingChart.fixesColor,
                    title: SpendingFormat.fixes(bar.fixes),
                    detail: bar.written > 0 ? "of \(bar.written.formatted()) written" : nil
                )
                if !bar.kinds.isEmpty {
                    Text(SpendingFormat.kinds(bar.kinds)).font(.caption).foregroundStyle(.secondary)
                }
                line(
                    color: SpendingChart.spentColor,
                    title: "\(SpendingFormat.precise(bar.cost)) spent",
                    detail: bar.requests > 0 ? SpendingFormat.requests(bar.requests) : nil
                )
                if !bar.models.isEmpty {
                    Text(SpendingFormat.models(bar.models)).font(.caption).foregroundStyle(.secondary)
                    Text(SpendingFormat.tokens(bar.tokens)).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
    }

    private func line(color: Color, title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title).fontWeight(.medium).monospacedDigit()
            if let detail {
                Spacer(minLength: 8)
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
