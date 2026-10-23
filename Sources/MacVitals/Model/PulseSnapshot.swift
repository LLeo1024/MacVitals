import Foundation

public enum PowerMode: String, Sendable {
    case unknown = "未知"
    case noBattery = "无电池"
    case discharging = "放电中"
    case charging = "充电中"
    case acIdle = "外接电源"
}

public enum NetState: String, Sendable {
    case checking = "探测中"
    case online = "在线"
    case slow = "延迟较高"
    case offline = "断网"
}

public struct ProcUsage: Identifiable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let cpuPercent: Double
    
    public init(pid: Int, name: String, cpuPercent: Double) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
    }
}

public struct PulseSnapshot: Sendable {
    // 电池与电源
    public var powerMode: PowerMode = .unknown
    public var batteryPercent: Int = -1               // 0..100
    public var batteryPowerW: Double = .nan           // 充放电实时功率 (正值)
    public var etaSeconds: Double = .nan             // 放电：预计剩余秒数；充电：预计充满秒数
    public var eta20Seconds: Double = .nan           // 放电时预计到达 20% 的秒数
    public var pctPerHour: Double = .nan             // 每小时耗电 / 充入百分比
    public var onBatterySeconds: Double = .nan       // 拔掉电源后持续的时间（秒）
    public var avgDischargeW: Double = .nan          // 拔电后平均放电功率
    public var batteryRemainingWh: Double = .nan
    public var batteryFullWh: Double = .nan
    public var batteryHealthPercent: Double = .nan   // 最大容量 / 设计容量 * 100
    public var batteryCycles: Int = -1
    public var batteryDesignCapMAh: Int = -1
    public var batteryFullCapMAh: Int = -1
    public var batteryRemainingMAh: Int = -1
    public var adapterWatts: Int = 0
    public var adapterName: String = ""
    public var voltageMV: Double = 0.0

    /// 动态格式化当前插入的任意适配器（如 30W/65W/70W/96W/140W 或显示器 Type-C 供电）
    public var displayAdapterTitle: String {
        if !adapterName.isEmpty {
            if let match = adapterName.range(of: #"\d+W"#, options: .regularExpression) {
                let nominal = String(adapterName[match])
                if adapterWatts > 0 && String(adapterWatts) + "W" != nominal {
                    return "\(nominal) 适配器 (\(adapterWatts)W)"
                } else {
                    return "\(nominal) 适配器"
                }
            }
            return "\(adapterWatts)W 适配器"
        } else if adapterWatts > 0 {
            return "\(adapterWatts)W 适配器"
        } else {
            return "外接供电"
        }
    }

    // 芯片与整机功耗 (Apple Silicon / SoC)
    public var packageW: Double = .nan               // 整芯片 / 整机实时瓦数
    public var cpuW: Double = .nan                   // CPU 核心瓦数
    public var gpuW: Double = .nan                   // GPU 核心瓦数
    public var aneW: Double = .nan                   // ANE 神经网络引擎瓦数

    // CPU 与内存
    public var cpuPercent: Double = 0.0              // 总占用率 (0..100)
    public var coreCount: Int = 0
    public var coreUsages: [Double] = []             // 各物理/能效核心占用
    public var memPercent: Double = 0.0              // 内存占用率 (0..100)
    public var memUsedGB: Double = 0.0
    public var memTotalGB: Double = 0.0

    // 网络
    public var downBps: Double = 0.0                 // 下载速率 (Bytes/s)
    public var upBps: Double = 0.0                   // 上传速率 (Bytes/s)
    public var totalRxBytes: UInt64 = 0
    public var totalTxBytes: UInt64 = 0
    public var netState: NetState = .checking
    public var latencyMs: Double = .nan              // HTTP HEAD 真实探测延迟
    public var primaryInterface: String = "en0"

    // 高占用进程
    public var topProcesses: [ProcUsage] = []        // CPU 前三名进程

    // 系统基础
    public var uptimeSeconds: Double = 0
    public var chipName: String = "Apple Silicon"

    public init() {}
}
