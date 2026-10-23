import Foundation
import Darwin

public final class NetworkCollector: @unchecked Sendable {
    private var prevRxBytes: UInt64 = 0
    private var prevTxBytes: UInt64 = 0
    private var prevSampleTime: Date?
    private var primaryIfName: String = "en0"

    // 测活探针配置 (采用原生 HTTPS + 苹果官方与国内高可用 CDN 端点)
    private let probeUrls: [URL] = [
        URL(string: "https://captive.apple.com/hotspot-detect.html")!,
        URL(string: "https://www.baidu.com")!,
        URL(string: "https://www.apple.com/library/test/success.html")!,
        URL(string: "https://www.msftconnecttest.com/connecttest.txt")!
    ]
    private var currentProbeIndex = 0
    private var failCount = 0
    private let failThreshold = 3
    private var lastLatencyMs: Double = .nan
    private var lastNetState: NetState = .online // 默认初始化为在线，防止启动瞬间误显断网
    private var isProbing = false
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 2.5
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    public struct NetSpeedResult {
        public let downBps: Double
        public let upBps: Double
        public let totalRx: UInt64
        public let totalTx: UInt64
        public let primaryIf: String
    }

    public func sampleSpeed() -> NetSpeedResult {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return NetSpeedResult(downBps: 0, upBps: 0, totalRx: prevRxBytes, totalTx: prevTxBytes, primaryIf: primaryIfName)
        }
        defer { freeifaddrs(ifaddr) }

        var currentTotalRx: UInt64 = 0
        var currentTotalTx: UInt64 = 0
        var bestIfName = primaryIfName

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)

            // 过滤：必须处于 UP 和 RUNNING 状态，排除回环接口 (LOOPBACK)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            // macOS 上物理网卡通常是 en0, en1 等
            if isUp && isRunning && !isLoopback && name.hasPrefix("en") {
                if let data = current.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self)
                    currentTotalRx += UInt64(ifData.pointee.ifi_ibytes)
                    currentTotalTx += UInt64(ifData.pointee.ifi_obytes)
                    bestIfName = name
                }
            }
            ptr = current.pointee.ifa_next
        }

        self.primaryIfName = bestIfName
        let now = Date()
        let dt = prevSampleTime.map { now.timeIntervalSince($0) } ?? 0.0
        prevSampleTime = now

        var downBps = 0.0
        var upBps = 0.0

        if dt > 0 && dt <= 10.0 && prevRxBytes > 0 {
            if currentTotalRx >= prevRxBytes {
                downBps = Double(currentTotalRx - prevRxBytes) / dt
            }
            if currentTotalTx >= prevTxBytes {
                upBps = Double(currentTotalTx - prevTxBytes) / dt
            }
        }

        prevRxBytes = currentTotalRx
        prevTxBytes = currentTotalTx

        // 核心保护：若物理网卡当前有实质性上下行流量，说明网络绝对连通，重置失败计数
        if downBps > 512.0 || upBps > 512.0 {
            failCount = 0
            if lastNetState == .offline {
                lastNetState = .online
            }
        }

        return NetSpeedResult(
            downBps: downBps,
            upBps: upBps,
            totalRx: currentTotalRx,
            totalTx: currentTotalTx,
            primaryIf: bestIfName
        )
    }

    /// 异步执行 HTTP 延迟探测与断网状态机更新
    public func triggerProbe(completion: @escaping @Sendable (Double, NetState) -> Void) {
        guard !isProbing else {
            completion(lastLatencyMs, lastNetState)
            return
        }

        let url = probeUrls[currentProbeIndex % probeUrls.count]
        currentProbeIndex += 1
        isProbing = true

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // 仅请求前 128 字节，避免下载多余数据同时完全兼容所有 CDN 反爬规则
        request.setValue("bytes=0-128", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let start = DispatchTime.now()
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            self.isProbing = false

            let end = DispatchTime.now()
            let elapsedNs = end.uptimeNanoseconds - start.uptimeNanoseconds
            let elapsedMs = Double(elapsedNs) / 1_000_000.0

            let success = (error == nil) && (response as? HTTPURLResponse).map {
                (200...206).contains($0.statusCode) || $0.statusCode == 301 || $0.statusCode == 302
            } ?? false

            DispatchQueue.main.async {
                if success {
                    self.failCount = 0
                    self.lastLatencyMs = elapsedMs
                    self.lastNetState = (elapsedMs > 500.0) ? .slow : .online
                } else {
                    self.failCount += 1
                    if self.failCount >= self.failThreshold {
                        self.lastLatencyMs = .nan
                        self.lastNetState = .offline
                    }
                }
                completion(self.lastLatencyMs, self.lastNetState)
            }
        }
        task.resume()
    }
}
