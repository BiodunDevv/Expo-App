import Foundation

/// How loud a moment of audio is, from 0 to 1, for the voice orb.
enum AudioLevel {
    /// `frame` holds little-endian 16-bit samples.
    static func of(_ frame: Data) -> Double {
        let samples = frame.count / 2
        guard samples > 0 else { return 0 }
        let sum = frame.withUnsafeBytes { raw in
            (0..<samples).reduce(0.0) { total, index in
                let value = Double(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32_768
                return total + value * value
            }
        }
        // Speech sits low on a linear scale, so it is lifted into view.
        return min(1, (sum / Double(samples)).squareRoot() * 4)
    }
}
