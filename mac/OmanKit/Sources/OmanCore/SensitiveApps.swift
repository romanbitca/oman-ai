import Foundation

/// Apps where a synthetic ⌘C or a paste can do more than copy and paste text.
public enum SensitiveApps {
    private static let terminals: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "org.tabby",
    ]

    /// Remote desktops and virtual machines pass key presses on to another computer,
    /// where ⌘C can arrive as Ctrl+C and stop whatever is running there.
    private static let keyForwarders: Set<String> = [
        "com.apple.ScreenSharing",
        "com.apple.RemoteDesktop",
        "com.microsoft.rdc.macos",
        "com.teamviewer.TeamViewer",
        "com.philandro.anydesk",
        "com.realvnc.vncviewer",
        "com.p5sys.jump.mac.viewer",
        "com.lemonmojo.RoyalTSX.App",
        "tv.parsec.www",
        "com.moonlight-stream.Moonlight",
        "com.utmapp.UTM",
        "codes.rambo.VirtualBuddy",
    ]

    private static let keyForwarderPrefixes = [
        "com.parallels.",
        "com.vmware.",
        "org.virtualbox.app.",
        "com.citrix.",
    ]

    /// Text pasted into a terminal can run as a command.
    public static func isTerminal(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return terminals.contains(bundleID)
    }

    public static func forwardsKeys(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return keyForwarders.contains(bundleID) || keyForwarderPrefixes.contains { bundleID.hasPrefix($0) }
    }

    /// Where the selection is read through Accessibility only, never with a synthetic ⌘C.
    public static func skipsSyntheticCopy(bundleID: String?) -> Bool {
        isTerminal(bundleID: bundleID) || forwardsKeys(bundleID: bundleID)
    }
}
