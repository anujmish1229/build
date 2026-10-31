import Foundation
#if canImport(RoomPlan)
import RoomPlan
#endif

/// Decides, when a scan is started, whether this device can scan (FR-S2).
public enum CapabilityGate {
    public enum Result: Equatable, Sendable {
        case supported
        case unsupported(reason: String)
    }

    public static let unsupportedMessage =
        "Scanning needs a LiDAR sensor, found on iPhone Pro models and iPad Pro. You can still use the rest of the app with sample rooms and rooms people send you."
    public static let simulatorMessage =
        "Scanning needs a real device with a LiDAR sensor, so it isn't available in the simulator. You can still use the rest of the app with sample rooms."

    public static func check() -> Result {
        #if targetEnvironment(simulator)
        return .unsupported(reason: simulatorMessage)
        #elseif canImport(RoomPlan)
        if #available(iOS 16.0, *), RoomCaptureSession.isSupported { return .supported }
        return .unsupported(reason: unsupportedMessage)
        #else
        return .unsupported(reason: unsupportedMessage)
        #endif
    }
}

public enum DeviceInfo {
    /// Hardware model and OS version only. Never the device's name (FR-S11).
    public static func current() -> RawDevice {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var bytes = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &bytes, &size, nil, 0)
        let model = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return RawDevice(model: model, osVersion: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
    }
}
