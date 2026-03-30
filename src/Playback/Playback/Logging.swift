import Foundation
import os
import Darwin

enum Log {
    static let recording   = Logger(subsystem: "com.falconer.Playback", category: "Recording")
    static let processing  = Logger(subsystem: "com.falconer.Playback", category: "Processing")
    static let playback    = Logger(subsystem: "com.falconer.Playback", category: "Playback")
    static let timeline    = Logger(subsystem: "com.falconer.Playback", category: "Timeline")
    static let ui          = Logger(subsystem: "com.falconer.Playback", category: "UI")
    static let menuBar     = Logger(subsystem: "com.falconer.Playback", category: "MenuBar")
    static let hotkey      = Logger(subsystem: "com.falconer.Playback", category: "Hotkey")
    static let config      = Logger(subsystem: "com.falconer.Playback", category: "Config")
    static let system      = Logger(subsystem: "com.falconer.Playback", category: "System")
    static let session     = Logger(subsystem: "com.falconer.Playback", category: "Session")
    static let settings    = Logger(subsystem: "com.falconer.Playback", category: "Settings")
    static let datepicker  = Logger(subsystem: "com.falconer.Playback", category: "DatePicker")
    static let memory      = Logger(subsystem: "com.falconer.Playback", category: "Memory")
}

/// Lightweight memory stats sampled from Mach task info.
struct MemoryStats {
    let residentMB: Double
    let footprintMB: Double

    /// Samples current process memory using task_info.
    static func current() -> MemoryStats {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rawPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return MemoryStats(residentMB: -1, footprintMB: -1)
        }
        let residentMB = Double(info.resident_size) / 1_048_576.0
        // phys_footprint via task_vm_info for actual memory pressure contribution
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let vmKr = withUnsafeMutablePointer(to: &vmInfo) { vmPtr in
            vmPtr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rawPtr, &vmCount)
            }
        }
        let footprintMB: Double
        if vmKr == KERN_SUCCESS {
            footprintMB = Double(vmInfo.phys_footprint) / 1_048_576.0
        } else {
            footprintMB = residentMB
        }
        return MemoryStats(residentMB: residentMB, footprintMB: footprintMB)
    }

    var description: String {
        String(format: "resident=%.1fMB footprint=%.1fMB", residentMB, footprintMB)
    }
}
