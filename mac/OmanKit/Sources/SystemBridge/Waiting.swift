import Foundation

/// Waits that a cancelled caller can't cut short. Cutting one short would give the clipboard back too early.
enum Waiting {
    static func pause(_ duration: Duration) async {
        await Task.detached {
            try? await Task.sleep(for: duration)
        }.value
    }

    @MainActor
    static func poll(every interval: Duration, for duration: Duration, until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: duration)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            await pause(interval)
        }
        return condition()
    }
}
