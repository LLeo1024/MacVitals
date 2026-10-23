import Foundation

public struct PulseWants: Sendable, Equatable {
    public var chipPower: Bool = true       // 读取芯片功耗 (SoC / Package)
    public var battery: Bool = true         // 电池详情与充放电平滑预测
    public var processes: Bool = true       // 扫描 CPU 前三进程
    public var networkSpeed: Bool = true    // 统计网速
    public var networkProbe: Bool = true    // 测活 HTTP HEAD 延迟与断网状态
    public var perCoreUsage: Bool = true    // 计算各核心占用

    public init() {}
}
