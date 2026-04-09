import Foundation
import AVFoundation

internal class BlackHoleAudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "DualAudioRecorder.loopback.session")
    private let sampleQueue = DispatchQueue(label: "DualAudioRecorder.loopback.samples")
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?
    
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        bufferCallback = onBuffer
        let device = try Self.preferredLoopbackDevice()
        let input = try AVCaptureDeviceInput(device: device)

        try sessionQueue.sync {
            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw AudioInputError.noLoopbackDevice
            }
            session.addInput(input)
            audioOutput.audioSettings = PCMAudio.captureSettings(for: device, defaultChannels: 2)
            audioOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            guard session.canAddOutput(audioOutput) else {
                session.removeInput(input)
                session.commitConfiguration()
                throw AudioInputError.noLoopbackDevice
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

    internal static func preferredLoopbackDevice() throws -> AVCaptureDevice {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices
        guard !devices.isEmpty else { throw AudioInputError.noLoopbackDevice }

        let rankedNameSubstrings = [
            "blackhole",
            "vb-cable",
            "vb cable",
            "vb-audio",
            "cable input",
            "soundflower",
            "loopback",
            "virtual cable",
            "wave link"
        ]

        for substring in rankedNameSubstrings {
            if let match = devices.first(where: { device in
                let name = device.localizedName.lowercased()
                guard name.contains(substring) else { return false }
                return !isAggregateOrMultiOutputName(name)
            }) {
                return match
            }
        }
        throw AudioInputError.noLoopbackDevice
    }

    private static func isAggregateOrMultiOutputName(_ name: String) -> Bool {
        name.contains("aggregate") || name.contains("multi-output") || name.contains("multi output")
    }
}
