import Foundation
import Darwin

public final class CpuMemCollector: @unchecked Sendable {
    private var prevCpuInfo: processor_info_array_t?
    private var prevCpuInfoCount: mach_msg_type_number_t = 0
    private var numCPUs: natural_t = 0

    public init() {
        var mib: [Int32] = [CTL_HW, HW_NCPU]
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctl(&mib, 2, &count, &size, nil, 0)
        self.numCPUs = natural_t(max(1, count))
    }

    deinit {
        if let prev = prevCpuInfo {
            let prevSize = vm_size_t(prevCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }
    }

    public struct CpuResult {
        public let totalUsage: Double
        public let coreUsages: [Double]
    }

    public struct MemResult {
        public let usedGB: Double
        public let totalGB: Double
        public let percent: Double
    }

    public func sampleCpu() -> CpuResult {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo = processorInfo else {
            return CpuResult(totalUsage: 0.0, coreUsages: [])
        }

        defer {
            if let prev = prevCpuInfo {
                let prevSize = vm_size_t(prevCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
            }
            prevCpuInfo = cpuInfo
            prevCpuInfoCount = processorInfoCount
            numCPUs = processorCount
        }

        guard let prev = prevCpuInfo else {
            return CpuResult(totalUsage: 0.0, coreUsages: Array(repeating: 0.0, count: Int(processorCount)))
        }

        var totalUser: Int64 = 0
        var totalSystem: Int64 = 0
        var totalIdle: Int64 = 0
        var totalNice: Int64 = 0
        var coreUsages: [Double] = []

        for i in 0..<Int(processorCount) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = Int64(cpuInfo[offset + Int(CPU_STATE_USER)] - prev[offset + Int(CPU_STATE_USER)])
            let system = Int64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)] - prev[offset + Int(CPU_STATE_SYSTEM)])
            let idle = Int64(cpuInfo[offset + Int(CPU_STATE_IDLE)] - prev[offset + Int(CPU_STATE_IDLE)])
            let nice = Int64(cpuInfo[offset + Int(CPU_STATE_NICE)] - prev[offset + Int(CPU_STATE_NICE)])

            totalUser += user
            totalSystem += system
            totalIdle += idle
            totalNice += nice

            let coreTotal = user + system + idle + nice
            let coreUsage = coreTotal > 0 ? Double(user + system + nice) / Double(coreTotal) * 100.0 : 0.0
            coreUsages.append(min(100.0, max(0.0, coreUsage)))
        }

        let overallTotal = totalUser + totalSystem + totalIdle + totalNice
        let overallUsage = overallTotal > 0 ? Double(totalUser + totalSystem + totalNice) / Double(overallTotal) * 100.0 : 0.0

        return CpuResult(totalUsage: min(100.0, max(0.0, overallUsage)), coreUsages: coreUsages)
    }

    public func sampleMemory() -> MemResult {
        var size = MemoryLayout<UInt64>.size
        var totalRamBytes: UInt64 = 0
        sysctlbyname("hw.memsize", &totalRamBytes, &size, nil, 0)
        let totalGB = Double(totalRamBytes) / (1024.0 * 1024.0 * 1024.0)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            return MemResult(usedGB: 0.0, totalGB: totalGB, percent: 0.0)
        }

        let pageSize = Double(getpagesize())
        let active = Double(vmStats.active_count) * pageSize
        let wired = Double(vmStats.wire_count) * pageSize
        let compressed = Double(vmStats.compressor_page_count) * pageSize

        let usedBytes = active + wired + compressed
        let usedGB = usedBytes / (1024.0 * 1024.0 * 1024.0)
        let percent = totalGB > 0 ? min(100.0, (usedGB / totalGB) * 100.0) : 0.0

        return MemResult(usedGB: usedGB, totalGB: totalGB, percent: percent)
    }

    public func uptime() -> Double {
        return ProcessInfo.processInfo.systemUptime
    }
}
