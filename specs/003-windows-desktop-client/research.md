# Phase 0 Research: Windows 桌面客户端技术决策与可行性 probe

**Feature**: `specs/003-windows-desktop-client` | **Date**: 2026-10-24 | **Plan**: [plan.md](./plan.md)

本文件沉淀 plan.md Technical Context 中各项选择的「为什么」，并把 FR-014 的**可行性 probe** 定义为实现前的硬门禁：probe 通过才推进完整客户端。所有「未知/未验证」项显式标注，禁止臆测。

## 1. 技术决策（Decisions）

### D1. 语言/运行时：C# 12 / .NET 8 (LTS)

- **Decision**: C# / .NET 8，TFM 分层：`KeyBeacon.Core` 用 `net8.0`（无平台依赖），`KeyBeacon.App` / `KeyBeacon.Probe` 用 `net8.0-windows10.0.19041.0`。
- **Rationale**: `net8.0-windowsXX.YY.ZZZZ` 这个 TFM 会自动把 WinRT（`Windows.Devices.Bluetooth*`）投影进 C# 命名空间，**无需** MSIX/UWP 打包、无需手工引 `Microsoft.Windows.SDK.Contracts`。.NET 8 是 LTS，覆盖 Win10 2004+/Win11，x64+ARM64。
- **Alternatives rejected**:
  - **Rust + btleplug + FFI**：会引入跨语言 core/FFI 维护成本，而本项目要省的只是 ~519 行机械移植——不值。（已在 brainstorm 阶段否决。）
  - **C++/WinRT**：BLE 可行但 UI/托盘/打包/诊断生态远不如 .NET，开发效率低。  - **UWP/MSIX 打包**：会强制沙箱与商店分发模型，与 macOS 版「ad-hoc、非商店」现状不一致，且非必需（bleak 证明未打包也能用 WinRT BLE）。

### D2. BLE 访问：WinRT 投影（未打包）

- **Decision**: 经 `net8.0-windows10.0.19041.0` TFM 直接调用 `Windows.Devices.Bluetooth`（GATT）+ `Windows.Devices.Enumeration`（`DeviceWatcher`）。
- **Rationale**: Python 的 `bleak` 在未打包进程里用的就是同一套 WinRT API，是「未打包亦可用」的现成证据。**已连接但不广播**的 HID 键盘只能靠**枚举已连接设备**发现（`BluetoothLEDevice.GetDeviceSelectorFromConnectionStatus(Connected)` + `DeviceWatcher` / `DeviceInformation.FindAllAsync`），而非广播扫描（`BluetoothLEAdvertisementWatcher`）——这对应 FR-001。
- **Hard gotcha（已知，必须在代码中规避）**: WinRT 异步在非 **MTA** 线程模型下会永久挂起。`KeyBeacon.Probe` 的入口 MUST 为 `[MTAThread]`；`KeyBeacon.App`（WPF 默认 STA）MUST 把所有 WinRT BLE 调用 marshaling 到一个专用 MTA 线程/线程池上下文。**此点是 probe 要验证的第一现实风险。**

### D3. UI 栈：WPF + 托盘 + 无边框置顶悬浮窗

- **Decision**: WPF（`net8.0-windows10.0.19041.0`）；托盘用 `H.NotifyIcon.Wpf`（现代、支持 .NET 8、MIT）；悬浮窗用无边框 `Window`（`WindowStyle=None`、`Topmost=true`、`ShowInTaskbar=false`）。
- **Rationale**: 需同时满足 FR-008（常驻托盘、不占任务栏、不抢焦点）与 FR-020（常驻置顶无边框悬浮窗，对标 macOS `FloatingPanel`）。WPF 对无边框/置顶/点击穿透/DPI 缩放的控制比 WinForms 成熟，且本地化（`.resx`）与数据绑定天然。
- **Alternatives rejected**:
  - **WinUI 3**：早期设计曾考虑。它更现代，但未打包场景的部署/依赖（Windows App SDK runtime）更重，托盘与无边框置顶窗生态不如 WPF 稳。最终收敛为 **WPF**，理由即部署简单、托盘/浮窗控制成熟。
  - **WinForms**：托盘最简单，但无边框置顶浮窗/DPI/本地化/绑定体验差。

### D4. 日志与诊断：Microsoft.Extensions.Logging + Serilog 滚动文件

- **Decision**: 以 `Microsoft.Extensions.Logging` 为抽象面；接收器用 Serilog rolling file，落 `%LOCALAPPDATA%\KeyBeacon\logs\`，结构化字段对齐 macOS `DiagnosticsLogger` 的类别与字段名（见 §4）。诊断包用 `System.IO.Compression.ZipFile` 打成单一 `.zip`。
- **Rationale**: 满足 FR-018（每降级事件恰好一条结构化日志）+ FR-022（持久化+滚动）+ FR-023（一键诊断包）+ FR-024（详细开关）+ FR-025（脱敏）。Serilog 的 rolling file + structured properties 是 .NET 事实标准。
- **类别对齐**：macOS 用 `os.Logger` subsystem `com.keybeacon.app` + 类别 `capability/profile/battery/staleness/connection`。Windows 复用同名类别（`SourceContext` 或自定义 property `category`），使跨平台 issue 的日志可读性一致。

### D5. 本地化：`.resx` + `CultureInfo`（跟随系统区域）

- **Decision**: `Resources.resx`（默认英文）+ `Resources.zh-CN.resx`；启动按 `CultureInfo.CurrentUICulture` 选择，zh-* → 中文，其余 → 英文（FR-021）。
- **Rationale**: .NET 原生卫星程序集机制，零第三方依赖，符合「跟随系统区域、至少中英两套」。

## 2. 可行性 probe（FR-014 的落点，实现前硬门禁）

### 目的

在写任何客户端 UI/BLE 业务代码之前，用一个最小 CLI（`KeyBeacon.Probe`）在**真实 Windows 主机 + 真实 KBP 键盘**上验证三件事。只要任一「阻塞项」失败，就触发 §3 回退，不盲目推进实现。

### 验证项（verification matrix）

| ID | 验证内容 | 判定 | 阻塞级别 |
|----|----------|------|----------|
| **P1 MTA 线程** | `[MTAThread]` 入口下 WinRT GATT 异步不挂起 | 调用返回而非超时 | 阻塞（实现基础） |
| **P2 枚举已连接** | 用 `GetDeviceSelectorFromConnectionStatus(Connected)` + `DeviceInformation.FindAllAsync` 枚出已配对且已连接的键盘，拿到其 `DeviceInformation.Id` | 列表含目标键盘 | 阻塞（FR-001） |
| **P3 GATT 共享连接不踢 HID** | `BluetoothLEDevice.FromIdAsync` + `GetGattServicesAsync` 建立 GATT 连接后，键盘仍正常打字 | 打字不中断 | 阻塞（核心前提） |
| **P4 发现 KBP service/char** | 在目标设备上发现 `AA440AA0-…` service 及 `AA440AA1-…`（必）/`AA2-…`/`AA3-…`（选）特征 | 找到 AA1，按存在性记录 AA2/AA3 | 阻塞（无服务即不可用） |
| **P5 读 + 订阅通知** | 对 `AA440AA1-…` `ReadValueAsync` 一次，并 `WriteClientCharacteristicConfigurationDescriptorAsync(Notify)` 后收到至少一次 `ValueChanged`（切层/按修饰键触发） | 收到 notify | 阻塞（FR-014 核心） |
| **P6 陈旧连接超时** | 对「OS 显示已连接但 GATT 读不出」的键盘，`FromIdAsync`/`GetGattServicesAsync` 是否长时间卡住；需要的超时/重试策略 | 记录实测超时行为与可行超时值 | 非阻塞（记录即可，喂给实现） |

### probe 产物

- 一份 **run log**（结构化），记录每项 PASS/FAIL + 原始数据（service/char UUID 列表、首个 notify 的 payload hex、各 async 调用耗时）。
- 结论写回本 `research.md` 的 §5「真机验证结论」表（probe 跑完后补）。

### probe CLI 契约

参数、输出、退出码见 [contracts/probe-cli.md](./contracts/probe-cli.md)。

## 3. Phase 0 FAIL → Windows 回退路径

probe 任一**阻塞项**失败时，按以下顺序评估，并把结论记入 §5：

1. **P1 失败（MTA 挂起）**：几乎必可解（线程模型问题）；调整线程 marshaling 后重测，不回退。
2. **P3 失败（GATT 连接踢掉 HID 打字）**：最严重。回退序列：
   a. 尝试「只读/短连接 + 立即释放」模式，降低与系统 HID 栈的争用；
   b. 若仍冲突 → 评估 `GattSession.MaintainConnection=false` + 按需短读；
   c. 若根本不可共存 → **Windows 版本降级为「按需快照」而非实时订阅**（轮询式，牺牲 SC-002 的 3 秒实时性），并在 spec/plan 记录为已知限制；
   d. 最差 → 判定 WinRT 路径不可行，记录结论、暂缓 Windows GUI 交付（与 Linux 同等「尽力而为后延后」待遇），不影响 macOS。
3. **P2/P4/P5 失败**：先排除配对状态/驱动/键盘固件未实现 KBP 等环境因素（换参考键盘 Corne 复测）；确属 WinRT 能力缺口再走 2c/2d。
4. **P6（非阻塞）**：无论结果，都把实测超时值固化为实现的连接超时/重试默认参数。

> 任何回退都 MUST 以 probe run log 为据，禁止凭猜测下结论（用户明确要求：永远研究真实方案，不臆测）。

## 4. 结构化日志字段对齐表（macOS → Windows）

Windows `Diagnostics` 复刻 macOS `DiagnosticsLogger` 的事件，保证跨平台 issue 日志语义一致。类别=category property；字段名逐字对齐。

| category | event | 关键字段（对齐 macOS） | 触发（降级事件） |
|----------|-------|------------------------|------------------|
| capability | `capability.discovered` | raw(hex), is_split, has_host_connection, has_profile, has_split_link, has_output_endpoint, has_left_charging, has_right_charging | 首次解析能力位 |
| capability | `capability.inconsistent` | raw(hex), reason | IV-C1/IV-C3 违背，丢弃该位 |
| capability | `capability.mutated` | from(hex), to(hex) | 能力位热变更 |
| profile | `profile.out_of_range` | raw_index, max_slots | index>max_slots |
| battery | `battery.length_mismatch` | expected, got, is_split | 长度不符 C-B1/C-B2 |
| battery | `battery.out_of_range` | raw(hex), side | 字节 101..254 |
| staleness | `staleness.field_stale` | field, reason | live→stale（3s 或断开） |
| staleness | `staleness.field_live` | field | stale→live |
| connection | `connection.state_changed` | connected, reason_raw(hex) | host_state.connected 翻转 |
| connection | `connectivity.short_payload` | length | <7 字节 C-C1 |
| connection | `discovery.anomaly` | reason | 见到 AA2 无 AA1 |

> 每个降级事件**恰好一条**日志（FR-018）；详细模式（FR-024）额外记录成功路径与原始 payload hex。

## 5. 真机验证结论（probe 跑完后回填）

> **状态：已验证 PASS。** 2026-10-31 在 Windows 11（10.0.26100，x64，.NET 8.0.33）上执行 `KeyBeacon.Probe`，参考键盘为 **TOTEM**（KBP 1.1，含 AA1/AA2/AA3）。verdict=**PASS**，门禁开。

| ID | 结果 | 实测数据 / 备注 |
|----|------|-----------------|
| P1 | ✅ PASS | `apartment=MTA`；WinRT GATT 异步在 `[MTAThread]` 下不挂起 |
| P2 | ✅ PASS | 枚举到 1 台已连接设备：`TOTEM`（id `…9b:1a:c1-cb:e3:c4:10:be:53`）；耗时 197 ms |
| P3 | ✅ PASS | GATT 会话建立后打字不中断（操作者确认）——核心前提成立，无需回退 |
| P4 | ✅ PASS | `classify=Supported`；发现 `AA1,AA2,AA3`（完整 KBP 1.1：层/修饰键 + 连接 + 电量）；耗时 461 ms |
| P5 | ✅ PASS | 首个 notify `000042415345` → 解析 `layer=BASE`、`mods=none`（解析器逐字节正确）；订阅→首 notify 11452 ms（含操作者切层的人工反应时间） |
| P6 | ✅ PASS | 非阻塞。`observed_max_ms=11452` 实为 P5 等待人工操作的时延；真实 GATT 调用均 <500 ms（P2=197/P4=461）。**结论：`--timeout` 默认 10 s 对真实 GATT 操作足够，维持不变。** |

**门禁结论**：✅ **PASS**（P1–P5 全 PASS ⇒ 推进 Phase 1 实现）。P6 非阻塞，实测确认 10 s 默认超时合理。

## 6. 仍未解决 / 依赖真机的未知项

- ~~`dotnet` SDK 在开发者 Windows 机上的可用性~~ → 已确认（.NET 8.0.33，Windows 11 10.0.26100）。
- ~~Windows「陈旧已连接设备」枚举/连接的真实超时行为（P6）~~ → 已测：真实 GATT 调用 <500 ms，10 s 默认超时足够。
- ~~GATT 共享连接是否不踢 HID（P3）~~ → 在本机 TOTEM 上确认不中断打字；其它驱动/芯片组组合仍建议逐一验证。
- Linux：BlueZ 内核 HID 与 GATT 订阅是否冲突——复用 `conformance/conformance_tool.py` 在 Linux 主机探查，结论记入 US4，不阻塞 Windows。
