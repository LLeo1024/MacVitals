import Foundation
import IOKit
import IOKit.ps

public final class BatteryCollector: @unchecked Sendable {
    private let filter = BatteryEMAFilter()

    public init() {}

    public struct RawReading {
        public var hasBattery: Bool = false
        public var mode: PowerMode = .noBattery
        public var percent: Int = -1
        public var instantWatt: Double = 0.0
        public var remainingWh: Double = 0.0
        public var fullWh: Double = 0.0
        public var cycles: Int = -1
        public var healthPercent: Double = .nan
        public var designCapMAh: Int = -1
        public var fullCapMAh: Int = -1
        public var remainingMAh: Int = -1
        public var adapterWatts: Int = 0
        public var adapterName: String = ""
        public var voltageMV: Double = 0.0
    }

    public func sample() -> (RawReading, BatteryEMAFilter.Result) {
        var raw = RawReading()

        // 1. 尝试从 AppleSmartBattery IORegistry 读取精准硬件数值
        var entry: io_registry_entry_t = 0
        if #available(macOS 12.0, *) {
            entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        } else {
            entry = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
        }

        if entry != 0 {
            defer { IOObjectRelease(entry) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                raw.hasBattery = true
                let bd = dict["BatteryData"] as? [String: Any]

                let isConnected = (dict["ExternalConnected"] as? Bool) ?? false
                let isCharging = (dict["IsCharging"] as? Bool) ?? false

                if !isConnected {
                    raw.mode = .discharging
                } else if isCharging {
                    raw.mode = .charging
                } else {
                    raw.mode = .acIdle
                }

                // 电量百分比 (0..100)
                let currentPct = (dict["CurrentCapacity"] as? Int) ?? (bd?["CurrentCapacity"] as? Int) ?? -1
                raw.percent = currentPct

                // 循环次数
                raw.cycles = (dict["CycleCount"] as? Int) ?? (bd?["CycleCount"] as? Int) ?? -1

                // 电池健康度：优先使用系统最大容量百分比 (匹配系统设置「电池健康」100%)
                let maxCapPct = (dict["MaxCapacity"] as? Double) ?? (bd?["MaxCapacity"] as? Double) ?? .nan
                if !maxCapPct.isNaN && maxCapPct > 0 && maxCapPct <= 100 {
                    raw.healthPercent = maxCapPct
                }

                // 电压 (mV)
                let voltageMV = (dict["Voltage"] as? Double) ?? (bd?["Voltage"] as? Double) ?? 0.0
                raw.voltageMV = voltageMV

                // 物理电量 (mAh) - 深度兼容 Apple Silicon (BatteryData) 与传统结构
                let remMAh = (bd?["RemainingCapacity"] as? Double)
                    ?? (dict["AppleRawCurrentCapacity"] as? Double)
                    ?? (dict["CurrentCapacity"] as? Double ?? 0.0)
                let fccMAh = (bd?["FullChargeCapacity"] as? Double)
                    ?? (dict["AppleRawMaxCapacity"] as? Double)
                    ?? (dict["FullChargeCapacity"] as? Double ?? 0.0)
                let designMAh = (bd?["DesignCapacity"] as? Double)
                    ?? (dict["DesignCapacity"] as? Double ?? 0.0)

                raw.remainingMAh = Int(remMAh)
                raw.fullCapMAh = Int(fccMAh)
                raw.designCapMAh = Int(designMAh)

                // 若之前 healthPercent 为 NaN，则用物理设计容量计算
                if raw.healthPercent.isNaN && designMAh > 0 && fccMAh > 0 {
                    raw.healthPercent = min(100.0, max(0.0, (fccMAh / designMAh) * 100.0))
                }

                // 真实能量 (Wh) 计算：确保使用真实 mAh 计算，而非百分比数字
                if fccMAh > 100 && voltageMV > 0 {
                    raw.remainingWh = (remMAh * voltageMV) / 1_000_000.0
                    raw.fullWh = (fccMAh * voltageMV) / 1_000_000.0
                } else if raw.percent >= 0 {
                    // 降级兜底估算：标准电池约 54 Wh
                    let estFullWh = 54.0
                    raw.fullWh = estFullWh
                    raw.remainingWh = (Double(raw.percent) / 100.0) * estFullWh
                }

                // 充放电实时功率 (W)
                if raw.mode == .acIdle {
                    // 外接供电且非充电状态下，系统由电源适配器供电，电池自身净电流为 0
                    raw.instantWatt = 0.0
                } else {
                    // 优先从 BatteryData.BatteryPower (毫瓦) 读取硬件直接测量的电池功率
                    if let batPowerMW = (bd?["BatteryPower"] as? NSNumber)?.doubleValue, abs(batPowerMW) > 0 {
                        raw.instantWatt = abs(batPowerMW) / 1000.0
                    } else if voltageMV > 0 {
                        let ampMA = (dict["InstantAmperage"] as? NSNumber)?.doubleValue
                            ?? (dict["Amperage"] as? NSNumber)?.doubleValue
                            ?? 0.0
                        raw.instantWatt = abs(voltageMV * ampMA) / 1_000_000.0
                    }
                }

                // 外接适配器信息 (动态识别当前插入的任意适配器，如 30W/65W/70W/96W/140W 等)
                if let adapter = dict["AdapterDetails"] as? [String: Any] {
                    raw.adapterWatts = (adapter["Watts"] as? Int) ?? 0
                    raw.adapterName = (adapter["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
            }
        }

        // 2. 如果未读取到，降级回 IOPowerSources 公开接口
        if !raw.hasBattery {
            if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
               !sources.isEmpty {
                for ps in sources {
                    if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] {
                        raw.hasBattery = true
                        let state = (desc[kIOPSPowerSourceStateKey] as? String) ?? ""
                        let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false

                        if state == kIOPSBatteryPowerValue {
                            raw.mode = .discharging
                        } else if isCharging {
                            raw.mode = .charging
                        } else {
                            raw.mode = .acIdle
                        }

                        let cur = (desc[kIOPSCurrentCapacityKey] as? Int) ?? -1
                        let maxCapVal = (desc[kIOPSMaxCapacityKey] as? Int) ?? 100
                        raw.percent = maxCapVal > 0 && cur >= 0 ? Int(round(Double(cur) / Double(maxCapVal) * 100.0)) : cur

                        let estFullWh = 54.0
                        raw.fullWh = estFullWh
                        raw.remainingWh = (Double(max(0, raw.percent)) / 100.0) * estFullWh
                        raw.instantWatt = (raw.mode == .acIdle) ? 0.0 : 5.0
                        break
                    }
                }
            }
        }

        // 3. 运行连续时间 EMA 平滑
        let filterResult = filter.update(
            mode: raw.mode,
            instantWatt: raw.instantWatt,
            remainingWh: raw.remainingWh,
            fullWh: raw.fullWh,
            currentPercent: raw.percent
        )

        return (raw, filterResult)
    }

    public func resetFilter() {
        filter.reset()
    }
}
