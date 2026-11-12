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
    static let maxHeight: CGFloat = 120
    /// The window keeps one size; the pill sits at its top or bottom edge.
    public static let windowSize = CGSize(width: width + sideMargin * 2, height: PanelMetrics.menuBarGap + maxHeight)
    /// Room above the Dock when the pill sits at the bottom of the screen.
    public static let bottomGap: CGFloat = 16
    /// The most characters of live words shown. Earlier words give way to the newest.
    static let visibleCharacters = 150
}

public struct DictationPillView: View {
    private let controller: DictationController
    private let state: DictationPillState

    public init(controller: DictationController, state: DictationPillState) {
        self.controller = controller
        self.state = state
    }

    private var atTop: Bool { state.position == .menuBar }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

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

    private var pill: some View {
        HStack(alignment: .center, spacing: 11) {
            leading
            words
                .frame(maxWidth: .infinity, alignment: .leading)
            if controller.mode == .long, controller.phase == .listening {
                PanelIconButton(symbol: "checkmark", label: "Put the words in") { controller.finishNow() }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 11)
        .frame(width: DictationPillMetrics.width)
        .frame(minHeight: 44)
        .liquidGlass(in: shape, reading: true)
        .animation(.easeOut(duration: 0.16), value: controller.phase)
    }

    @ViewBuilder
    private var leading: some View {
        if controller.notice != nil, controller.phase == .idle {
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

    @ViewBuilder
    private var words: some View {
        if let notice = controller.notice, controller.phase == .idle {
            Text(notice)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        } else if controller.transcript.isEmpty {
            Text(controller.phase == .finishing ? "Finishing…" : "Listening…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else {
            let parts = PillWords(controller.transcript, limit: DictationPillMetrics.visibleCharacters)
            (Text(parts.settled) + Text(parts.tentative).foregroundStyle(.secondary))
                .font(.system(size: 13))
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(controller.transcript.text)
        }
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
