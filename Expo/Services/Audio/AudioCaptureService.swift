import AppKit
import AVFoundation

struct AudioSourceApp: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
}

/// Health reported while capturing.
struct AudioHealth: Sendable, Equatable {
    var secondsSinceFrame: Double
    var secondsSinceSound: Double
    var secondsSinceSystemSound: Double
    var secondsSinceMicrophone: Double = 0
}

/// Owns system and microphone capture and emits mixed PCM frames in order.
@MainActor
final class AudioCaptureService {
    private let queue = DispatchQueue(label: "core4.Expo.audio", qos: .userInitiated)
    private lazy var tap = SystemAudioTap(queue: queue)
    private var engine: AVAudioEngine?
    private var pipeline: Pipeline?
    private var forwarder: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?
    private var microphoneWanted = false
    private var microphoneStarted = ContinuousClock.now

    static func sourceApps() -> [AudioSourceApp] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != own }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return AudioSourceApp(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// An app and its helper processes (browsers play audio from helpers).
    private static func processIDs(bundleID: String) -> [pid_t] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleID || $0.bundleIdentifier?.hasPrefix(bundleID + ".") == true }
            .map(\.processIdentifier)
    }

    /// Returns whether the optional microphone joined the capture.
    @discardableResult
    func start(settings: ExpoSettings, onFrame: @escaping @MainActor (Data) -> Void) async throws -> Bool {
        stop()
        var processIDs: [pid_t]?
        if settings.audioCaptureMode == .selectedApplication {
            guard let bundleID = settings.audioSourceBundleID else {
                throw AudioCaptureError(message: "Choose a meeting source in Settings before starting Assist.", permanent: true)
            }
            processIDs = Self.processIDs(bundleID: bundleID)
            if processIDs?.isEmpty == true {
                throw AudioCaptureError(message: "The saved meeting source is not running. Open it or choose another in Settings.", permanent: true)
            }
        }
        var microphone = false
        if settings.captureMicrophone { microphone = await AVCaptureDevice.requestAccess(for: .audio) }

        let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingNewest(40))
        let pipeline = Pipeline(includeMicrophone: settings.captureMicrophone, output: continuation)
        self.pipeline = pipeline
        forwarder = Task {
            for await frame in stream { onFrame(frame) }
        }
        do {
            try tap.start(processIDs: processIDs) { pipeline.system($0) }
        } catch {
            stop()
            throw error
        }
        // The microphone is optional: computer output keeps working without it.
        microphoneWanted = microphone
        if microphone { microphone = startMicrophone(pipeline) }
        return microphone
    }

    func stop() {
        microphoneWanted = false
        stopMicrophone()
        tap.stop()
        pipeline?.finish()
        pipeline = nil
        forwarder?.cancel()
        forwarder = nil
    }

    var health: AudioHealth? { pipeline?.health }

    /// Another app (a meeting joining or leaving, a headset connecting) can
    /// reconfigure the microphone and silently stop it. This brings it back.
    func reviveMicrophoneIfNeeded() {
        guard microphoneWanted, let pipeline, ContinuousClock.now - microphoneStarted > .seconds(3) else { return }
        if engine?.isRunning == true && pipeline.health.secondsSinceMicrophone < 3 { return }
        stopMicrophone()
        _ = startMicrophone(pipeline)
    }

    private func stopMicrophone() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func startMicrophone(_ pipeline: Pipeline) -> Bool {
        microphoneStarted = .now
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        let sink = MicrophoneSink(rate: format.sampleRate, queue: queue, pipeline: pipeline)
        input.installTap(onBus: 0, bufferSize: 4_096, format: format, block: sink.block)
        do { try engine.start() } catch { input.removeTap(onBus: 0); return false }
        self.engine = engine
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.microphoneWanted, let pipeline = self.pipeline else { return }
                self.stopMicrophone()
                _ = self.startMicrophone(pipeline)
            }
        }
        return true
    }
}

private final class MicrophoneSink: @unchecked Sendable {
    private var resampler: LinearResampler
    private let queue: DispatchQueue
    private let pipeline: Pipeline

    init(rate: Double, queue: DispatchQueue, pipeline: Pipeline) {
        resampler = LinearResampler(from: rate)
        self.queue = queue
        self.pipeline = pipeline
    }

    /// Built outside the main actor because AVAudioEngine calls it on its own thread.
    var block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { [self] buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
            queue.async { [self] in pipeline.microphone(resampler.process(samples)) }
        }
    }
}

/// Mixer state, mutated only on the capture queue; health is lock-protected.
private final class Pipeline: @unchecked Sendable {
    private var mixer: PCMFrameMixer
    private let output: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var lastFrame = ContinuousClock.now
    private var lastSound = ContinuousClock.now
    private var lastSystemSound: ContinuousClock.Instant?
    private var lastMicrophone = ContinuousClock.now

    init(includeMicrophone: Bool, output: AsyncStream<Data>.Continuation) {
        mixer = PCMFrameMixer(includeMicrophone: includeMicrophone)
        self.output = output
    }

    var health: AudioHealth {
        lock.withLock {
            let now = ContinuousClock.now
            return AudioHealth(secondsSinceFrame: (now - lastFrame) / .seconds(1), secondsSinceSound: (now - lastSound) / .seconds(1),
                               secondsSinceSystemSound: lastSystemSound.map { (now - $0) / .seconds(1) } ?? .infinity,
                               secondsSinceMicrophone: (now - lastMicrophone) / .seconds(1))
        }
    }

    func system(_ samples: [Float]) {
        mark(samples, countsAsFrame: true)
        mixer.pushSystem(PCMFrameMixer.pcm(samples)).forEach { output.yield($0) }
    }

    func microphone(_ samples: [Float]) {
        lock.withLock { lastMicrophone = .now }
        mark(samples, countsAsFrame: false)
        mixer.pushMicrophone(PCMFrameMixer.pcm(samples)).forEach { output.yield($0) }
    }

    func finish() { output.finish() }

    private func mark(_ samples: [Float], countsAsFrame: Bool) {
        let audible = samples.contains { abs($0) > 0.000_5 }
        lock.withLock {
            if countsAsFrame { lastFrame = .now }
            if audible && countsAsFrame { lastSystemSound = .now }
            if audible { lastSound = .now }
        }
    }
}
