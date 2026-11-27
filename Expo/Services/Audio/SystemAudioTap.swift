import AudioToolbox
import CoreAudio
import Foundation

struct AudioCaptureError: LocalizedError, Sendable {
    var message: String
    /// Retrying cannot help (missing permission, source or OS support).
    var permanent = false
    var errorDescription: String? { message }
}

/// Captures computer output with a private Core Audio process tap and delivers
/// 48 kHz mono samples on `queue`. Nothing is muted and nothing is stored.
final class SystemAudioTap: @unchecked Sendable {
    private let queue: DispatchQueue
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var builtFor: String?

    init(queue: DispatchQueue) { self.queue = queue }

    deinit { stop() }

    /// `processID == nil` captures all computer output except this app.
    func start(processIDs: [pid_t]?, onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        stop()
        do {
            let description: CATapDescription
            if let processIDs {
                let objects = processIDs.compactMap(Self.processObject)
                guard !objects.isEmpty else {
                    throw AudioCaptureError(message: "The selected application is not playing audio yet. Start its audio and try again.", permanent: true)
                }
                description = CATapDescription(monoMixdownOfProcesses: objects)
            } else {
                let own = Self.processObject(getpid()).map { [$0] } ?? []
                description = CATapDescription(monoGlobalTapButExcludeProcesses: own)
            }
            description.uuid = UUID()
            description.name = "Expo private conversation capture"
            description.isPrivate = true
            description.muteBehavior = .unmuted

            try check(AudioHardwareCreateProcessTap(description, &tap), "Expo could not open computer audio. Allow Expo under System Settings → Privacy & Security → Screen & System Audio Recording.")

            guard let output = Self.defaultOutputUID() else {
                throw AudioCaptureError(message: "No default audio output device was found.")
            }
            let settings: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Expo private conversation aggregate",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: output,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            try check(AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate), "Expo could not prepare the audio capture device.")

            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = Self.address(kAudioTapPropertyFormat)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "Expo could not read the audio format.")
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
                throw AudioCaptureError(message: "This audio device uses an unsupported format.", permanent: true)
            }

            let converter = Converter(rate: format.mSampleRate)
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { _, input, _, _, _ in
                let mono = Converter.mono(input)
                if !mono.isEmpty { onSamples(converter.resampler.process(mono)) }
            }, "Expo could not read from the audio device.")
            try check(AudioDeviceStart(aggregate, ioProc), "Expo could not start computer audio capture.")
            builtFor = output
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregate != kAudioObjectUnknown {
            if let ioProc {
                AudioDeviceStop(aggregate, ioProc)
                AudioDeviceDestroyIOProcID(aggregate, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        ioProc = nil
        builtFor = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    /// Only touched from the serial capture queue.
    private final class Converter: @unchecked Sendable {
        var resampler: LinearResampler
        init(rate: Double) { resampler = LinearResampler(from: rate) }

        static func mono(_ list: UnsafePointer<AudioBufferList>) -> [Float] {
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            // The tap is mono; it is the last input stream of the aggregate device.
            guard let buffer = buffers.last, let data = buffer.mData else { return [] }
            let channels = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            let samples = data.bindMemory(to: Float.self, capacity: frames * channels)
            return (0..<frames).map { frame in
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                return sum / Float(channels)
            }
        }
    }

    /// The Mac switched speakers or headphones since capture began.
    var outputChanged: Bool {
        guard let builtFor, let current = Self.defaultOutputUID() else { return false }
        return current != builtFor
    }

    private func check(_ status: OSStatus, _ message: String) throws {
        guard status == noErr else { throw AudioCaptureError(message: "\(message) (\(status))") }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObject(_ pid: pid_t) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputUID() -> String? {
        var address = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var uidAddress = Self.address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}
