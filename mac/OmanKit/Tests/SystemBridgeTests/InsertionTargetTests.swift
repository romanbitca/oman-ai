import Foundation
import OmanCore
import Testing
@testable import SystemBridge

@Suite struct InsertionTargetTests {
    /// The answers to a run of `confirm` calls. `#expect` can't call a mutating method itself.
    private func answers(
        remembering element: Int?,
        processID: pid_t = 42,
        then checks: [(element: Int?, processID: pid_t)]
    ) -> [Bool] {
        var target = InsertionTarget<Int> { $0 == $1 }
        target.remember(element, processID: processID)
        return checks.map { target.confirm($0.element, processID: $0.processID) }
    }

    @Test func theSamePlaceIsConfirmed() {
        #expect(answers(remembering: 1, then: [(1, 42), (1, 42)]) == [true, true])
    }

    @Test func aMovedCursorIsRefusedOnceThenAccepted() {
        #expect(answers(remembering: 1, then: [(2, 42), (2, 42), (1, 42)]) == [false, true, false])
    }

    @Test func nothingIsRefusedWhenTheAppDoesNotSayWhatHasFocus() {
        #expect(answers(remembering: nil, then: [(2, 42)]) == [true])
        #expect(answers(remembering: 1, then: [(nil, 42), (1, 42)]) == [true, true])
    }

    @Test func anotherAppIsNotCompared() {
        #expect(answers(remembering: 1, then: [(2, 7)]) == [true])
    }

    @Test func rememberingAgainReplacesThePlace() {
        var target = InsertionTarget<Int> { $0 == $1 }
        target.remember(1, processID: 42)
        target.remember(2, processID: 42)
        let confirmed = target.confirm(2, processID: 42)
        #expect(confirmed)
    }
}

@Suite struct SensitiveAppsTests {
    @Test(arguments: ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty"])
    func terminalsAreRecognised(bundleID: String) {
        #expect(SensitiveApps.isTerminal(bundleID: bundleID))
        #expect(SensitiveApps.skipsSyntheticCopy(bundleID: bundleID))
        #expect(SensitiveApps.forwardsKeys(bundleID: bundleID) == false)
    }

    @Test(arguments: [
        "com.apple.ScreenSharing",
        "com.microsoft.rdc.macos",
        "com.utmapp.UTM",
        "com.parallels.desktop.console",
        "com.vmware.fusion",
        "org.virtualbox.app.VirtualBoxVM",
    ])
    func remoteDesktopsAndVirtualMachinesAreRecognised(bundleID: String) {
        #expect(SensitiveApps.forwardsKeys(bundleID: bundleID))
        #expect(SensitiveApps.skipsSyntheticCopy(bundleID: bundleID))
        #expect(SensitiveApps.isTerminal(bundleID: bundleID) == false)
    }

    @Test(arguments: ["com.tinyspeck.slackmacgap", "com.apple.mail", "com.google.Chrome", "com.microsoft.VSCode"])
    func ordinaryAppsStillUseTheSyntheticCopy(bundleID: String) {
        #expect(SensitiveApps.skipsSyntheticCopy(bundleID: bundleID) == false)
    }

    @Test func anAppWithoutABundleIDIsOrdinary() {
        #expect(SensitiveApps.skipsSyntheticCopy(bundleID: nil) == false)
        #expect(SensitiveApps.isTerminal(bundleID: nil) == false)
    }
}
