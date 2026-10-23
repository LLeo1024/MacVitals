import Foundation
import AppKit

@MainActor
public final class MetricsCoordinator: ObservableObject {
    public static let shared = MetricsCoordinator()

    @Published public private(set) var snapshot = PulseSnapshot()
    @Published public var wants = PulseWants()
    @Published public var refreshInterval: TimeInterval = 1.0

    private let cpuMemCollector = CpuMemCollector()
    private let batteryCollector = BatteryCollector()
    private let networkCollector = NetworkCollector()
    private let processCollector = ProcessCollector()
    private let powerCollector = AppleSiliconPowerCollector()

    private var samplingTask: Task<Void, Never>?
    private var isPaused = false

    private init() {
        setupSleepWakeObservers()
        start()
    }

    public func start() {
        stop()
        samplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                if !self.isPaused {
                    await self.performSample()
                }
                let nanos = UInt64(max(0.2, self.refreshInterval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    public func stop() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    public func updateInterval(_ interval: TimeInterval) {
        self.refreshInterval = interval
        start()
    }

    public func setPaused(_ paused: Bool) {
        self.isPaused = paused
    }

    private func performSample() async {
        let currentWants = self.wants
        let cpuMem = self.cpuMemCollector
        let battery = self.batteryCollector
        let network = self.networkCollector
        let process = self.processCollector
        let power = self.powerCollector

        // 耗时/底层内核调用转入 utility 后台任务
        let detachedTask = Task.detached(priority: .utility) { () -> PulseSnapshot in
            var newSnap = PulseSnapshot()
            newSnap.chipName = power.chipName
            newSnap.uptimeSeconds = cpuMem.uptime()

            // 1. CPU & 内存
            let cpuRes = cpuMem.sampleCpu()
            newSnap.cpuPercent = cpuRes.totalUsage
            newSnap.coreCount = cpuRes.coreUsages.count
            if currentWants.perCoreUsage {
                newSnap.coreUsages = cpuRes.coreUsages
            }

            let memRes = cpuMem.sampleMemory()
            newSnap.memPercent = memRes.percent
            newSnap.memUsedGB = memRes.usedGB
            newSnap.memTotalGB = memRes.totalGB

            // 2. 电池采样
            var isDischarging = false
            var batPowerW = Double.nan
            if currentWants.battery {
                let (rawBat, filterRes) = battery.sample()
                newSnap.powerMode = rawBat.mode
                newSnap.batteryPercent = rawBat.percent
                newSnap.batteryPowerW = filterRes.smoothedPowerW
                newSnap.etaSeconds = filterRes.etaSeconds
                newSnap.eta20Seconds = filterRes.eta20Seconds
                newSnap.pctPerHour = filterRes.pctPerHour
                newSnap.onBatterySeconds = filterRes.onBatterySeconds
                newSnap.avgDischargeW = filterRes.avgDischargeW
                newSnap.batteryRemainingWh = rawBat.remainingWh
                newSnap.batteryFullWh = rawBat.fullWh
                newSnap.batteryHealthPercent = rawBat.healthPercent
                newSnap.batteryCycles = rawBat.cycles
                newSnap.batteryDesignCapMAh = rawBat.designCapMAh
                newSnap.batteryFullCapMAh = rawBat.fullCapMAh
                newSnap.batteryRemainingMAh = rawBat.remainingMAh
                newSnap.adapterWatts = rawBat.adapterWatts
                newSnap.adapterName = rawBat.adapterName
                newSnap.voltageMV = rawBat.voltageMV

                isDischarging = (rawBat.mode == .discharging)
                batPowerW = filterRes.smoothedPowerW
            }

            // 3. Apple Silicon 芯片功耗
            if currentWants.chipPower {
                let powerRes = power.estimatePower(
                    cpuPercent: cpuRes.totalUsage,
                    batteryPowerW: batPowerW,
                    isDischarging: isDischarging
                )
                newSnap.packageW = powerRes.packageW
                newSnap.cpuW = powerRes.cpuW
                newSnap.gpuW = powerRes.gpuW
                newSnap.aneW = powerRes.aneW
            }

            // 4. 网速
            if currentWants.networkSpeed {
                let netRes = network.sampleSpeed()
                newSnap.downBps = netRes.downBps
                newSnap.upBps = netRes.upBps
                newSnap.totalRxBytes = netRes.totalRx
                newSnap.totalTxBytes = netRes.totalTx
                newSnap.primaryInterface = netRes.primaryIf
            }

            // 5. 高占用进程
            if currentWants.processes {
                newSnap.topProcesses = process.sampleTopProcesses(limit: 3)
            }

            return newSnap
        }

        var snapshotResult = await detachedTask.value
        snapshotResult.latencyMs = self.snapshot.latencyMs
        snapshotResult.netState = self.snapshot.netState
        self.snapshot = snapshotResult

        // 6. 网络测活探针 (异步触发)
        if currentWants.networkProbe {
            network.triggerProbe { [weak self] latency, state in
                Task { @MainActor [weak self] in
                    self?.snapshot.latencyMs = latency
                    self?.snapshot.netState = state
                }
            }
        }
    }

    private func setupSleepWakeObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setPaused(true)
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.batteryCollector.resetFilter()
                self?.setPaused(false)
            }
        }
    }
}
