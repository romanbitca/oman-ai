import AppKit

/// Reads a selection out of the frontmost app with ⌘C and puts text into it with ⌘V.
/// Each borrows the clipboard for a moment and gives it back.
@MainActor
final class ClipboardRoute {
    struct Timing {
        var pollInterval = Duration.milliseconds(10)
        /// How long the panel waits for a copy before it opens without a selection.
        var copyWait = Duration.milliseconds(250)
        /// A busy app can copy after that. For this much longer its late copy is still caught and undone.
        var lateCopyWatch = Duration.milliseconds(1000)
        /// The clipboard is never given back sooner than this after a paste.
        var pasteHold = Duration.milliseconds(500)
        /// How much longer to wait for an app that has not asked for the pasted text yet.
        var slowPasteWait = Duration.milliseconds(2000)
        /// Time for the app to finish its paste once it has asked for the text.
        var afterReadGrace = Duration.milliseconds(150)
    }

    private struct LateCopyWatch {
        let snapshot: PasteboardSnapshot
        let baseline: Int
        let task: Task<Void, Never>
    }

    private let pasteboard: NSPasteboard
    private let timing: Timing
    private let postCopy: () -> Void
    private let postPaste: () -> Void
    private var lateCopyWatch: LateCopyWatch?
    private var lastOperation: Task<Void, Never>?
    private var pasteCount = 0
    private var activePasteID: Int?

    init(
        pasteboard: NSPasteboard,
        timing: Timing = Timing(),
        postCopy: @escaping () -> Void,
        postPaste: @escaping () -> Void
    ) {
        self.pasteboard = pasteboard
        self.timing = timing
        self.postCopy = postCopy
        self.postPaste = postPaste
    }

    // MARK: Reading the selection

    func copySelection() async -> String? {
        await inTurn { await self.copySelectionNow() }
    }

    private func copySelectionNow() async -> String? {
        settleLateCopy()
        let snapshot = PasteboardSnapshot(of: pasteboard)
        let originalCount = pasteboard.changeCount
        postCopy()

        var copied: String?
        // An app can clear the pasteboard before it finishes writing, so wait for the text itself.
        _ = await Waiting.poll(every: timing.pollInterval, for: timing.copyWait) {
            guard pasteboard.changeCount != originalCount else { return false }
            copied = pasteboard.string(forType: .string)
            return copied != nil
        }

        if pasteboard.changeCount != originalCount {
            snapshot.restore(to: pasteboard)
        }
        if copied == nil {
            // The app may only be slow. When its copy does arrive, it must not be left on the clipboard.
            watchForLateCopy(snapshot: snapshot)
        }
        return copied
    }

    private func watchForLateCopy(snapshot: PasteboardSnapshot) {
        let baseline = pasteboard.changeCount
        let task = Task { [weak self] in
            guard let self else { return }
            _ = await Waiting.poll(every: self.timing.pollInterval, for: self.timing.lateCopyWatch) {
                Task.isCancelled || self.pasteboard.changeCount != baseline
            }
            guard !Task.isCancelled else { return }
            self.settleLateCopy()
        }
        lateCopyWatch = LateCopyWatch(snapshot: snapshot, baseline: baseline, task: task)
    }

    /// Ends the watch. If the late copy has arrived, the clipboard goes back to what it held before.
    private func settleLateCopy() {
        guard let watch = lateCopyWatch else { return }
        lateCopyWatch = nil
        watch.task.cancel()
        // An emptied clipboard is not a copy. It is more likely a password manager clearing up after itself,
        // and putting the old contents back would undo that.
        if pasteboard.changeCount != watch.baseline, pasteboard.string(forType: .string)?.isEmpty == false {
            watch.snapshot.restore(to: pasteboard)
        }
    }

    // MARK: Pasting

    func paste(_ text: String) async {
        await inTurn { await self.pasteNow(text) }
    }

    private func pasteNow(_ text: String) async {
        settleLateCopy()
        let snapshot = PasteboardSnapshot(of: pasteboard)
        let receipt = pasteboard.writeTransientString(text)
        let writtenCount = pasteboard.changeCount
        pasteCount += 1
        let id = pasteCount
        activePasteID = id
        postPaste()

        await Waiting.pause(timing.pasteHold)
        if !receipt.wasRead {
            // The app has not asked for the text yet. Giving the clipboard back now would make it
            // paste the old contents instead, so wait until it asks, up to a limit.
            _ = await Waiting.poll(every: timing.pollInterval, for: timing.slowPasteWait) {
                receipt.wasRead || pasteboard.changeCount != writtenCount
            }
            if receipt.wasRead {
                await Waiting.pause(timing.afterReadGrace)
            }
        }

        // The person may have pressed Copy meanwhile. Their copy stays.
        guard activePasteID == id else { return }
        activePasteID = nil
        snapshot.restore(to: pasteboard, ifChangeCountIs: writtenCount)
    }

    // MARK: The person's own clipboard

    /// The person's own copy replaces whatever was being borrowed, so nothing is given back over it.
    func copy(_ text: String) {
        lateCopyWatch?.task.cancel()
        lateCopyWatch = nil
        activePasteID = nil
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Decided from the types alone, so nothing is read until the person asks.
    var offersText: Bool { pasteboard.offersPlainText }

    func text() -> String? {
        guard pasteboard.offersPlainText else { return nil }
        return pasteboard.string(forType: .string)
    }

    // MARK: Private

    /// One copy or paste at a time. Two that overlap would each mistake the other's writes for the app's,
    /// as when the menu bar icon is clicked twice in a row.
    private func inTurn<Result: Sendable>(_ operation: @escaping @MainActor () async -> Result) async -> Result {
        let previous = lastOperation
        let task = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        lastOperation = Task { @MainActor in
            _ = await task.value
        }
        return await task.value
    }
}
