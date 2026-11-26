import Foundation

/// Packs capture buffers into 250 ms signed 16-bit frames. With the microphone
/// enabled, channel 0 is always the local microphone and channel 1 computer
/// output, so the backend can label speakers deterministically.
struct PCMFrameMixer {
    static let sampleRate = 48_000
    static let samplesPerFrame = sampleRate / 4
    private static let maxBuffered = samplesPerFrame * 8

    let includeMicrophone: Bool
    var microphoneAvailable = false
    private var system: [Int16] = []
    private var microphone: [Int16] = []

    init(includeMicrophone: Bool) { self.includeMicrophone = includeMicrophone }

    mutating func pushSystem(_ samples: [Int16]) -> [Data] {
        Self.append(samples, to: &system)
        return drain()
    }

    mutating func pushMicrophone(_ samples: [Int16]) -> [Data] {
        guard includeMicrophone else { return [] }
        microphoneAvailable = true
        Self.append(samples, to: &microphone)
        return drain()
    }

    private static func append(_ samples: [Int16], to buffer: inout [Int16]) {
        buffer.append(contentsOf: samples)
        if buffer.count > maxBuffered { buffer.removeFirst(buffer.count - maxBuffered) }
    }

    private mutating func drain() -> [Data] {
        let size = Self.samplesPerFrame
        var frames: [Data] = []
        while true {
            let systemReady = system.count >= size
            // Never let a stalled microphone hold computer audio for more than a second.
            let microphoneReady = !includeMicrophone || !microphoneAvailable || microphone.count >= size || system.count >= size * 4
            // Nor may the microphone wait on silent computer output: once it is a
            // frame ahead, send it with a silent system channel.
            let silentSystem = !systemReady && includeMicrophone && microphoneAvailable && microphone.count >= size * 2
            guard (systemReady && microphoneReady) || silentSystem else { break }
            if includeMicrophone {
                var interleaved = [Int16](repeating: 0, count: size * 2)
                let micCount = min(size, microphone.count)
                for index in 0..<micCount { interleaved[index * 2] = microphone[index] }
                if !silentSystem {
                    for index in 0..<size { interleaved[index * 2 + 1] = system[index] }
                }
                microphone.removeFirst(micCount)
                frames.append(interleaved.withUnsafeBufferPointer { Data(buffer: $0) })
            } else {
                frames.append(system.prefix(size).withUnsafeBufferPointer { Data(buffer: $0) })
            }
            if !silentSystem { system.removeFirst(size) }
        }
        return frames
    }

    static func pcm(_ samples: [Float]) -> [Int16] {
        samples.map { sample in
            let clipped = max(-1, min(1, sample.isFinite ? sample : 0))
            return Int16((clipped < 0 ? clipped * 32_768 : clipped * 32_767).rounded())
        }
    }
}

/// Linear resampler that carries its position across buffers.
struct LinearResampler {
    let step: Double
    private var pending: [Float] = []
    private var position = 0.0

    init(from source: Double, to target: Double = Double(PCMFrameMixer.sampleRate)) { step = source / target }

    mutating func process(_ samples: [Float]) -> [Float] {
        if abs(step - 1) < 0.000_001 { return samples }
        pending.append(contentsOf: samples)
        var output: [Float] = []
        while position + 1 < Double(pending.count) {
            let index = Int(position)
            let fraction = Float(position - Double(index))
            output.append(pending[index] + (pending[index + 1] - pending[index]) * fraction)
            position += step
        }
        let consumed = min(Int(position), max(0, pending.count - 1))
        if consumed > 0 {
            pending.removeFirst(consumed)
            position -= Double(consumed)
        }
        return output
    }
}
