import Foundation
import AVFoundation
import ScreenCaptureKit

internal class SystemAudioCapture: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "DualAudioRecorder.system-audio")
    private let onBuffer: (AVAudioPCMBuffer) -> Void
    private let onFailure: (Error) -> Void

    init(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.onBuffer = onBuffer
        self.onFailure = onFailure
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = Self.preferredDisplay(from: content) else {
            throw AudioInputError.noShareableDisplay
        }

        let excludedApps = content.applications.filter { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 44_100
        configuration.channelCount = 1
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        configuration.width = 2
        configuration.height = 2
        configuration.showsCursor = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        Task {
            try? await stream.stopCapture()
        }
        self.stream = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(error)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        do {
            let buffer = try PCMAudio.MakeBuffer(from: sampleBuffer)
            onBuffer(buffer)
        } catch {
            onFailure(error)
        }
    }

    private static func preferredDisplay(from content: SCShareableContent) -> SCDisplay? {
        guard let mainScreenNumber = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return content.displays.first
        }
        let mainDisplayID = CGDirectDisplayID(mainScreenNumber.uint32Value)
        return content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first
    }
}
