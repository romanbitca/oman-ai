import CoreAudio
import Foundation

/// Mutes the Mac's sound output while a dictation listens, and brings back what it was afterwards.
@MainActor
final class OutputMute {
    /// The device that was muted, and whether it was muted before, so only OmanAI's own mute is undone.
    private var muted: (device: AudioDeviceID, wasMuted: Bool)?

    func setMuted(_ mute: Bool) {
        if mute {
            guard muted == nil, let device = Self.defaultOutput(), let before = Self.isMuted(device) else { return }
            if !before { Self.setMute(true, on: device) }
            muted = (device, before)
        } else {
            guard let muted else { return }
            self.muted = nil
            if !muted.wasMuted { Self.setMute(false, on: muted.device) }
        }
    }

    private static func defaultOutput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
            == noErr, device != 0
        else { return nil }
        return device
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Nil for a device that can't be muted, such as some displays' speakers.
    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func setMute(_ mute: Bool, on device: AudioDeviceID) {
        var address = muteAddress
        var value: UInt32 = mute ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
