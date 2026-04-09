import Foundation
enum AudioInputError: LocalizedError {
    case noShareableDisplay
    case missingAudioFormat
    case unsupportedAudioFormat
    case noAudioInputDevice
    case noLoopbackDevice

    var errorDescription: String? {
        switch self {
        case .noShareableDisplay:
            return "No display was available for ScreenCaptureKit."
        case .missingAudioFormat:
            return "The captured audio buffer did not include a usable format description."
        case .unsupportedAudioFormat:
            return "The captured audio buffer could not be converted into PCM."
        case .noAudioInputDevice:
            return "No physical microphone was found for capture, or the session could not be configured."
        case .noLoopbackDevice:
            return "No BlackHole or compatible loopback input was found. Install BlackHole and route system output to it (e.g. Multi-Output Device in Audio MIDI Setup)."
        }
    }
}
