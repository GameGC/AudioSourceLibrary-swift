import Foundation
import AVFoundation

internal enum PCMAudio {
    static func MakeBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = sampleBuffer.formatDescription,
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw AudioInputError.missingAudioFormat
        }
        guard let sourceFormat = AVAudioFormat(streamDescription: streamDescription) else {
            throw AudioInputError.unsupportedAudioFormat
        }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw AudioInputError.unsupportedAudioFormat
        }
        buffer.frameLength = frameCount

        try sampleBuffer.withAudioBufferList { audioBufferList, _ in
            let sourceBuffers = audioBufferList
            let destinationBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for index in 0..<min(sourceBuffers.count, destinationBuffers.count) {
                guard let sourceData = sourceBuffers[index].mData,
                      let destinationData = destinationBuffers[index].mData
                else { continue }
                memcpy(
                    destinationData,
                    sourceData,
                    Int(min(sourceBuffers[index].mDataByteSize, destinationBuffers[index].mDataByteSize))
                )
            }
        }
        return buffer
    }
    
    static func captureSettings(for device: AVCaptureDevice, defaultChannels: Int) -> [String: Any] {
          var channels = defaultChannels
          var sampleRate = 48_000.0
          if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
              device.activeFormat.formatDescription)?.pointee {
              let c = Int(asbd.mChannelsPerFrame)
              if (1...8).contains(c) { channels = c }
              if asbd.mSampleRate > 1 { sampleRate = asbd.mSampleRate }
          }
          return [
              AVFormatIDKey: Int(kAudioFormatLinearPCM),
              AVSampleRateKey: sampleRate,
              AVNumberOfChannelsKey: channels,
              AVLinearPCMBitDepthKey: 32,
              AVLinearPCMIsFloatKey: true,
              AVLinearPCMIsNonInterleaved: true,
              AVLinearPCMIsBigEndianKey: false
          ]
      }
}
