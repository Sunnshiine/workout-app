import Darwin
import Foundation

/// The phone a press ran on and the state it was in, which latency and accuracy vary with.
struct DeviceFacts: Equatable, Sendable, Codable {
    enum Thermal: String, Equatable, Sendable, Codable {
        case nominal, fair, serious, critical
    }

    /// The hardware identifier, as "iPhone17,1".
    let model: String
    let os: String
    let thermal: Thermal
    let lowPower: Bool
    /// The app's physical memory footprint.
    let footprintMB: Int

    static func current() -> DeviceFacts {
        let process = ProcessInfo.processInfo
        let version = process.operatingSystemVersion
        return DeviceFacts(
            model: process.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardwareModel(),
            os: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            thermal: Thermal(process.thermalState),
            lowPower: process.isLowPowerModeEnabled,
            footprintMB: Int(footprintBytes() / 1_048_576)
        )
    }

    private static func hardwareModel() -> String {
        #if os(macOS)
            let name = "hw.model"
        #else
            let name = "hw.machine"
        #endif
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
    }

    private static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

extension DeviceFacts.Thermal {
    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}
