import Foundation
import AVFoundation

/// Uses AVCaptureSession with an explicit hardware device choice so capture does not follow the
/// system default Core Audio input (often a broken aggregate) the way AVAudioEngine does.
internal class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "DualAudioRecorder.mic.session")
    private let sampleQueue = DispatchQueue(label: "DualAudioRecorder.mic.samples")
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?

    static func listSelectableMicrophones() -> [AudioInputDeviceOption] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let raw = discovery.devices
        let filtered = raw.filter { !isLikelyVirtualOrAggregateInput($0) }
        let use = filtered.isEmpty ? raw : filtered
        let options = use.map { AudioInputDeviceOption(id: $0.uniqueID, name: $0.localizedName) }
        return options.sorted { a, b in
            let ra = inputPriorityRank(forName: a.name)
            let rb = inputPriorityRank(forName: b.name)
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func inputPriorityRank(forName name: String) -> Int {
        let n = name.lowercased()
        if n.contains("macbook") || n.contains("imac") || n.contains("mac studio") || n.contains("mac pro") {
            return 0
        }
        if n.contains("studio display") || n.contains("built-in") || n.contains("built in") {
            return 0
        }
        return 1
    }

    func start(deviceUniqueID: String?, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        bufferCallback = onBuffer
        let device: AVCaptureDevice
        if let id = deviceUniqueID, !id.isEmpty {
            guard let resolved = AVCaptureDevice(uniqueID: id) else {
                throw AudioInputError.noAudioInputDevice
            }
            device = resolved
        } else {
            device = try Self.preferredMicrophoneDevice()
        }

        let input = try AVCaptureDeviceInput(device: device)
        try sessionQueue.sync {
            session.beginConfiguration()
            session.sessionPreset = .high

            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw AudioInputError.noAudioInputDevice
            }
            session.addInput(input)

            audioOutput.audioSettings = PCMAudio.captureSettings(for: device,defaultChannels: 1)
            audioOutput.setSampleBufferDelegate(self, queue: sampleQueue)

            guard session.canAddOutput(audioOutput) else {
                session.removeInput(input)
                session.commitConfiguration()
                throw AudioInputError.noAudioInputDevice
            }
            session.addOutput(audioOutput)
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.sync {
            session.stopRunning()
            session.beginConfiguration()
            for output in session.outputs { session.removeOutput(output) }
            for input in session.inputs { session.removeInput(input) }
            session.commitConfiguration()
        }
        bufferCallback = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let bufferCallback else { return }
        do {
            let pcm = try PCMAudio.MakeBuffer(from: sampleBuffer)
            bufferCallback(pcm)
        } catch {
            // Drop bad samples.
        }
    }


    private static func preferredMicrophoneDevice() throws -> AVCaptureDevice {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let candidates = discovery.devices.filter { !isLikelyVirtualOrAggregateInput($0) }
        let devices = candidates.isEmpty ? discovery.devices : candidates
        guard !devices.isEmpty else { throw AudioInputError.noAudioInputDevice }

        let builtInNameHints = ["macbook", "imac", "mac studio", "mac pro", "studio display", "built-in", "built in"]
        if let match = devices.first(where: { device in
            let name = device.localizedName.lowercased()
            return builtInNameHints.contains(where: { name.contains($0) })
        }) {
            return match
        }

        let builtInIDHints = ["builtin", "built-in", "applehda", "applehdaengineinput"]
        if let match = devices.first(where: { device in
            let id = device.uniqueID.lowercased()
            return builtInIDHints.contains(where: { id.contains($0) })
        }) {
            return match
        }

        return devices[0]
    }

    private static func isLikelyVirtualOrAggregateInput(_ device: AVCaptureDevice) -> Bool {
        let name = device.localizedName.lowercased()
        let id = device.uniqueID.lowercased()
        let nameHints = [
            "aggregate", "multi-output", "multi output", "blackhole", "loopback", "soundflower",
            "vb-audio", "vb cable", "cable input", "zoom audio", "microsoft teams", "teams audio",
            "discord", "krisp", "eqmac", "rogue amoeba"
        ]
        if nameHints.contains(where: { name.contains($0) }) { return true }
        if id.contains("aggregate") || id.contains("multi-output") || id.contains("multioutput") { return true }
        return false
    }
}
