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
    nonisolated public static func cgPath(in rect: CGRect, amplitude: CGFloat) -> CGPath {
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
    nonisolated public static func amplitude(forLevel level: Float) -> CGFloat {
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
    static let maxHeight: CGFloat = 262
    /// The window keeps one size; the pill sits at its top or bottom edge.
    public static let windowSize = CGSize(width: width + sideMargin * 2, height: PanelMetrics.menuBarGap + maxHeight)
    /// Where the window sits above the Dock when the pill is at the bottom of the screen. With `bottomRoom` inside
    /// the window, the pill is 18 points above the Dock.
    public static let bottomGap: CGFloat = 6
    /// Below the pill inside its window, so the rim of the glass isn't cut off by the window's edge.
    static let bottomRoom: CGFloat = 12
    /// The most words kept on show. Earlier ones scroll out of view anyway, past ten lines.
    static let visibleWords = 400
    /// The words grow from one line to ten, then scroll to keep the newest in view.
    static let wordsMaxHeight: CGFloat = 10 * 18.5
    static let control: CGFloat = 34
    static let gap: CGFloat = 8
    /// The faintest red, so Cancel reads as Cancel without shouting.
    static let cancelTint = Color(red: 1, green: 0.3, blue: 0.3).opacity(0.13)
    static let cancelGlyph = Color(red: 1, green: 0.74, blue: 0.74)
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
        .padding(.bottom, atTop ? 0 : DictationPillMetrics.bottomRoom)
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
                if showsWaiting {
                    waitingMessage
                        .padding(.horizontal, 10)
                        .frame(height: DictationPillMetrics.control)
                        .liquidGlass(in: Capsule())
                        .transition(.opacity)
                } else if showsSeconds {
                    seconds
                        .padding(.horizontal, 12)
                        .frame(height: DictationPillMetrics.control)
                        .liquidGlass(in: Capsule())
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                buttons
            }
            wordsArea(alignment: .leading, padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                .frame(width: DictationPillMetrics.width)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), reading: true)
        }
    }

    private var waveCircle: some View {
        leadingSymbol
            .frame(width: DictationPillMetrics.control, height: DictationPillMetrics.control)
            .pillCircle(interactive: false)
    }

    // MARK: Floating: the words on a soft blur with no box, the wave, the seconds and Done below

    private var floating: some View {
        VStack(spacing: 6) {
            wordsArea(alignment: .center, padding: EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 0.5)
                .frame(width: DictationPillMetrics.width)
                .background {
                    // Wider than the words, so the blur has faded away before its edge, with no rim to see.
                    SoftBlur(points: 28, dim: 0.24)
                        .padding(.horizontal, -30)
                        .padding(.vertical, -16)
                }
            HStack(spacing: DictationPillMetrics.gap) {
                HStack(spacing: 8) {
                    leadingSymbol
                    if showsWaiting {
                        waitingMessage
                    } else if showsSeconds {
                        seconds
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: DictationPillMetrics.control)
                .liquidGlass(in: Capsule())
                buttons
            }
        }
    }

    // MARK: Pieces

    private var showsNotice: Bool { controller.notice != nil && controller.phase == .idle }
    /// Nothing that takes text had the cursor, so the words wait for a click into a field.
    private var showsWaiting: Bool { controller.phase == .holding }
    private var showsSeconds: Bool { controller.listeningSince != nil && !showsNotice && !showsWaiting }
    private var showsDone: Bool { controller.mode == .long && controller.phase == .listening }

    /// Cancel, ✨ and Done during a long dictation, or × and Copy while the words wait for a field.
    @ViewBuilder
    private var buttons: some View {
        if showsDone {
            Group {
                cancelButton
                if controller.field == nil { improveButton }
                doneButton
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else if showsWaiting {
            Group {
                cancelButton
                copyButton
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    @ViewBuilder
    private var leadingSymbol: some View {
        if controller.isLoadingModel {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else if showsNotice {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
                .frame(width: 20, height: 20)
        } else if showsWaiting {
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 14, weight: .medium))
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

    /// 202 points wide at this size. In the card's top row, with the symbol, × and Copy beside it, 4 points are left.
    private var waitingMessage: some View {
        Text("Click where these words should go")
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }

    nonisolated static func elapsed(from start: Date?, to now: Date) -> String {
        guard let start else { return "0:00" }
        let total = max(Int(now.timeIntervalSince(start)), 0)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private var cancelButton: some View {
        Button {
            controller.cancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DictationPillMetrics.cancelGlyph)
                .frame(width: DictationPillMetrics.control, height: DictationPillMetrics.control)
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .pillCircle(tint: DictationPillMetrics.cancelTint)
        .help("Throw the words away")
        .accessibilityLabel("Cancel")
    }

    private var improveButton: some View {
        Button {
            controller.improveNow()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: DictationPillMetrics.control, height: DictationPillMetrics.control)
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .pillCircle()
        .help("Open the words in OmanAI, to proofread or rewrite them before they go in")
        .accessibilityLabel("Proofread or rewrite first")
    }

    private var copyButton: some View {
        Button {
            controller.copyHeldWords()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: DictationPillMetrics.control, height: DictationPillMetrics.control)
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .pillCircle()
        .help("Copy the words")
        .accessibilityLabel("Copy")
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
        .pillCircle()
        .help("Put the words in")
        .accessibilityLabel("Done")
    }

    /// The words, in an area that grows with them up to ten lines and then scrolls to keep the newest in view.
    private func wordsArea(alignment: HorizontalAlignment, padding: EdgeInsets) -> some View {
        ScrollView(.vertical) {
            words(alignment: alignment)
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(minHeight: 40, maxHeight: DictationPillMetrics.wordsMaxHeight + padding.top + padding.bottom)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.22), value: controller.transcript)
    }

    @ViewBuilder
    private func words(alignment: HorizontalAlignment) -> some View {
        Group {
            if let notice = controller.notice, showsNotice {
                Text(notice)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if controller.isLoadingModel, controller.transcript.isEmpty {
                Text("Getting \(controller.modelName) ready…")
                    .foregroundStyle(.secondary)
            } else if controller.transcript.isEmpty {
                Text(controller.phase == .finishing ? "Finishing…" : "Listening…")
                    .foregroundStyle(.secondary)
            } else {
                LiveWords(transcript: controller.transcript, alignment: alignment)
            }
        }
        .font(.system(size: 13))
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }
}

/// The live words, laid out as text. Each new word fades in from a slight blur as it arrives, rather than appearing
/// all at once, and the model's guess at the newest words stays dimmer until it settles.
struct LiveWords: View {
    let transcript: LiveTranscript
    let alignment: HorizontalAlignment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Word: Identifiable, Equatable {
        /// The word's place in the whole dictation, so a word keeps its identity while others arrive after it.
        let id: Int
        let text: String
        let isGuess: Bool
    }

    nonisolated static func words(of transcript: LiveTranscript, limit: Int = DictationPillMetrics.visibleWords) -> [Word] {
        let settled = transcript.confirmed.split(separator: " ").map(String.init)
        let guess = transcript.tentative.split(separator: " ").map(String.init)
        let all = settled.enumerated().map { Word(id: $0.offset, text: $0.element, isGuess: false) }
            + guess.enumerated().map { Word(id: settled.count + $0.offset, text: $0.element, isGuess: true) }
        return Array(all.suffix(limit))
    }

    var body: some View {
        let words = Self.words(of: transcript)
        FlowLayout(spacing: 3.6, lineSpacing: 3, alignment: alignment) {
            ForEach(words) { word in
                Text(word.text)
                    .foregroundStyle(word.isGuess ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .contentTransition(.opacity)
                    .transition(WordArrival(reduceMotion: reduceMotion))
            }
        }
        .animation(.easeOut(duration: 0.3), value: words)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(transcript.text)
    }
}

/// How a word arrives: from transparent, slightly blurred and a little low, to clear and in place. With Reduce
/// Motion on it only fades.
struct WordArrival: Transition {
    var reduceMotion = false

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity || reduceMotion ? 0 : 3)
            .offset(y: phase.isIdentity || reduceMotion ? 0 : 3)
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

private extension View {
    /// A round glass control. The glass alone is lit from above, so its sides look darker than its top and bottom
    /// and the circle reads a little wide; an even ring around it keeps it round.
    func pillCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        liquidGlass(in: Circle(), tint: tint, interactive: interactive)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
