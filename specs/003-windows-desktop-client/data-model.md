# Phase 1 Data Model: Windows 桌面客户端

**Feature**: `specs/003-windows-desktop-client` | **Date**: 2026-10-24 | **Plan**: [plan.md](./plan.md)

本文件定义 `KeyBeacon.Core`（`net8.0`，纯解析、跨平台可测）的实体、字段与 wire 偏移。全部逐字节复刻 macOS `BleWidgetCore` 的既有实现（唯一真相源 `protocol/README.md`），并以 `conformance/` 共享测试向量验证——**不发明任何新字段**（宪法 Principle I）。

## 0. UUID 常量（`KbpUuids`）

| 名称 | UUID | 说明 |
|------|------|------|
| service | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` | KBP 服务；MAJOR 版本信号 |
| status (AA1) | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` | KBP 1.0 层+修饰键（必存） |
| connectivity (AA2) | `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` | KBP 1.1 连接（可选） |
| battery (AA3) | `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` | KBP 1.1 电量（可选） |
| family suffix | `-F5ED-4C48-84A1-8062D20D3D55` | 家族判定后缀；未来 MAJOR 换前段保后缀 |

`KbpUuids.Classify(IEnumerable<Guid> discoveredServices)` → `supported` / `unsupportedVersion` / `notAKeyboard`，逻辑与 Swift `KBPCompatibility.classify` 一致：命中 supported 集合 → supported；否则命中 family suffix → unsupportedVersion；否则 notAKeyboard。

## 1. KeyboardStatus（KBP 1.0，来自 AA1）

逐字节复刻 `KeyboardStatus.swift`。

| 字段 | 类型 | wire | 规则 |
|------|------|------|------|
| LayerIndex | byte | byte 0 | — |
| Mods | byte | byte 1 | HID 修饰键位掩码 |
| LayerName | string | bytes 2..n (UTF-8) | 空 → 回退 `L{index}`（FR-004） |
| Connected | bool | — | parse 成功即 true |

- **Parse**: `data.Length < 2` → `null`。`byte0=index`，`byte1=mods`，`byte2..` UTF-8 解码（解码失败 → 空串 → 回退 `L{index}`）。
- **修饰键合并**（FR-005，左右任一按下即激活）：
  - Shift = `mods & 0x22 != 0`
  - Control = `mods & 0x11 != 0`
  - Alt(Option) = `mods & 0x44 != 0`
  - Gui(Command) = `mods & 0x88 != 0`
- **Disconnected** 哨兵：`{index:0, name:"", mods:0, connected:false}`。

## 2. CapabilityMatrix（KBP 1.1，Connectivity byte 0）

逐字节复刻 `CapabilityMatrix.swift`。

| bit | 字段 | 约束 |
|-----|------|------|
| 0 | IsSplit | — |
| 1 | HasHostConnection | — |
| 2 | HasProfile | — |
| 3 | HasSplitLink | 需 IsSplit（IV-C1） |
| 4 | HasOutputEndpoint | — |
| 5 | HasLeftCharging | 非 split 时表示整体 |
| 6 | HasRightCharging | 需 IsSplit && HasLeftCharging（IV-C3） |
| 7 | Reserved7 | 1.1 固件 MUST 为 0；无损保留 |

- `IsConsistent`：`HasSplitLink && !IsSplit` → false；`HasRightCharging && !IsSplit` → false；`HasRightCharging && !HasLeftCharging` → false；否则 true。
- 违背时：调用方丢弃该位（当 0）并发 `capability.inconsistent` 日志（消费规则 C-C3/C-C6）。
- `RawByte` 往返无损（保留 bit7）。

## 3. ConnectivityStatus（KBP 1.1，来自 AA2，7 字节）

逐字节复刻 `ConnectivityStatus.swift`。`Parse`：`data.Length < 7` → `null`（C-C1，并发 `connectivity.short_payload`）；取前 7 字节，尾部多余字节记入 `TrailingBytesIgnored`（C-C2，MINOR 前向兼容）。

| byte | 子结构 | 字段 → 规则 |
|------|--------|-------------|
| 0 | CapabilityMatrix | 见 §2 |
| 1 | Link | connected = bit0；lastDisconnectReason = bits1-2 (0 unknown/1 explicit/2 timeout/3 reserved)；reservedBits3To7 = bits3-7 |
| 2–3 | Profile | index = b2 & 0x7F（1-based，0=不适用）；isOpen = b2 bit7；maxSlots = b3 |
| 4 | SplitLinkFlags | leftOnline = bit0；rightOnline = bit1；reservedBits2To7 = bits2-7 |
| 5 | OutputEndpoint | 0 unknown / 1 usb / 2 ble / 其它 reserved(b) |
| 6 | ChargingFlags | leftCharging = bit0；rightCharging = bit1；reservedBits2To7 = bits2-7 |

## 4. BatteryStatus（KBP 1.1，来自 AA3）

逐字节复刻 `BatteryStatus.swift`。`Parse(data, isSplit)`：依 Connectivity 声明的 `isSplit` 定长校验——

- `isSplit == false` ⇒ 必 1 字节 → `Overall(reading)`（C-B1）
- `isSplit == true` ⇒ 必 2 字节 `[left,right]` → `Split(left,right)`（C-B2）
- 长度不符 → `null`，调用方发 `battery.length_mismatch`。

单字节解码 `BatteryReading(byte)`（§14.4.2）：

| 原值 | 结果 |
|------|------|
| 0..100 | `Percent(n)` |
| 255 | `Unavailable(raw:255, outOfRange:false)`（哨兵：不可用） |
| 101..254 | `Unavailable(raw, outOfRange:true)`（保留值，当不可用，发 `battery.out_of_range`） |

- `PercentValue`：available → Int；否则 null。UI 对 Unavailable **显示「不可用」，禁止以 0% 伪造**（FR-017 / SC-009）。

## 5. StalenessTracker（3 秒陈旧）

复刻 `StalenessTracker.swift`（改为 C# `sealed class`，注入单调时间，测试用）：

- `StalenessWindow` 默认 3.0s（SC-003）。
- `RecordNotify(fieldKey, at)`：时间不回退（保留较新时间戳）；清除该字段 forced-stale。
- `IsStale(fieldKey, now)`：forced-stale → true；从未记录 → true；`now - last >= window` → true。
- `ForceStaleAll()`：断开时把所有已记录字段标陈旧（UI 立即停显 live 值）。
- 线程安全：调用方在 BLE 回调线程上串行化访问；UI 读快照。

## 6. CompatibleKeyboard（设备视图）

复刻 `CompatibleKeyboard.swift`（去 CoreBluetooth，改用 WinRT `DeviceInformation.Id` 作标识）：

| 字段 | 类型 | 规则 |
|------|------|------|
| Identifier | string | WinRT `DeviceInformation.Id`（macOS 为 `UUID`） |
| Name | string? | BLE 设备名；空/空白 → 回退 `Keyboard {id 前 8}`（FR-003） |
| State | enum | disconnected/connecting/connected |
| IsCompatible | bool | 发现的 service 含 KBP service |

- `DisplayName`：有非空白 name → name；否则 `Keyboard {id.prefix(8)}`。
- `ResolveSelection(candidates, remembered)`：remembered 在候选内 → remembered；否则候选唯一 → 该把；否则 null（FR-010 记忆选择）。

## 7. 版本能力形态（对齐 BLEClient.ProtocolVariant）

| 形态 | 条件 | UI |
|------|------|-----|
| onePointZero | 仅发现 AA1 | 仅层+修饰键 |
| onePointOne(hasBattery) | 存在 AA2；AA3 可选 | 层+修饰键 + 按能力位的连接/电量 |
| 异常 | 见 AA2 无 AA1 | 发 `discovery.anomaly`，按不可用处理 |

## 8. 用户设置（`Settings`，本地文件）

`%LOCALAPPDATA%\KeyBeacon\settings.json`：

| 键 | 类型 | 对应 FR |
|----|------|---------|
| SelectedKeyboardId | string? | FR-010 记住所选键盘 |
| DisplayMode | enum(full/compact) | 对标 macOS 完整/精简 |
| PinnedCorner | enum(topLeft/topRight/bottomLeft/bottomRight) | 悬浮窗钉角 |
| VerboseLogging | bool | FR-024 详细日志开关 |
| UICulture | enum(system/zh/en) | 默认 system（FR-021） |

## 9. 测试向量映射（`KeyBeacon.Core.Tests`）

`conformance/tests` 下的共享 payload 布局用例逐一映射为 xUnit `[Theory]` 数据：AA1 层+mods+name 组合、AA2 全 7 字节位域矩阵（含 IV-C1/IV-C3 违背）、AA3 overall/split × percent/sentinel/out-of-range、长度不足/超长边界。目标：SC-005 纯解析 100% 通过，零 BLE 硬件。
