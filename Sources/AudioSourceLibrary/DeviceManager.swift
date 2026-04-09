//
//  File.swift
//  
//
//  Created by user on 4/9/26.
//

import Foundation
import AVFoundation
public enum DeviceManager {
    
    public static func listSelectableMicrophones() -> [AudioInputDeviceOption] {
        return MicrophoneCapture.listSelectableMicrophones()
    }
    public static var microphonePermissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static var screenCapturePermissionGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    public static func requestScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }
}
