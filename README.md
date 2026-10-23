# MacVitals

> 轻量、优雅的 macOS 原生菜单栏状态监控工具。灵感源自 Windows 平台的开源监控项目 [Pulse](https://github.com/yftx888/Pulse)。

MacVitals 基于原生 **Swift 6 + AppKit + SwiftUI** 构建，专为 Apple Silicon（M1 / M2 / M3 / M4）及现代 macOS 系统深度定制。零 Electron，无重型框架，常驻内存仅约 15~25MB，日常 CPU 占用 < 0.1%，几乎不消耗任何额外电量。

---

## 📥 直接下载使用

- 🚀 **[点击立即下载 MacVitals-v1.0.0.zip](https://github.com/LLeo1024/MacVitals/releases/download/v1.0.0/MacVitals-v1.0.0.zip)**（仅 168 KB）
- 📦 **[所有历史版本 GitHub Releases](https://github.com/LLeo1024/MacVitals/releases)**

> **安装提示**：
> 1. 下载解压得到 `MacVitals.app`；
> 2. 直接双击运行，或拖入「访达 → 应用程序」；
> 3. 首次打开若 macOS 提示“无法验证开发者”，在「系统设置」→「隐私与安全性」中点击「仍要打开」即可。

---

## 🌟 核心功能

### 1. 菜单栏紧凑双行排版（替代任务栏模式）
* **第一行**：实时物理网卡上下行速率（↑ 上传 / ↓ 下载）及 CPU 总占用率。
* **第二行**：整机 / SoC 实时功耗（W）、电池电量与平滑续航时间、HTTP 端到端延迟（ms）。
* **自适应系统主题**：跟随 macOS 菜单栏原生深色/浅色外观动态切换文字与警示颜色，断网时自动标红提醒。

### 2. 点击弹出完整面板（Popover 详情卡片）
* **硬件四格**：
  - **CPU**：实时占用率、多核状态与进度条。
  - **内存**：统一内存（RAM）已用 / 总量及占用百分比。
  - **芯片功耗**：基于 Apple Silicon 功耗模型与电池放电传感器校准的实时整机、CPU、GPU、ANE 瓦数。
  - **电池与电源**：充放电模式标识、健康度与循环次数。
* **电池平滑与深度预测**：
  - **连续时间指数平滑（Continuous EMA, $\tau=30s$）**：完全消除瞬时负载抖动对续航预测的干扰。
  - **到达 20% 时间（ETA 20%）**：专为保护锂电池寿命设计的实用指标。
  - **拔电后平均功耗**：拔掉充电器后的真实平均放电功率。
* **网络与测活探针**：
  - 绑定物理网络适配器（排除 VPN、虚拟网卡与回环接口）。
  - 异步探测国内/海外高可用 204 端点（小米 CDN、谷歌、微软），展示真实网络延迟，连续 3 次失败判定为断网。
* **高占用进程前三**：
  - 基于 Mach 内核及 `libproc` 实时扫描非自身的高 CPU 占用进程列表。

---

## 🚀 编译与运行

### 快速一键打包为 App

在项目根目录下执行打包脚本：

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

脚本将以 Release 高度优化模式编译，并自动在当前目录下生成标准的 `MacVitals.app` 应用程序包。

### 运行方式

```bash
# 启动应用
open MacVitals.app
```

启动后，MacVitals 将常驻于屏幕右上角的 **macOS 菜单栏**：
- **左键单击**：展开 / 收起完整的硬件与网络详情卡片；
- **右键单击**：弹出快捷菜单（切换刷新率：0.5s / 1.0s / 2.0s、开关可选指标、退出程序）。

---

## 🛠️ 技术架构

* **语言**：Swift 6
* **框架**：AppKit（NSStatusItem, NSView, NSPopover）、SwiftUI、Combine
* **底层接口**：
  - `mach/host_info.h`：内核级 CPU 与内存无堆开销统计
  - `IOKit.ps` / `AppleSmartBattery`：电池毫瓦级传感器与健康数据
  - `getifaddrs`：物理接口流量差分
  - `URLSession`：极轻量异步 HEAD 探针
