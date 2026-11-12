import OmanCore
import SwiftUI

/// The app's wave, the stroke of its menu bar icon, with its height following the voice.
public struct DictationWave: Shape {
    /// Near 0 the line is almost flat. At 1 it is the icon's own wave.
    public var amplitude: CGFloat

    public init(amplitude: CGFloat) {
        self.amplitude = amplitude
    }

    public var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        Path(Self.cgPath(in: rect, amplitude: amplitude))
    }

    /// The stroke from MenuBarIcon.svg, drawn on an 18-point square with y growing downwards, centred in `rect`.
    public static func cgPath(in rect: CGRect, amplitude: CGFloat) -> CGPath {
        let scale = min(rect.width, rect.height) / 18
        let originX = rect.midX - 9 * scale
        let originY = rect.midY - 9 * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + (9 + (y - 9) * amplitude) * scale)
        }
        let path = CGMutablePath()
        path.move(to: point(2.2, 11.4))
        path.addCurve(to: point(9, 9), control1: point(4.4, 2.4), control2: point(7, 3.2))
        path.addCurve(to: point(15.8, 6.6), control1: point(11, 14.8), control2: point(13.6, 15.6))
        return path
    }

    /// How tall the wave is for a microphone level, so even silence shows a little movement.
    public static func amplitude(forLevel level: Float) -> CGFloat {
        0.18 + 0.82 * CGFloat(min(max(level, 0), 1))
    }
}

/// Whether the pill shows, set by the window that holds it so the pill can fade before the window goes.
@MainActor
@Observable
public final class DictationPillState {
    public var isShown = false
    public var position: DictationPillPosition = .menuBar

    public init() {}
}

public enum DictationPillMetrics {
    public static let width: CGFloat = PanelMetrics.width
    public static let sideMargin: CGFloat = 24
    static let maxHeight: CGFloat = 156
    /// The window keeps one size; the pill sits at its top or bottom edge.
    public static let windowSize = CGSize(width: width + sideMargin * 2, height: PanelMetrics.menuBarGap + maxHeight)
    /// Room above the Dock when the pill sits at the bottom of the screen.
    public static let bottomGap: CGFloat = 16
    /// The most characters of live words shown. Earlier words give way to the newest.
    static let visibleCharacters = 150
    static let control: CGFloat = 34
    static let gap: CGFloat = 8
}

public struct DictationPillView: View {
    private let controller: DictationController
    private let state: DictationPillState

    public init(controller: DictationController, state: DictationPillState) {
        self.controller = controller
        self.state = state
    }

    private var atTop: Bool { state.position == .menuBar }

    public var body: some View {
        VStack(spacing: 0) {
            if !atTop { Spacer(minLength: 0) }
            if state.isShown {
                pill.transition(.opacity.combined(with: .offset(y: atTop ? -6 : 6)))
            }
            if atTop { Spacer(minLength: 0) }
        }
        .padding(.top, atTop ? PanelMetrics.menuBarGap : 0)
        .padding(.horizontal, DictationPillMetrics.sideMargin)
        .frame(width: DictationPillMetrics.windowSize.width, height: DictationPillMetrics.windowSize.height)
        .animation(.easeOut(duration: 0.16), value: state.isShown)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var pill: some View {
        Group {
            switch controller.pillStyle {
            case .card: card
            case .floating: floating
            }
        }
        .frame(width: DictationPillMetrics.width)
        .animation(.easeOut(duration: 0.16), value: controller.phase)
        .animation(.easeOut(duration: 0.16), value: controller.notice)
    }

    // MARK: Card: the wave, the seconds and Done on top, the words below in a glass card

    private var card: some View {
        VStack(spacing: DictationPillMetrics.gap) {
            HStack(spacing: DictationPillMetrics.gap) {
                waveCircle
                if showsSeconds {
                    seconds
                        .padding(.horizontal, 12)
                        .frame(height: DictationPillMetrics.control)
                        .liquidGlass(in: Capsule())
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if showsDone {
                    doneButton.transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            words(alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: DictationPillMetrics.width, alignment: .leading)
                .frame(minHeight: 40)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), reading: true)
        }
    }

    private var waveCircle: some View {
        leadingSymbol
            .frame(width: DictationPillMetrics.control, height: DictationPillMetrics.control)
            .liquidGlass(in: Circle())
    }

    // MARK: Floating: the words on a soft blur with no box, the wave, the seconds and Done below

    private var floating: some View {
        VStack(spacing: 6) {
            words(alignment: .center)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .frame(width: DictationPillMetrics.width)
                .background {
                    SoftBlur(points: 14, dim: 0.34)
                        .padding(.horizontal, -12)
                        .padding(.vertical, -4)
                }
            HStack(spacing: DictationPillMetrics.gap) {
                HStack(spacing: 8) {
                    leadingSymbol
                    if showsSeconds { seconds }
                }
                .padding(.horizontal, 12)
                .frame(height: DictationPillMetrics.control)
                .liquidGlass(in: Capsule())
                if showsDone {
                    doneButton.transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
    }

    // MARK: Pieces

    private var showsNotice: Bool { controller.notice != nil && controller.phase == .idle }
    private var showsSeconds: Bool { controller.listeningSince != nil && !showsNotice }
    private var showsDone: Bool { controller.mode == .long && controller.phase == .listening }

    @ViewBuilder
    private var leadingSymbol: some View {
        if showsNotice {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
                .frame(width: 20, height: 20)
        } else {
            DictationWave(amplitude: controller.phase == .listening
                ? DictationWave.amplitude(forLevel: controller.level) : 0.12)
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .frame(width: 20, height: 20)
                .opacity(controller.phase == .listening ? 1 : 0.55)
                .animation(.easeOut(duration: 0.1), value: controller.level)
        }
    }

    /// How long the microphone has been listening, as minutes and seconds.
    private var seconds: some View {
        TimelineView(.periodic(from: controller.listeningSince ?? .now, by: 1)) { context in
            Text(Self.elapsed(from: controller.listeningSince, to: context.date))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Time listening")
    }

    static func elapsed(from start: Date?, to now: Date) -> String {
        guard let start else { return "0:00" }
        let total = max(Int(now.timeIntervalSince(start)), 0)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private var doneButton: some View {
        Button {
            controller.finishNow()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: DictationPillMetrics.control, height: DictationPillMetrics.control)
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .liquidGlass(in: Circle(), interactive: true)
        .help("Put the words in")
        .accessibilityLabel("Done")
    }

    @ViewBuilder
    private func words(alignment: TextAlignment) -> some View {
        Group {
            if let notice = controller.notice, showsNotice {
                Text(notice)
                    .lineLimit(4)
            } else if controller.transcript.isEmpty {
                Text(controller.phase == .finishing ? "Finishing…" : "Listening…")
                    .foregroundStyle(.secondary)
            } else {
                let parts = PillWords(controller.transcript, limit: DictationPillMetrics.visibleCharacters)
                (Text(parts.settled) + Text(parts.tentative).foregroundStyle(.secondary))
                    .lineSpacing(2)
                    .lineLimit(3)
                    .accessibilityLabel(controller.transcript.text)
            }
        }
        .font(.system(size: 13))
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The end of the live words, as much as fits, split into the settled words and the model's current guess.
struct PillWords: Equatable {
    let settled: String
    let tentative: String

    init(_ transcript: LiveTranscript, limit: Int) {
        let confirmed = transcript.confirmed.trimmingCharacters(in: .whitespacesAndNewlines)
        let guess = transcript.tentative.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = LiveTranscript.join(confirmed, guess)
        guard joined.count > limit else {
            settled = confirmed
            tentative = confirmed.isEmpty || guess.isEmpty ? guess : " " + guess
            return
        }
        // Cut at a space, so the first word shown is whole.
        var start = joined.index(joined.endIndex, offsetBy: -limit)
        if let space = joined[start...].firstIndex(of: " ") {
            start = joined.index(after: space)
        }
        let shown = String(joined[start...])
        let guessLength = guess.isEmpty ? 0 : min(guess.count + 1, shown.count)
        let settledPart = String(shown.dropLast(guessLength))
        settled = "…" + settledPart
        tentative = String(shown.suffix(guessLength))
    }
}

/// The microphone beside a field in the panel. While a dictation fills that field, it shows the moving wave and
/// finishes the dictation when clicked.
struct DictationMicButton: View {
    let controller: DictationController
    let field: PanelField

    private var isDictatingHere: Bool { controller.isActive && controller.field == field }

    var body: some View {
        Button {
            controller.toggle(into: field)
        } label: {
            ZStack {
                if isDictatingHere {
                    DictationWave(amplitude: controller.phase == .listening
                        ? DictationWave.amplitude(forLevel: controller.level) : 0.12)
                        .stroke(Liquid.accent, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 18, height: 18)
                        .animation(.easeOut(duration: 0.1), value: controller.level)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(controller.isActive && !isDictatingHere)
        .help(isDictatingHere ? "Stop dictating" : "Dictate")
        .accessibilityLabel(isDictatingHere ? "Stop dictating" : "Dictate")
    }
}
