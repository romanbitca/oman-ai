import AVFoundation
import Foundation

/// Sound as the downloaded models take it: 16,000 samples a second, one channel, as floating point numbers.
enum SpeechAudio {
    static let sampleRate = 16_000.0

    // A format this plain always exists; the force unwrap can't fail.
    nonisolated(unsafe) static let format16k = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    static func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format16k, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// A recording's sound in the models' format.
    static func samples(ofFile url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: source)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format16k),
              let converted = MicrophoneCapture.convert(source, with: converter, to: format16k)
        else { return [] }
        return samples(of: converted)
    }

    /// How loud a stretch of sound is, as its root mean square.
    static func energy(of samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return (sum / Float(samples.count)).squareRoot()
    }
}
