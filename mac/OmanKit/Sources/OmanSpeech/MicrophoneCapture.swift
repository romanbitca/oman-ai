import AudioToolbox
import AVFoundation
#if os(macOS)
import CoreAudio
#endif
import Foundation
import OmanCore

/// Listens to the microphone chosen in Settings, or else the one chosen in System Settings, and hands the sound on
/// in the format a model wants, together with how loud it is.
final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private let onAudio: @Sendable (AVAudioPCMBuffer) -> Void
    private let onLevel: @Sendable (Float) -> Void
    // Only touched on the audio thread once the tap is installed.
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var isRunning = false

    init(
        targetFormat: AVAudioFormat,
        onAudio: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        self.targetFormat = targetFormat
        self.onAudio = onAudio
        self.onLevel = onLevel
    }

    func start() throws {
        #if os(iOS)
        // On the iPhone the app has to ask for the microphone through its audio session first.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: [])
            if let port = AudioDevices.chosenPort() { try? session.setPreferredInput(port) }
        } catch {
            throw DictationError.failed("The microphone couldn't be started: \(error.localizedDescription)")
        }
        #endif
        let input = engine.inputNode
        #if os(macOS)
        if var device = AudioDevices.chosenDevice(), let unit = input.audioUnit {
            // When this fails, the microphone chosen in System Settings is used instead.
            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
        #endif
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw DictationError.noMicrophone
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw DictationError.failed("The microphone's sound couldn't be read.")
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw DictationError.failed("The microphone couldn't be started: \(error.localizedDescription)")
        }
        lock.withLock { isRunning = true }
    }

    func stop() {
        let wasRunning = lock.withLock {
            defer { isRunning = false }
            return isRunning
        }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        // Lets music that was playing come back.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        onLevel(Self.level(of: buffer))
        guard let converter, let converted = Self.convert(buffer, with: converter, to: targetFormat) else { return }
        onAudio(converted)
    }

    static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    /// From 0 for silence to 1 for a raised voice, on a scale of loudness rather than of the raw signal.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = channels[0]
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        // About -55 dB is a quiet room and -15 dB a raised voice close to the microphone.
        return min(max((decibels + 55) / 40, 0), 1)
    }
}
