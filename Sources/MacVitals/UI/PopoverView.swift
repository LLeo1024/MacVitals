import SwiftUI

public struct PopoverView: View {
    @ObservedObject var coordinator = MetricsCoordinator.shared

    public init() {}

    public var body: some View {
        let s = coordinator.snapshot

        VStack(spacing: 10) {
            // 顶栏 Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .bold))
                    Text("MacVitals")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                Text(s.chipName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)

                Text(formatUptime(s.uptimeSeconds))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(height: 20)

            // 1. 硬件四格 (CPU, 内存, 芯片功耗, 电池)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                // CPU 格
                StatCard(
                    title: "处理器 CPU",
                    icon: "cpu",
                    iconColor: .orange,
                    value: String(format: "%.1f%%", s.cpuPercent),
                    subtitle: "\(s.coreCount) 核心"
                ) {
                    MiniProgress(percent: s.cpuPercent / 100.0, color: .orange)
                }

                // 内存格
                StatCard(
                    title: "统一内存 RAM",
                    icon: "memorychip",
                    iconColor: .purple,
                    value: String(format: "%.1f%%", s.memPercent),
                    subtitle: String(format: "%.1f / %.0f GB", s.memUsedGB, s.memTotalGB)
                ) {
                    MiniProgress(percent: s.memPercent / 100.0, color: .purple)
                }

                // 芯片功耗格
                StatCard(
                    title: "整机/SoC 功耗",
                    icon: "bolt.fill",
                    iconColor: .yellow,
                    value: s.packageW.isNaN ? "--" : String(format: "%.1f W", s.packageW),
                    subtitle: String(format: "CPU: %.1fW | GPU: %.1fW", s.cpuW.isNaN ? 0 : s.cpuW, s.gpuW.isNaN ? 0 : s.gpuW)
                )

                // 电池电量格
                StatCard(
                    title: "电池电量",
                    icon: batteryIcon(s.powerMode, s.batteryPercent),
                    iconColor: s.batteryPercent > 20 ? .green : .red,
                    value: s.batteryPercent >= 0 ? "\(s.batteryPercent)%" : "--",
                    subtitle: s.powerMode == .acIdle
                        ? s.displayAdapterTitle
                        : (s.powerMode == .charging
                            ? "充电中 (\(s.displayAdapterTitle))"
                            : "电池放电")
                ) {
                    if s.batteryPercent >= 0 {
                        MiniProgress(percent: Double(s.batteryPercent) / 100.0, color: s.batteryPercent > 20 ? .green : .red)
                    }
                }
            }

            // 2. 电池深度预测卡片 (固定高度，防止抖动)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("电池与平滑预测", systemImage: "bolt.badge.clock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if s.powerMode == .discharging {
                        if !s.batteryPowerW.isNaN && s.batteryPowerW > 0 {
                            Text(String(format: "%.1f W", s.batteryPowerW))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                    } else if s.powerMode == .charging {
                        if !s.batteryPowerW.isNaN && s.batteryPowerW > 0 {
                            Text(String(format: "%.1f W", s.batteryPowerW))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    } else if s.powerMode == .acIdle {
                        Text(s.displayAdapterTitle)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.powerMode == .charging ? "充满预计" : (s.powerMode == .acIdle ? "供电模式" : "续航预计"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(s.powerMode == .acIdle ? "外接供电" : formatDuration(s.etaSeconds))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }

                    Divider().frame(height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.powerMode == .discharging ? "至 20% 剩余" : "实际容量")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if s.powerMode == .discharging {
                            Text(formatDuration(s.eta20Seconds))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(s.batteryPercent <= 20 ? .red : .primary)
                        } else if s.batteryFullCapMAh > 0 {
                            Text("\(s.batteryFullCapMAh) mAh")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        } else if s.batteryFullWh > 0 {
                            Text(String(format: "%.1f Wh", s.batteryFullWh))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        } else {
                            Text("--")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(s.batteryCycles >= 0 ? "循环 \(s.batteryCycles) 次" : "外接供电")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if !s.batteryHealthPercent.isNaN {
                            Text(String(format: "健康度 %.0f%%", s.batteryHealthPercent))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(s.batteryHealthPercent > 80 ? .green : .orange)
                        }
                    }
                }
            }
            .padding(8)
            .frame(height: 58)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // 3. 网络与测活卡片 (固定高度)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("物理网络 (\(s.primaryInterface))", systemImage: "network")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    NetStateBadge(state: s.netState, latency: s.latencyMs)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("下载速率")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(formatSpeed(s.downBps))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("上传速率")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(formatSpeed(s.upBps))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(8)
            .frame(height: 58)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // 4. 高占用进程前三 (固定高度 82pt，绝不上下伸缩)
            VStack(alignment: .leading, spacing: 4) {
                Text("高 CPU 占用进程")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                if s.topProcesses.isEmpty {
                    VStack {
                        Spacer()
                        Text("采样中...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(Array(s.topProcesses.prefix(3).enumerated()), id: \.element.id) { index, proc in
                        HStack {
                            Text("\(index + 1).")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 14, alignment: .leading)

                            Text(proc.name)
                                .font(.system(size: 11))
                                .lineLimit(1)

                            Spacer()

                            Text(String(format: "%.1f%%", proc.cpuPercent))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(proc.cpuPercent > 50 ? .red : (proc.cpuPercent > 20 ? .orange : .primary))
                        }
                    }
                }
            }
            .padding(8)
            .frame(height: 82)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // 5. 底部控制栏
            HStack {
                Picker("", selection: $coordinator.refreshInterval) {
                    Text("0.5s").tag(0.5)
                    Text("1.0s").tag(1.0)
                    Text("2.0s").tag(2.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: coordinator.refreshInterval) { val in
                    coordinator.updateInterval(val)
                }

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
            }
            .frame(height: 24)
        }
        .padding(12)
        .frame(width: 310, height: 430)
    }

    // 格式化辅助
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec.isNaN || bytesPerSec <= 0 { return "0 B/s" }
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.2f MB/s", bytesPerSec / (1024.0 * 1024.0))
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds.isNaN || seconds <= 0 { return "--" }
        let totalMinutes = Int(seconds) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else {
            return "\(m)m"
        }
    }

    private func formatUptime(_ seconds: Double) -> String {
        let totalHours = Int(seconds) / 3600
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 {
            return "开机 \(days)天\(hours)时"
        } else {
            return "开机 \(hours)时"
        }
    }

    private func batteryIcon(_ mode: PowerMode, _ percent: Int) -> String {
        if mode == .charging { return "battery.100.bolt" }
        if percent < 20 { return "battery.0" }
        if percent < 50 { return "battery.25" }
        if percent < 80 { return "battery.75" }
        return "battery.100"
    }
}

struct StatCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let value: String
    var subtitle: String? = nil
    var progress: Content? = nil

    init(
        title: String,
        icon: String,
        iconColor: Color,
        value: String,
        subtitle: String? = nil,
        @ViewBuilder progress: () -> Content = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.value = value
        self.subtitle = subtitle
        self.progress = progress()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))

            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let p = progress {
                p
            }
        }
        .padding(8)
        .frame(height: 64, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

struct MiniProgress: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(percent))), height: 3)
            }
        }
        .frame(height: 3)
    }
}

struct NetStateBadge: View {
    let state: NetState
    let latency: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)

            Text(stateText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(stateColor)
        }
    }

    private var stateColor: Color {
        switch state {
        case .online: return .green
        case .slow: return .orange
        case .offline: return .red
        case .checking: return .secondary
        }
    }

    private var stateText: String {
        switch state {
        case .online, .slow:
            return latency.isNaN ? state.rawValue : String(format: "%.0f ms", latency)
        case .offline:
            return "断网"
        case .checking:
            return "探测中"
        }
    }
}
