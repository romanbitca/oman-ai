#if os(macOS)
import CoreAudio
import Foundation
import OmanCore
import os

/// The Mac's microphones, as CoreAudio lists them, and the one Settings chose for dictation.
enum AudioDevices {
    /// The chosen microphone's lasting identifier, or nil for the one chosen in System Settings.
    private static let chosen = OSAllocatedUnfairLock<String?>(initialState: nil)

    static var chosenMicrophone: String? {
        get { chosen.withLock { $0 } }
        set { chosen.withLock { $0 = newValue } }
    }

    static func microphones() -> [Microphone] {
        deviceIDs().compactMap { device in
            guard hasInput(device), let uid = string(kAudioDevicePropertyDeviceUID, of: device) else { return nil }
            let name = string(kAudioObjectPropertyName, of: device) ?? uid
            return Microphone(id: uid, name: name)
        }
    }

    /// The device to listen to now: the chosen one while it is plugged in, otherwise nil for macOS's own choice.
    static func chosenDevice() -> AudioDeviceID? {
        guard let uid = chosenMicrophone else { return nil }
        return deviceIDs().first { hasInput($0) && string(kAudioDevicePropertyDeviceUID, of: $0) == uid }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
            == noErr
        else { return [] }
        return devices
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value
        else { return nil }
        return value.takeRetainedValue() as String
    }
}
#else
import AVFoundation
import Foundation
import OmanCore
import os

/// The iPhone's microphones, as its audio session lists them, and the one Settings chose for dictation.
enum AudioDevices {
    /// The chosen microphone's port identifier, or nil for the one iOS picks.
    private static let chosen = OSAllocatedUnfairLock<String?>(initialState: nil)

    static var chosenMicrophone: String? {
        get { chosen.withLock { $0 } }
        set { chosen.withLock { $0 = newValue } }
    }

    static func microphones() -> [Microphone] {
        (AVAudioSession.sharedInstance().availableInputs ?? []).map { Microphone(id: $0.uid, name: $0.portName) }
    }

    /// The chosen microphone while it is connected, otherwise nil for iOS's own choice.
    static func chosenPort() -> AVAudioSessionPortDescription? {
        guard let uid = chosenMicrophone else { return nil }
        return AVAudioSession.sharedInstance().availableInputs?.first { $0.uid == uid }
    }
}
#endif
