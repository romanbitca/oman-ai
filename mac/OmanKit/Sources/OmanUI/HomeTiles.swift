#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import OmanCore
import SwiftUI

/// A few choices in one capsule, the chosen one lifted: the stretch of time, and what the year map counts.
struct HomeChips<Value: Hashable & Identifiable>: View {
    let values: [Value]
    @Binding var selection: Value
    var isSmall = false
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values) { value in
                let isOn = value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = value }
                } label: {
                    Text(title(value))
                        .font(.system(size: isSmall ? 12 : 13, weight: .medium))
                        .foregroundStyle(isOn ? HomePalette.ink : HomePalette.dim)
                        .padding(.horizontal, isSmall ? 10 : 12)
                        .padding(.vertical, isSmall ? 3 : 5)
                        .background {
                            if isOn {
                                Capsule().fill(HomePalette.chipOn).shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(HomePalette.chip))
    }
}

// MARK: The first tile

/// The stretch's line: a smooth curve through what each step held, lit from below, with a mark on now. Moving the
/// pointer along it says what each step held.
struct HomeVoice: View {
    let values: [Int]
    let nowIndex: Int?
    let labels: [(step: Int, text: String, isNow: Bool)]
    /// What a step says while the pointer is on it: when it was, and what it held.
    let tip: (Int) -> (when: String, what: String)
    @State private var hovered: Int?

    static let lineHeight: CGFloat = 78
    static let height: CGFloat = 112
    private static let top: CGFloat = 13
    private static let base: CGFloat = 58
    /// Between the mark under the pointer and its note, and between the note and the tile's edge.
    private static let tipGap: CGFloat = 16
    private static let tipEdge: CGFloat = 8

    /// `pointingAt` starts with the pointer on a step, for drawing the line with its note showing.
    init(
        values: [Int], nowIndex: Int?, labels: [(step: Int, text: String, isNow: Bool)], pointingAt: Int? = nil,
        tip: @escaping (Int) -> (when: String, what: String)
    ) {
        self.values = values
        self.nowIndex = nowIndex
        self.labels = labels
        self.tip = tip
        _hovered = State(initialValue: pointingAt)
    }

    private func points(in width: CGFloat) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let peak = CGFloat(max(values.max() ?? 0, 1))
        let step = width / CGFloat(values.count)
        return values.enumerated().map { index, value in
            CGPoint(x: step * (CGFloat(index) + 0.5), y: Self.base - (Self.base - Self.top) * CGFloat(value) / peak)
        }
    }

    private func curve(_ points: [CGPoint], width: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        let all = [CGPoint(x: 0, y: first.y)] + points + [CGPoint(x: width, y: last.y)]
        path.move(to: all[0])
        for (from, to) in zip(all, all.dropFirst()) {
            let middle = (from.x + to.x) / 2
            path.addCurve(to: to, control1: CGPoint(x: middle, y: from.y), control2: CGPoint(x: middle, y: to.y))
        }
        return path
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let points = points(in: width)
            let line = curve(points, width: width)
            ZStack(alignment: .topLeading) {
                Group {
                    Path { path in
                        path.addPath(line)
                        path.addLine(to: CGPoint(x: width, y: Self.lineHeight))
                        path.addLine(to: CGPoint(x: 0, y: Self.lineHeight))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(height: Self.lineHeight, alignment: .top)

                    line.stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round)).blur(radius: 5)
                    line.stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        if index == nowIndex {
                            Circle().fill(.white.opacity(0.22)).frame(width: 22, height: 22).position(point)
                            Circle().fill(.white).frame(width: 11, height: 11).position(point)
                        } else if points.count <= 8 {
                            Circle().fill(.white.opacity(values[index] > 0 ? 0.75 : 0.4)).frame(width: 6, height: 6).position(point)
                        }
                    }

                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                        let x = width / CGFloat(max(values.count, 1)) * (CGFloat(label.step) + 0.5)
                        Group {
                            if label.isNow {
                                Text(label.text)
                                    .foregroundStyle(Color(hex: 0x0C7F8E))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.white).shadow(color: Color(hex: 0x083A5E).opacity(0.25), radius: 4, y: 2))
                            } else {
                                Text(label.text).foregroundStyle(.white.opacity(0.62))
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize()
                        // Kept inside the tile at its two ends.
                        .position(x: min(max(x, label.text.count > 4 ? 52 : 38), width - (label.text.count > 4 ? 52 : 38)), y: Self.height - 18)
                    }
                }
                .accessibilityHidden(true)

                if let hovered, points.indices.contains(hovered) {
                    let point = points[hovered]
                    // A thin line down from the step under the pointer, a mark on it, and what it held beside it.
                    Path { path in
                        path.move(to: point)
                        path.addLine(to: CGPoint(x: point.x, y: Self.lineHeight))
                    }
                    .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    Circle().fill(.white.opacity(0.25)).frame(width: 22, height: 22).position(point)
                    Circle().fill(.white).frame(width: 11, height: 11).position(point)
                    let said = tip(hovered)
                    HomeTip(title: said.when, text: said.what)
                        // To the right of the mark where there is room, else to its left, and never past the tile.
                        .alignmentGuide(.leading) { size in
                            var left = point.x + Self.tipGap
                            if left + size.width > width - Self.tipEdge { left = point.x - Self.tipGap - size.width }
                            return -min(max(left, Self.tipEdge), max(width - Self.tipEdge - size.width, Self.tipEdge))
                        }
                        // Level with the mark, and never over the words above the line.
                        .alignmentGuide(.top) { size in -max(point.y - size.height / 2, 0) }
                        .allowsHitTesting(false)
                }

                // On top of everything, so the pointer is followed over the line, the marks and the labels alike.
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            guard !values.isEmpty, width > 0 else { return }
                            let step = width / CGFloat(values.count)
                            hovered = min(max(Int(location.x / step), 0), values.count - 1)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: Self.height)
    }
}

struct HomeHeroTile: View {
    let summary: HomeSummary
    let calendar: Calendar
    let dictationKeys: String?
    let proofreadKeys: String?
    /// A step to draw as if the pointer were on it.
    var pointingAt: Int?

    private var values: [Int] {
        summary.steps.map { summary.hero == .fixes ? $0.fixes : $0.words }
    }

    private var fixesDetail: String {
        let fixes = summary.fixes
        let parts = [
            fixes.proofread > 0 ? "\(fixes.proofread.formatted()) proofread" : nil,
            fixes.rewritten > 0 ? "\(fixes.rewritten.formatted()) rewritten" : nil,
            fixes.composed > 0 ? "\(fixes.composed.formatted()) composed" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "Nothing put back yet in this stretch" : parts.joined(separator: " · ")
    }

    private var welcome: String {
        let speak = dictationKeys.map { "Hold \($0) and talk" } ?? "Dictate from the menu bar"
        let fix = proofreadKeys.map { "select text and press \($0)" } ?? "select text and open OmanAI from the menu bar"
        return "\(speak), or \(fix). What you do is counted here."
    }

    private var title: String {
        switch summary.hero {
        case .words: "Words spoken"
        case .fixes: "Texts fixed"
        case .welcome: "Welcome"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        ZStack(alignment: .bottom) {
            HomePalette.heroFill
            words
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Above the words, so nothing lies between the pointer and the line.
            HomeVoice(
                values: values, nowIndex: summary.todayStep,
                labels: HomeFormat.lineLabels(summary, calendar: calendar),
                pointingAt: pointingAt
            ) { HomeFormat.lineStep(summary, at: $0, calendar: calendar) }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, minHeight: HomeMetrics.heroHeight, maxHeight: HomeMetrics.heroHeight)
        .clipShape(shape)
        .overlay { shape.strokeBorder(HomePalette.edge, lineWidth: 1) }
        .shadow(color: Color(hex: 0x143CA0).opacity(0.32), radius: 10, x: 0, y: 6)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                DictationWave(amplitude: 1)
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.top, 4)

            if summary.hero == .welcome {
                Text("Speak or fix your first text")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .padding(.top, 10)
                Text(welcome)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } else {
                Text((summary.hero == .fixes ? summary.fixes.total : summary.words).formatted())
                    .font(.system(size: 84, weight: .bold, design: .rounded))
                    .tracking(-3)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: 88)
                    .padding(.top, 2)
                Text(summary.hero == .fixes ? fixesDetail : HomeFormat.heroDetail(summary))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: The two small tiles

struct HomeStreakTile: View {
    let streak: HomeSummary.Streak
    let calendar: Calendar

    /// The first letters of the week's days, the calendar's first day first.
    private var letters: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: "", count: 7) }
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        HomeTile(height: HomeMetrics.smallHeight) {
            VStack(alignment: .leading, spacing: 0) {
                HomeLabel(symbol: "flame.fill", title: "Streak", color: HomePalette.orange)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HomeFigure(value: streak.days.formatted(), unit: HomeFormat.days(streak.days))
                    Spacer(minLength: 4)
                    Text(HomeFormat.streakNote(streak))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HomePalette.soft)
                        .lineLimit(1)
                }
                .padding(.top, 2)
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        let isOn = index < streak.week.count && streak.week[index]
                        VStack(spacing: 4) {
                            Circle()
                                .fill(isOn
                                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFB347), HomePalette.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(HomePalette.off))
                                .frame(width: 16, height: 16)
                                .shadow(color: isOn ? HomePalette.orange.opacity(0.45) : .clear, radius: 3, y: 2)
                            Text(letters[index])
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(index == streak.todayIndex ? HomePalette.ink : HomePalette.soft)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 7)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct HomeSpeedTile: View {
    let summary: HomeSummary
    let period: HomeSummary.Period

    var body: some View {
        HomeTile(height: HomeMetrics.smallHeight) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HomeLabel(symbol: "bolt.fill", title: "Speed", color: HomePalette.teal)
                    Spacer(minLength: 4)
                    if let times = summary.timesFasterThanTyping {
                        Text("\(HomeFormat.times(times)) typing")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(HomePalette.teal)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(HomePalette.copy.opacity(0.13)))
                            .help("Against typing at \(Int(HomeSummary.typingSpeed)) words a minute, the usual figure for an adult.")
                    }
                }
                if let speed = summary.speed {
                    HomeFigure(value: speed.formatted(), unit: "words a minute").padding(.top, 2)
                    let typing = HomeSummary.typingSpeed
                    let most = max(Double(speed), typing)
                    VStack(spacing: 5) {
                        bar("You", share: Double(speed) / most, fill: AnyShapeStyle(HomePalette.barFill))
                        bar("Typing", share: typing / most, fill: AnyShapeStyle(HomePalette.off))
                    }
                    .padding(.top, 7)
                } else {
                    HomeFigure(value: "–", unit: "words a minute").foregroundStyle(HomePalette.soft).padding(.top, 2)
                    Text(period == .week ? "Nothing dictated this week" : "Nothing dictated this month")
                        .font(.system(size: 12))
                        .foregroundStyle(HomePalette.soft)
                        .padding(.top, 8)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func bar(_ name: String, share: Double, fill: AnyShapeStyle) -> some View {
        HStack(spacing: 7) {
            Text(name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HomePalette.soft)
                .frame(width: 36, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(fill).frame(width: max(7, proxy.size.width * share))
            }
            .frame(height: 7)
        }
    }
}

/// For someone who has never dictated: how to start.
struct HomeDictateTipTile: View {
    let keys: String?

    var body: some View {
        HomeTile(height: HomeMetrics.smallHeight) {
            VStack(alignment: .leading, spacing: 0) {
                HomeLabel(symbol: "mic.fill", title: "Dictate", color: HomePalette.teal)
                Text(keys.map { "Hold \($0) and speak" } ?? "Choose a key to hold in Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Text("Your words are typed where the cursor is.")
                    .font(.system(size: 12))
                    .foregroundStyle(HomePalette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
        }
    }
}

// MARK: The second row

struct HomeTimeSavedTile: View {
    let summary: HomeSummary
    let isAccent: Bool

    var body: some View {
        let saved = HomeFormat.saved(minutes: summary.minutesSaved)
        HomeAccentTile(isAccent: isAccent) {
            HomeClockRings().frame(width: 128, height: 128).offset(x: 34, y: 40).opacity(isAccent ? 0.8 : 0)
        } content: { ink, note in
            VStack(alignment: .leading, spacing: 0) {
                HomeLabel(symbol: "clock", title: "Time saved", color: isAccent ? .white.opacity(0.92) : HomePalette.violet)
                HomeFigure(value: saved.value, unit: saved.unit, size: 50, unitColor: ink).foregroundStyle(ink).padding(.top, 4)
                Text(summary.words > 0 ? "against typing the same\n\(summary.words.formatted()) words" : "against typing the same words")
                    .font(.system(size: 12.5))
                    .foregroundStyle(note)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }
            .help("Typing is taken as \(Int(HomeSummary.typingSpeed)) words a minute, the usual figure for an adult.")
            .accessibilityElement(children: .combine)
        }
    }
}

/// A tile of the second row that is drawn in colour when it is the row's accent, and as a white card otherwise.
struct HomeAccentTile<Decoration: View, Content: View>: View {
    let isAccent: Bool
    @ViewBuilder var decoration: Decoration
    /// Given the colours for the figure and for the note under it.
    @ViewBuilder var content: (Color, Color) -> Content

    var body: some View {
        HomeTile(
            height: HomeMetrics.wideHeight,
            glow: isAccent ? Color(hex: 0xAA3CAA).opacity(0.32) : HomePalette.shadow
        ) {
            ZStack(alignment: .bottomTrailing) {
                if isAccent { HomePalette.accentFill } else { HomePalette.card }
                decoration
            }
        } content: {
            content(isAccent ? .white : HomePalette.ink, isAccent ? .white.opacity(0.88) : HomePalette.dim)
        }
    }
}

private struct HomeClockRings: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.16), lineWidth: 2)
            Circle().strokeBorder(.white.opacity(0.2), lineWidth: 2).padding(17)
            Path { path in
                path.move(to: CGPoint(x: 64, y: 32))
                path.addLine(to: CGPoint(x: 64, y: 64))
                path.addLine(to: CGPoint(x: 85, y: 77))
            }
            .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct HomeFixesTile: View {
    let fixes: HomeSummary.Fixes
    let period: HomeSummary.Period

    private var kinds: [(name: String, count: Int, color: Color)] {
        [
            ("proofread", fixes.proofread, Color(hex: 0x0AA37F)),
            ("rewritten", fixes.rewritten, HomePalette.mint),
            ("composed", fixes.composed, Color(hex: 0x9BE8D0)),
        ].filter { $0.count > 0 }
    }

    var body: some View {
        HomeTile(height: HomeMetrics.wideHeight) {
            VStack(alignment: .leading, spacing: 0) {
                HomeLabel(symbol: "checkmark", title: "Fixes", color: HomePalette.green)
                HomeFigure(value: fixes.total.formatted(), size: 50).padding(.top, 4)
                if kinds.isEmpty {
                    Text(period == .week ? "None put back this week" : "None put back in this stretch")
                        .font(.system(size: 12.5))
                        .foregroundStyle(HomePalette.dim)
                        .padding(.top, 8)
                } else {
                    GeometryReader { proxy in
                        let free = proxy.size.width - 3 * CGFloat(kinds.count - 1)
                        HStack(spacing: 3) {
                            ForEach(kinds, id: \.name) { kind in
                                Capsule().fill(kind.color)
                                    .frame(width: max(8, free * CGFloat(kind.count) / CGFloat(max(fixes.total, 1))))
                            }
                        }
                    }
                    .frame(height: 8)
                    .padding(.top, 6)
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 2) {
                        ForEach(kinds, id: \.name) { kind in
                            HStack(spacing: 5) {
                                Circle().fill(kind.color).frame(width: 7, height: 7)
                                Text("\(kind.count.formatted()) \(kind.name)").font(.system(size: 11.5)).foregroundStyle(HomePalette.dim).lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .help("Texts OmanAI wrote that you put back into an app with Replace or Insert.")
            .accessibilityElement(children: .combine)
        }
    }
}

struct HomeEnglishTile: View {
    let summary: HomeSummary
    let isAccent: Bool

    var body: some View {
        HomeAccentTile(isAccent: isAccent) {
            EmptyView()
        } content: { ink, note in
            VStack(alignment: .leading, spacing: 0) {
                HomeLabel(symbol: "sparkles", title: "Your English", color: isAccent ? .white.opacity(0.92) : HomePalette.violet)
                if let english = summary.english {
                    HStack(alignment: .center, spacing: 10) {
                        HomeFigure(value: HomeFormat.corrections(english.average), size: 50).foregroundStyle(ink)
                        HomeTrendLine(values: english.weeks.compactMap { $0 }, color: ink)
                            .frame(maxWidth: 104, maxHeight: 40)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.top, 4)
                    Text(["corrections per proofread", HomeFormat.trend(english, period: summary.period)].compactMap { $0 }.joined(separator: "\n"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(note)
                        .lineSpacing(2)
                        .padding(.top, 4)
                } else {
                    HomeFigure(value: "–", size: 50).foregroundStyle(ink.opacity(0.6)).padding(.top, 4)
                    Text(summary.period == .week ? "No proofread this week" : "No proofread this month")
                        .font(.system(size: 12.5))
                        .foregroundStyle(note)
                        .padding(.top, 4)
                }
            }
            .help("How many places a proofread changed, on average. Fewer is better. Only the number is kept, never the words.")
            .accessibilityElement(children: .combine)
        }
    }
}

/// A small line through a few values, with a mark on the last: how the corrections went week by week.
struct HomeTrendLine: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            if values.count >= 2, let low = values.min(), let high = values.max() {
                let inset: CGFloat = 11
                let width = proxy.size.width - inset * 2
                let height = proxy.size.height - inset * 2
                let range = max(high - low, 0.0001)
                let points = values.enumerated().map { index, value in
                    CGPoint(
                        x: inset + width * CGFloat(index) / CGFloat(values.count - 1),
                        y: inset + height * (high == low ? 0.5 : CGFloat((high - value) / range))
                    )
                }
                ZStack {
                    Path { path in
                        path.move(to: points[0])
                        for (from, to) in zip(points, points.dropFirst()) {
                            let middle = (from.x + to.x) / 2
                            path.addCurve(to: to, control1: CGPoint(x: middle, y: from.y), control2: CGPoint(x: middle, y: to.y))
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    if let last = points.last {
                        Circle().fill(color.opacity(0.25)).frame(width: 20, height: 20).position(last)
                        Circle().fill(color).frame(width: 9, height: 9).position(last)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct HomeAppIcon: View {
    let url: URL?
    let name: String
    var size: CGFloat = 22

    var body: some View {
        if let url, let icon = Platform.appIcon(at: url) {
            Image(platformImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(HomePalette.off)
                .frame(width: size, height: size)
                .overlay {
                    Text(name.prefix(1).uppercased())
                        .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                        .foregroundStyle(HomePalette.dim)
                }
                .accessibilityHidden(true)
        }
    }
}

struct HomeAppsTile: View {
    let summary: HomeSummary
    let url: (String) -> URL?

    var body: some View {
        HomeTile(height: HomeMetrics.wideHeight) {
            VStack(alignment: .leading, spacing: 0) {
                HomeLabel(title: summary.hero == .fixes ? "Where you fix" : "Where you dictate")
                if summary.apps.isEmpty {
                    Text(summary.period == .week ? "Nothing this week yet" : "Nothing in this stretch yet")
                        .font(.system(size: 12.5))
                        .foregroundStyle(HomePalette.dim)
                        .padding(.top, 10)
                } else {
                    let most = CGFloat(summary.apps.first?.count ?? 1)
                    VStack(spacing: 10) {
                        ForEach(summary.apps.prefix(3)) { app in
                            HStack(spacing: 8) {
                                HomeAppIcon(url: url(app.name), name: app.name)
                                Text(app.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .frame(width: 74, alignment: .leading)
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(HomePalette.track)
                                        Capsule().fill(HomePalette.barFill).frame(width: max(6, proxy.size.width * CGFloat(app.count) / most))
                                    }
                                }
                                .frame(height: 6)
                                Text(app.count.formatted())
                                    .font(.system(size: 13, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(HomePalette.dim)
                                    .frame(minWidth: 18, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Until a proofread has been counted with its corrections: what the tile will show, and how to start. Alone in
/// its row it lies flat, the words beside the hint.
struct HomeEnglishInviteTile: View {
    let keys: String?
    var isAlone = false

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeLabel(symbol: "sparkles", title: "Your English", color: HomePalette.violet)
            Text("Proofread a message and see how many corrections it needed, week by week.")
                .font(.system(size: 12.5))
                .foregroundStyle(HomePalette.dim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private var hint: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            Text(keys.map { "Select text, press \($0)" } ?? "Proofread a text")
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0x5B4CF5), Color(hex: 0x8A5CF6)], startPoint: .leading, endPoint: .trailing))
                .shadow(color: Color(hex: 0x5B4CF5).opacity(0.5), radius: 5, y: 3)
        )
        .fixedSize()
    }

    var body: some View {
        HomeTile(height: isAlone ? 84 : HomeMetrics.wideHeight) {
            ZStack {
                HomePalette.card
                LinearGradient(
                    stops: [.init(color: HomePalette.violet.opacity(0.11), location: 0), .init(color: HomePalette.violet.opacity(0), location: 0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        } content: {
            Group {
                if isAlone {
                    HStack(alignment: .center, spacing: 16) {
                        words
                        Spacer(minLength: 0)
                        hint
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        words
                        hint
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
