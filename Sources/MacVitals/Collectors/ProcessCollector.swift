import Foundation
import AppKit
import Darwin

public final class ProcessCollector: @unchecked Sendable {
    private struct ProcRecord {
        let cpuTimeNs: UInt64
        let sampleTime: Date
    }

    private var prevTimes: [pid_t: ProcRecord] = [:]
    private let selfPid = ProcessInfo.processInfo.processIdentifier

    public init() {}

    public func sampleTopProcesses(limit: Int = 3) -> [ProcUsage] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let count = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let actualBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualBytes > 0 else { return [] }

        let actualCount = Int(actualBytes) / MemoryLayout<pid_t>.size
        let now = Date()

        var currentRecords: [pid_t: (name: String, totalTimeNs: UInt64)] = [:]
        currentRecords.reserveCapacity(actualCount)

        for i in 0..<actualCount {
            let pid = pids[i]
            if pid <= 0 || pid == selfPid { continue }

            var taskInfo = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            let bytesWritten = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)

            if bytesWritten == size {
                let totalNs = taskInfo.pti_total_user + taskInfo.pti_total_system
                let friendlyName = resolveFriendlyName(pid: pid)
                if !friendlyName.isEmpty {
                    currentRecords[pid] = (friendlyName, totalNs)
                }
            }
        }

        var usages: [ProcUsage] = []
        usages.reserveCapacity(currentRecords.count)

        for (pid, record) in currentRecords {
            if let prev = prevTimes[pid] {
                let dt = now.timeIntervalSince(prev.sampleTime)
                if dt > 0.1 && record.totalTimeNs >= prev.cpuTimeNs {
                    let deltaNs = Double(record.totalTimeNs - prev.cpuTimeNs)
                    let cpuSeconds = deltaNs / 1_000_000_000.0
                    let percent = (cpuSeconds / dt) * 100.0
                    if percent > 0.1 {
                        usages.append(ProcUsage(pid: Int(pid), name: record.name, cpuPercent: percent))
                    }
                }
            }
            prevTimes[pid] = ProcRecord(cpuTimeNs: record.totalTimeNs, sampleTime: now)
        }

        // 清理已退出的 PID
        if prevTimes.count > currentRecords.count * 2 {
            let activeSet = Set(currentRecords.keys)
            prevTimes = prevTimes.filter { activeSet.contains($0.key) }
        }

        usages.sort { $0.cpuPercent > $1.cpuPercent }
        return Array(usages.prefix(limit))
    }

    /// 解析用户友好的应用程序名称
    private func resolveFriendlyName(pid: pid_t) -> String {
        // 1. 优先获取 macOS 原生 GUI 应用程序名称 (如: "微信", "Google Chrome", "访达", "Safari", "Xcode")
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName, !name.isEmpty {
            return name
        }

        // 2. 检查可执行文件完整路径，如果位于 .app 内部 (如 Helper / 渲染子进程)
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        if pathLen > 0 {
            let fullPath = pathBuffer.withUnsafeBufferPointer { ptr in
                ptr.baseAddress.map { String(cString: $0) }
            } ?? ""

            // 如果路径包含类似 /Applications/XXX.app/Contents/...，提取主 App 名
            if let appRange = fullPath.range(of: ".app") {
                let prefix = fullPath[..<appRange.lowerBound]
                if let lastSlash = prefix.lastIndex(of: "/") {
                    let appName = String(prefix[prefix.index(after: lastSlash)...])
                    if !appName.isEmpty {
                        let binaryName = (fullPath as NSString).lastPathComponent
                        if binaryName.contains("Helper") || binaryName.contains("XPCHelper") {
                            return "\(appName) (辅助进程)"
                        }
                        return appName
                    }
                }
            }

            // 非 .app 的常规二进制服务 (如 WindowServer, node, zsh, cloudd)
            let lastComponent = (fullPath as NSString).lastPathComponent
            if !lastComponent.isEmpty {
                return cleanDaemonName(lastComponent)
            }
        }

        // 3. 兜底回退到 proc_name
        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let fallback = nameBuffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress.map { String(cString: $0) }
        } ?? ""

        return fallback.isEmpty ? "PID \(pid)" : cleanDaemonName(fallback)
    }

    private func cleanDaemonName(_ raw: String) -> String {
        switch raw {
        case "WindowServer": return "窗口渲染 (WindowServer)"
        case "com.apple.WebKit.WebContent": return "网页渲染 (WebKit)"
        case "mds", "mds_stores", "mdworker_shared": return "聚焦搜索 (Spotlight)"
        case "kernel_task": return "系统内核 (kernel_task)"
        case "coreaudiod": return "音频核心 (coreaudiod)"
        case "Finder": return "访达 (Finder)"
        default: return raw
        }
    }
}
