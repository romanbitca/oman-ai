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

    private struct ActivePaste {
        let id: Int
        let snapshot: PasteboardSnapshot
        let writtenCount: Int
    }

    private let pasteboard: NSPasteboard
    private let timing: Timing
    private let postCopy: () -> Void
    private let postPaste: () -> Void
    private var lateCopyWatch: LateCopyWatch?
    private var activePaste: ActivePaste?
    private var pasteCount = 0

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
        giveBackBorrowedClipboard()
        let snapshot = PasteboardSnapshot(of: pasteboard)
        let originalCount = pasteboard.changeCount
        postCopy()

        var copied: String?
        // An app can clear the pasteboard before it finishes writing, so wait for the text itself.
        _ = await poll(for: timing.copyWait) {
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
            _ = await self.poll(for: self.timing.lateCopyWatch) {
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
        giveBackBorrowedClipboard()
        let snapshot = PasteboardSnapshot(of: pasteboard)
        let receipt = pasteboard.writeTransientString(text)
        let writtenCount = pasteboard.changeCount
        pasteCount += 1
        let id = pasteCount
        activePaste = ActivePaste(id: id, snapshot: snapshot, writtenCount: writtenCount)
        postPaste()

        await pause(timing.pasteHold)
        if !receipt.wasRead {
            // The app has not asked for the text yet. Giving the clipboard back now would make it
            // paste the old contents instead, so wait until it asks, up to a limit.
            _ = await poll(for: timing.slowPasteWait) {
                receipt.wasRead || pasteboard.changeCount != writtenCount
            }
            if receipt.wasRead {
                await pause(timing.afterReadGrace)
            }
        }

        // Another clipboard operation may have started meanwhile and already given the clipboard back.
        guard activePaste?.id == id else { return }
        activePaste = nil
        snapshot.restore(to: pasteboard, ifChangeCountIs: writtenCount)
    }

    // MARK: The person's own copy

    /// Replaces whatever was being borrowed, so nothing is given back over it.
    func copy(_ text: String) {
        lateCopyWatch?.task.cancel()
        lateCopyWatch = nil
        activePaste = nil
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: Private

    /// A new operation has to start from the person's own clipboard, not from text that is passing through.
    private func giveBackBorrowedClipboard() {
        settleLateCopy()
        if let paste = activePaste {
            activePaste = nil
            paste.snapshot.restore(to: pasteboard, ifChangeCountIs: paste.writtenCount)
        }
    }

    private func poll(for duration: Duration, until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: duration)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            await pause(timing.pollInterval)
        }
        return condition()
    }

    /// Detached so that cancelling the caller cannot cut a wait short and give the clipboard back too early.
    private func pause(_ duration: Duration) async {
        await Task.detached {
            try? await Task.sleep(for: duration)
        }.value
    }
}
