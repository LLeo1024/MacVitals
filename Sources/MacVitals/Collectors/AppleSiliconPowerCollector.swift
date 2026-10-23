import Foundation

public final class AppleSiliconPowerCollector: @unchecked Sendable {
    public let chipName: String

    public init() {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
            self.chipName = buffer.withUnsafeBufferPointer { ptr in
                ptr.baseAddress.map { String(cString: $0) }
            } ?? "Apple Silicon"
        } else {
            self.chipName = "Apple Silicon"
        }
    }

    public struct PowerResult {
        public let packageW: Double
        public let cpuW: Double
        public let gpuW: Double
        public let aneW: Double
    }

    /// 根据 CPU 占用、供电状态与 Apple Silicon 功耗模型估算芯片各域功耗
    public func estimatePower(cpuPercent: Double, batteryPowerW: Double, isDischarging: Bool) -> PowerResult {
        let normalizedCpu = min(100.0, max(0.0, cpuPercent)) / 100.0

        // Apple Silicon (M1/M2/M3/M4) 功耗曲线参数
        // 静态基准空闲：约 1.2W ~ 2.0W
        // CPU 满载：约 15W ~ 25W (视核心数量而定)
        let baseIdleW = 1.6
        let maxCpuPowerW = chipName.contains("Max") ? 35.0 : (chipName.contains("Pro") ? 26.0 : 18.0)
        let estimatedCpuW = baseIdleW * 0.3 + pow(normalizedCpu, 1.4) * maxCpuPowerW
        let estimatedGpuW = baseIdleW * 0.2 + (normalizedCpu > 0.6 ? 2.5 : 0.4)
        let estimatedAneW = 0.1

        var packageW = baseIdleW + estimatedCpuW + estimatedGpuW + estimatedAneW

        // 若处于电池放电模式，校准整机总功耗
        if isDischarging && !batteryPowerW.isNaN && batteryPowerW > 1.0 {
            // 电池功率包含了屏幕亮度、外设等，芯片占整机约 60% ~ 75%
            packageW = min(batteryPowerW, max(packageW, batteryPowerW * 0.72))
        }

        return PowerResult(
            packageW: (packageW * 10).rounded() / 10,
            cpuW: (estimatedCpuW * 10).rounded() / 10,
            gpuW: (estimatedGpuW * 10).rounded() / 10,
            aneW: estimatedAneW
        )
    }
}
