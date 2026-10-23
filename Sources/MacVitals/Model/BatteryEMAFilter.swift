import Foundation

/// 连续时间指数加权移动平均（Continuous EMA）电池平滑滤波器
/// 移植自 Pulse 的核心算法，保证在任何刷新率和采样抖动下均获得完全恒定的 30 秒滤波特性。
public final class BatteryEMAFilter: @unchecked Sendable {
    private let tauSec: Double = 30.0
    private let warmupSec: Double = 60.0

    private var prevMode: PowerMode = .unknown
    private var prevTime: Date?
    private var emaWatt: Double = 0.0
    private var hasEma: Bool = false

    // 拔电统计
    private var unplugTime: Date?
    private var energyAccumWh: Double = 0.0
    private var measuredDurationSec: Double = 0.0
    private var lastRecordedWh: Double = 0.0

    public init() {}

    public struct Result {
        public let smoothedPowerW: Double
        public let etaSeconds: Double
        public let eta20Seconds: Double
        public let pctPerHour: Double
        public let onBatterySeconds: Double
        public let avgDischargeW: Double
    }

    public func update(
        now: Date = Date(),
        mode: PowerMode,
        instantWatt: Double,
        remainingWh: Double,
        fullWh: Double,
        currentPercent: Int
    ) -> Result {
        let dt = prevTime.map { now.timeIntervalSince($0) } ?? 0.0
        prevTime = now

        // 1. 判断供电模式切换（充电/放电）
        if mode != prevMode {
            hasEma = false
            emaWatt = instantWatt
            if mode == .discharging {
                unplugTime = now
                energyAccumWh = 0.0
                measuredDurationSec = 0.0
                lastRecordedWh = remainingWh
            } else {
                unplugTime = nil
            }
            prevMode = mode
        }

        // 2. 连续时间 EMA 滤波: alpha = 1 - exp(-dt / tau)
        if (mode == .discharging || mode == .charging) && instantWatt > 0 {
            if !hasEma || dt <= 0 || dt > 10.0 {
                emaWatt = instantWatt
                hasEma = true
            } else {
                let alpha = 1.0 - exp(-dt / tauSec)
                emaWatt += alpha * (instantWatt - emaWatt)
            }
        } else {
            hasEma = false
            emaWatt = 0.0
        }

        // 3. 拔电后平均功耗累计
        var onBatteryDuration: Double = .nan
        var avgWatt: Double = .nan
        if mode == .discharging, let unplug = unplugTime {
            onBatteryDuration = now.timeIntervalSince(unplug)
            if dt > 0 && dt <= 10.0 && lastRecordedWh > remainingWh {
                energyAccumWh += (lastRecordedWh - remainingWh)
            }
            lastRecordedWh = remainingWh
            if dt > 0 { measuredDurationSec += dt }

            if measuredDurationSec > warmupSec && energyAccumWh > 0 {
                let hours = measuredDurationSec / 3600.0
                avgWatt = energyAccumWh / hours
            }
        }

        // 4. 预测剩余续航与充满时间
        var eta: Double = .nan
        var eta20: Double = .nan
        var pph: Double = .nan

        if hasEma && emaWatt > 0.01 {
            if mode == .discharging && remainingWh > 0 {
                eta = (remainingWh / emaWatt) * 3600.0
                if fullWh > 0 {
                    pph = (emaWatt / fullWh) * 100.0
                    if currentPercent > 20 {
                        let reserveWh = 0.2 * fullWh
                        if remainingWh > reserveWh {
                            eta20 = ((remainingWh - reserveWh) / emaWatt) * 3600.0
                        }
                    } else {
                        eta20 = 0.0
                    }
                }
            } else if mode == .charging && fullWh > remainingWh {
                eta = ((fullWh - remainingWh) / emaWatt) * 3600.0
                if fullWh > 0 {
                    pph = (emaWatt / fullWh) * 100.0
                }
            }
        }

        return Result(
            smoothedPowerW: hasEma ? emaWatt : instantWatt,
            etaSeconds: eta,
            eta20Seconds: eta20,
            pctPerHour: pph,
            onBatterySeconds: onBatteryDuration,
            avgDischargeW: avgWatt
        )
    }

    public func reset() {
        prevMode = .unknown
        prevTime = nil
        hasEma = false
        emaWatt = 0.0
        unplugTime = nil
        energyAccumWh = 0.0
        measuredDurationSec = 0.0
    }
}
