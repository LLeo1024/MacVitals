import AppKit
import SwiftUI
import Combine

public enum StatusItemFontSize: Double, CaseIterable {
    case compact = 9.0
    case standard = 9.5
    case large = 10.5

    var title: String {
        switch self {
        case .compact: return "紧凑 (9.0 pt)"
        case .standard: return "标准 (9.5 pt)"
        case .large: return "放大 (10.5 pt)"
        }
    }

    var itemWidth: CGFloat {
        switch self {
        case .compact: return 100.0
        case .standard: return 106.0
        case .large: return 116.0
        }
    }
}

@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var statusView: StatusItemView!
    private var cancellables = Set<AnyCancellable>()

    // 用户可选文字大小，默认标准 9.5pt
    private var currentFontSize: StatusItemFontSize = .standard

    public override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        observeMetrics()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: currentFontSize.itemWidth)
        statusView = StatusItemView(frame: NSRect(x: 0, y: 0, width: currentFontSize.itemWidth, height: 22))
        statusView.fontSize = CGFloat(currentFontSize.rawValue)

        if let button = statusItem.button {
            button.addSubview(statusView)
            statusView.frame = button.bounds
            statusView.autoresizingMask = [.width, .height]

            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 310, height: 430)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PopoverView())
    }

    private func observeMetrics() {
        MetricsCoordinator.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                self?.statusView.updateSnapshot(snap)
            }
            .store(in: &cancellables)
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    public func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentSize = NSSize(width: 310, height: 430)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            if let popoverWindow = popover.contentViewController?.view.window {
                popoverWindow.makeKey()
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // 1. 文字大小调节菜单
        let fontMenu = NSMenu()
        for size in StatusItemFontSize.allCases {
            let item = NSMenuItem(title: size.title, action: #selector(changeFontSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            if currentFontSize == size {
                item.state = .on
            }
            fontMenu.addItem(item)
        }
        let fontItem = NSMenuItem(title: "状态栏字号", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        // 2. 刷新频率切换
        let refreshMenu = NSMenu()
        let intervals: [(String, TimeInterval)] = [("0.5 秒 (快速)", 0.5), ("1.0 秒 (默认)", 1.0), ("2.0 秒 (极省电)", 2.0)]
        for (title, sec) in intervals {
            let item = NSMenuItem(title: title, action: #selector(changeRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sec
            if MetricsCoordinator.shared.refreshInterval == sec {
                item.state = .on
            }
            refreshMenu.addItem(item)
        }
        let refreshItem = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        refreshItem.submenu = refreshMenu
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // 3. 指标开关
        let wants = MetricsCoordinator.shared.wants
        let togglePower = NSMenuItem(title: "芯片功耗", action: #selector(toggleChipPower), keyEquivalent: "")
        togglePower.target = self
        togglePower.state = wants.chipPower ? .on : .off
        menu.addItem(togglePower)

        let toggleProc = NSMenuItem(title: "高占用进程扫描", action: #selector(toggleProcesses), keyEquivalent: "")
        toggleProc.target = self
        toggleProc.state = wants.processes ? .on : .off
        menu.addItem(toggleProc)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 MacVitals", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func changeFontSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Double,
              let size = StatusItemFontSize(rawValue: raw) else { return }
        self.currentFontSize = size
        self.statusItem.length = size.itemWidth
        self.statusView.fontSize = CGFloat(size.rawValue)
        self.statusView.frame = NSRect(x: 0, y: 0, width: size.itemWidth, height: 22)
        self.statusView.needsDisplay = true
    }

    @objc private func changeRefreshInterval(_ sender: NSMenuItem) {
        if let sec = sender.representedObject as? TimeInterval {
            MetricsCoordinator.shared.updateInterval(sec)
        }
    }

    @objc private func toggleChipPower() {
        MetricsCoordinator.shared.wants.chipPower.toggle()
    }

    @objc private func toggleProcesses() {
        MetricsCoordinator.shared.wants.processes.toggle()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// 菜单栏紧凑型双行手绘渲染 View
@MainActor
final class StatusItemView: NSView {
    private var snapshot = PulseSnapshot()
    var fontSize: CGFloat = 9.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 穿透点击事件，让 NSStatusBarButton 处理高亮和原生事件流
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func updateSnapshot(_ snap: PulseSnapshot) {
        self.snapshot = snap
        needsDisplay = true
    }

    private func line1String() -> String {
        let up = formatCompactSpeed(snapshot.upBps)
        let down = formatCompactSpeed(snapshot.downBps)
        let cpu = String(format: "%.0f%%", snapshot.cpuPercent)
        return "↑\(up) ↓\(down) C:\(cpu)"
    }

    private func line2String() -> String {
        // 功率
        let pStr: String
        if !snapshot.packageW.isNaN && snapshot.packageW > 0 {
            pStr = String(format: "%.1fW", snapshot.packageW)
        } else if !snapshot.batteryPowerW.isNaN && snapshot.batteryPowerW > 0 {
            pStr = String(format: "%.1fW", snapshot.batteryPowerW)
        } else {
            pStr = "--W"
        }

        // 电池
        let batStr: String
        if snapshot.batteryPercent >= 0 {
            if !snapshot.etaSeconds.isNaN && snapshot.etaSeconds > 60 {
                let m = Int(snapshot.etaSeconds) / 60
                let h = m / 60
                let remM = m % 60
                if h > 0 {
                    batStr = "\(snapshot.batteryPercent)%(\(h)h)"
                } else {
                    batStr = "\(snapshot.batteryPercent)%(\(remM)m)"
                }
            } else {
                batStr = "\(snapshot.batteryPercent)%"
            }
        } else {
            batStr = "AC"
        }

        // 延迟
        let pingStr: String
        if snapshot.netState == .offline {
            pingStr = "断网"
        } else if !snapshot.latencyMs.isNaN {
            pingStr = String(format: "%.0fms", snapshot.latencyMs)
        } else {
            pingStr = ".."
        }

        return "\(pStr) \(batStr) \(pingStr)"
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let textColor = NSColor.headerTextColor

        // 第一行：网速与 CPU (水平自动居中，彻底消除右侧空白过多)
        let attr1: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let l1 = line1String() as NSString
        let w1 = l1.size(withAttributes: attr1).width
        let x1 = max(2.0, (bounds.width - w1) / 2.0)
        l1.draw(at: NSPoint(x: x1, y: 11.5), withAttributes: attr1)

        // 第二行：功耗、电量与延迟 (水平自动居中)
        let attr2: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: snapshot.netState == .offline ? NSColor.systemRed : textColor.withAlphaComponent(0.88)
        ]
        let l2 = line2String() as NSString
        let w2 = l2.size(withAttributes: attr2).width
        let x2 = max(2.0, (bounds.width - w2) / 2.0)
        l2.draw(at: NSPoint(x: x2, y: 1.5), withAttributes: attr2)
    }

    private func formatCompactSpeed(_ bps: Double) -> String {
        if bps.isNaN || bps <= 0 { return "0K" }
        if bps < 1024 * 1024 {
            let k = bps / 1024.0
            return String(format: "%.0fK", k)
        } else {
            return String(format: "%.1fM", bps / (1024.0 * 1024.0))
        }
    }
}
