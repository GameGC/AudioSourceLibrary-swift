// Audio/AudioThreadManager.swift

import AVFoundation

/// Owns and vends the live capture threads for microphone, loopback, and system audio.
/// All threads are lazily created and torn down explicitly via stop().
public final class AudioThreadManager {
    
    // MARK: - Public State

    public private(set) var isCapturingMicrophone = false
    public private(set) var isCapturingBlackHole = false
    public private(set) var isCapturingSystemAudio = false

    public var activeCaptureCount: Int {
        [isCapturingMicrophone, isCapturingBlackHole, isCapturingSystemAudio]
            .filter { $0 }.count
    }

    // MARK: - Private

    private var microphoneCapture: MicrophoneCapture?
    private var blackHoleCapture: BlackHoleAudioCapture?
    private var systemCapture: SystemAudioCapture?

    public init() {}

    // MARK: - Start (returns AsyncStream, caller just iterates)

    public func startMicrophone(deviceUniqueID: String? = nil) throws -> AsyncStream<AVAudioPCMBuffer> {
        let capture = MicrophoneCapture()
        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            try? capture.start(deviceUniqueID: deviceUniqueID) { buffer in
                continuation.yield(buffer)
            }
        }
        microphoneCapture = capture
        isCapturingMicrophone = true
        return stream
    }

    public func startBlackHole() throws -> AsyncStream<AVAudioPCMBuffer> {
        let capture = BlackHoleAudioCapture()
        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            try? capture.start { buffer in
                continuation.yield(buffer)
            }
        }
        blackHoleCapture = capture
        isCapturingBlackHole = true
        return stream
    }

    public func startSystemAudio() async throws -> AsyncStream<AVAudioPCMBuffer> {
        var failureContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            failureContinuation = continuation
        }
        let capture = SystemAudioCapture(
            onBuffer: { buffer in failureContinuation?.yield(buffer) },
            onFailure: { _ in failureContinuation?.finish() }
        )
        try await capture.start()
        systemCapture = capture
        isCapturingSystemAudio = true
        return stream
    }

    // MARK: - Stop

    public func stopMicrophone() {
        microphoneCapture?.stop()
        microphoneCapture = nil
        isCapturingMicrophone = false
    }

    public func stopBlackHole() {
        blackHoleCapture?.stop()
        blackHoleCapture = nil
        isCapturingBlackHole = false
    }

    public func stopSystemAudio() {
        systemCapture?.stop()
        systemCapture = nil
        isCapturingSystemAudio = false
    }

    public func stopAll() {
        stopMicrophone()
        stopBlackHole()
        stopSystemAudio()
    }
    
    public static var isBlackHoleAvailable: Bool {
        (try? BlackHoleAudioCapture.preferredLoopbackDevice()) != nil
    }
}
