import AppKit
import Testing
@testable import SystemBridge

/// Stands in for the app in front: what it does when ⌘C or ⌘V reaches it.
@MainActor
private final class FakeApp {
    var onCopy: () -> Void = {}
    var onPaste: () -> Void = {}
    var copies = 0
    var pastes = 0
    var pasted: [String?] = []
}

@MainActor
private func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}

/// Every test uses its own named pasteboard, never the real clipboard.
@MainActor
@Suite struct ClipboardRouteTests {
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("oman-test-\(UUID().uuidString)"))
    private let app = FakeApp()

    /// Short waits where a test has to sit one out, long limits where it only needs them not to run out.
    private var timing: ClipboardRoute.Timing {
        var timing = ClipboardRoute.Timing()
        timing.pollInterval = .milliseconds(2)
        timing.copyWait = .milliseconds(60)
        timing.lateCopyWatch = .seconds(5)
        timing.pasteHold = .milliseconds(40)
        timing.slowPasteWait = .seconds(5)
        timing.afterReadGrace = .milliseconds(10)
        return timing
    }

    private func makeRoute(_ timing: ClipboardRoute.Timing? = nil) -> ClipboardRoute {
        let app = app
        return ClipboardRoute(
            pasteboard: pasteboard,
            timing: timing ?? self.timing,
            postCopy: {
                app.copies += 1
                app.onCopy()
            },
            postPaste: {
                app.pastes += 1
                app.onPaste()
            }
        )
    }

    private func put(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var clipboard: String? { pasteboard.string(forType: .string) }

    // MARK: Reading the selection

    @Test func aPromptCopyIsReadAndTheClipboardGivenBack() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        app.onCopy = { put("the selection") }

        let copied = await makeRoute().copySelection()

        #expect(copied == "the selection")
        #expect(clipboard == "user clipboard")
        #expect(app.copies == 1)
    }

    @Test func aCopyThatClearsFirstAndWritesAMomentLaterIsStillRead() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let pasteboard = pasteboard
        app.onCopy = {
            pasteboard.clearContents()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(10))
                pasteboard.setString("the selection", forType: .string)
            }
        }
        var patient = timing
        patient.copyWait = .seconds(5)

        let copied = await makeRoute(patient).copySelection()

        #expect(copied == "the selection")
        #expect(clipboard == "user clipboard")
    }

    @Test func whenNothingIsCopiedTheClipboardIsNotTouched() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let countBefore = pasteboard.changeCount

        let copied = await makeRoute().copySelection()

        #expect(copied == nil)
        #expect(clipboard == "user clipboard")
        #expect(pasteboard.changeCount == countBefore)
    }

    @Test func aCopyThatIsNotTextGivesTheClipboardBack() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let pasteboard = pasteboard
        app.onCopy = {
            pasteboard.clearContents()
            pasteboard.setData(Data([0x01]), forType: NSPasteboard.PasteboardType("com.romanbitca.oman.test"))
        }

        let copied = await makeRoute().copySelection()

        #expect(copied == nil)
        #expect(clipboard == "user clipboard")
    }

    @Test func aCopyThatArrivesAfterThePanelGaveUpIsUndone() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let route = makeRoute()

        // The app is busy: nothing is copied while the panel waits.
        #expect(await route.copySelection() == nil)

        // Then it gets round to the ⌘C it was sent.
        put("the selection")
        #expect(await eventually { clipboard == "user clipboard" })
    }

    @Test func aClipboardEmptiedAfterThePanelGaveUpStaysEmpty() async throws {
        defer { pasteboard.releaseGlobally() }
        put("a password that its manager is about to clear")
        let route = makeRoute()
        #expect(await route.copySelection() == nil)

        pasteboard.clearContents()
        try await Task.sleep(for: .milliseconds(60))

        #expect(clipboard == nil)
    }

    @Test func aNewCopyStartsFromThePersonsClipboardEvenIfALateCopyJustLanded() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let route = makeRoute()
        #expect(await route.copySelection() == nil)

        put("late selection")
        app.onCopy = { put("second selection") }
        let second = await route.copySelection()

        #expect(second == "second selection")
        #expect(clipboard == "user clipboard")
    }

    @Test func thePersonsOwnCopyIsNotUndone() async throws {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let route = makeRoute()
        #expect(await route.copySelection() == nil)

        route.copy("the result")
        try await Task.sleep(for: .milliseconds(60))

        #expect(clipboard == "the result")
    }

    // MARK: Pasting

    @Test func aPasteIsReadThenTheClipboardIsGivenBack() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let pasteboard = pasteboard
        let app = app
        var typesSeen: [NSPasteboard.PasteboardType] = []
        app.onPaste = {
            typesSeen = pasteboard.types ?? []
            app.pasted.append(pasteboard.string(forType: .string))
        }

        await makeRoute().paste("new text")

        #expect(app.pasted == ["new text"])
        #expect(typesSeen.contains(NSPasteboard.transientType))
        #expect(clipboard == "user clipboard")
    }

    @Test func anAppThatReadsLateStillGetsTheNewText() async throws {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let route = makeRoute()
        let pasting = Task { await route.paste("new text") }
        // On a busy machine the paste can take a while to begin, so wait for the key press itself.
        #expect(await eventually { app.pastes == 1 })

        // Well past the hold. Giving the clipboard back on a timer alone would hand this app the old contents.
        try await Task.sleep(for: .milliseconds(150))
        #expect(clipboard == "new text")

        await pasting.value
        #expect(clipboard == "user clipboard")
    }

    @Test func aPasteNobodyReadsIsGivenBackAtTheLimit() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        var impatient = timing
        impatient.slowPasteWait = .milliseconds(60)

        await makeRoute(impatient).paste("new text")

        #expect(clipboard == "user clipboard")
    }

    @Test func somethingCopiedDuringAPasteIsKept() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        app.onPaste = { put("copied meanwhile") }

        await makeRoute().paste("new text")

        #expect(clipboard == "copied meanwhile")
    }

    @Test func aCopyDuringAPasteWaitsForItsTurn() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let pasteboard = pasteboard
        let app = app
        app.onPaste = { app.pasted.append(pasteboard.string(forType: .string)) }
        app.onCopy = {
            // By the time the copy runs, the paste has finished and given the clipboard back.
            app.pasted.append(pasteboard.string(forType: .string))
            pasteboard.clearContents()
            pasteboard.setString("the selection", forType: .string)
        }
        let route = makeRoute()
        let pasting = Task { await route.paste("new text") }
        #expect(await eventually { app.pastes == 1 })

        let copied = await route.copySelection()
        await pasting.value

        #expect(app.pasted == ["new text", "user clipboard"])
        #expect(copied == "the selection")
        #expect(clipboard == "user clipboard")
    }

    @Test func twoCopiesStartedTogetherEachSeeOnlyTheirOwn() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let pasteboard = pasteboard
        // The app takes a moment over each ⌘C, as a real one does, so the two requests overlap.
        app.onCopy = {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(10))
                pasteboard.clearContents()
                pasteboard.setString("the selection", forType: .string)
            }
        }
        var patient = timing
        patient.copyWait = .seconds(5)
        let route = makeRoute(patient)

        let first = Task { await route.copySelection() }
        let second = Task { await route.copySelection() }

        #expect(await first.value == "the selection")
        #expect(await second.value == "the selection")
        #expect(clipboard == "user clipboard")
        #expect(app.copies == 2)
    }

    @Test func textIsOfferedAndReadOnlyWhenItIsOrdinary() {
        defer { pasteboard.releaseGlobally() }
        let route = makeRoute()
        put("hello")
        #expect(route.offersText)
        #expect(route.text() == "hello")

        pasteboard.writeTransientString("passing through")
        #expect(route.offersText == false)
        #expect(route.text() == nil)
    }

    @Test func thePersonsOwnCopyDuringAPasteIsKept() async {
        defer { pasteboard.releaseGlobally() }
        put("user clipboard")
        let route = makeRoute()
        let pasting = Task { await route.paste("new text") }
        #expect(await eventually { app.pastes == 1 })

        route.copy("the result")
        await pasting.value

        #expect(clipboard == "the result")
    }
}
