# Contract: WinRT BLE 消费流程（ble-consumption）

**Feature**: `specs/003-windows-desktop-client` | **Phase**: 1 | **Source of truth**: `protocol/README.md`（本文件**引用不复制** wire 契约）

本契约定义 Windows 客户端作为 KBP **消费者**的运行时流程与不变量。wire 字节布局见 [data-model.md](../data-model.md) 与 `protocol/README.md §1/§4/§14`。本 feature 不改动任何 wire（FR-012）。

## C-1 发现（Discovery）

- MUST 以**枚举已连接设备**发现键盘，NOT 广播扫描（FR-001）：
  `BluetoothLEDevice.GetDeviceSelectorFromConnectionStatus(BluetoothConnectionStatus.Connected)` → `DeviceInformation.FindAllAsync(selector)`，并以 `DeviceWatcher` 持续跟踪 Added/Removed/Updated。
- 对每个候选 `DeviceInformation.Id`：`BluetoothLEDevice.FromIdAsync` → `GetGattServicesAsync` → 用 `KbpUuids.Classify` 分类。
- 仅 `supported` 进入监视候选；`unsupportedVersion` → UI 显示「协议版本不受支持」且 NOT 解析（FR-009）；`notAKeyboard` 忽略。
- 全程 WinRT 调用 MUST 在 MTA 上下文（research D2 gotcha）。

## C-2 连接与特征发现

- 在选定键盘上发现 service `AA440AA0-…`，再发现特征：
  - `AA440AA1-…`（status，**必存**；缺失 → 该设备不可用）。
  - `AA440AA2-…`（connectivity，可选）。
  - `AA440AA3-…`（battery，可选）。
- 形态判定（data-model §7）：仅 AA1 → `onePointZero`；有 AA2 → `onePointOne(hasBattery: AA3存在)`。
- 见到 AA2 却无 AA1 → 发 `discovery.anomaly`，按不可用处理。
- 陈旧已连接设备风险：`FromIdAsync`/`GetGattServicesAsync` MUST 施加超时（默认值由 probe P6 实测确定），超时 → 发诊断日志并标该设备不可用，NOT 无限等待（edge case：OS 显示已连接但 GATT 读不出）。

## C-3 读取与订阅

- 对 AA1（及存在的 AA2/AA3）：先 `ReadValueAsync` 取初值，再 `WriteClientCharacteristicConfigurationDescriptorAsync(Notify)` 订阅。
- `ValueChanged` 回调把原始字节交给 `KeyBeacon.Core` 解析器（data-model §1/§3/§4）。
- AA3 的解析 MUST 传入 AA2 声明的 `isSplit`（定长校验 C-B1/C-B2）。若 AA3 先于 AA2 到达，缓存原始字节，待 capability 已知后再解析。
- 解析返回 `null`（长度/校验失败）→ 发对应诊断日志（`connectivity.short_payload` / `battery.length_mismatch`），UI 对该字段显示不可用，NOT 伪造。

## C-4 降级与陈旧（对齐 Principle IV）

- 每个降级事件 MUST 恰好一条结构化日志，类别/字段见 [research.md §4](../research.md)（FR-018）。
- 断开/蓝牙不可用 → `StalenessTracker.ForceStaleAll()`，UI 在 3 秒内切「未连接」并停显旧值（FR-007 / SC-003）；发 `connection.state_changed`。
- 连接仍在但字段超 3 秒无更新 → 保留最后已知值 + 「更新于 hh:mm:ss」+ 视觉弱化，不清空不伪造（FR-007a）。
- 蓝牙适配器关闭/缺失 → UI 显「蓝牙不可用」（US2 场景 2）。可用后自动恢复发现（edge case）。
- 每字段 3 秒陈旧（data-model §5）：跨 live→stale 发 `staleness.field_stale`，stale→live 发 `staleness.field_live`。

## C-5 能力位字段级显示（FR-016/FR-008）

- KBP 1.1 字段 MUST 严格按 `CapabilityMatrix` 位显示/隐藏：不支持的字段**完全不出现**（无占位、无伪造，SC-008）。
- `IsConsistent == false` → 丢弃违背位（当 0）+ 发 `capability.inconsistent`。

## C-6 多键盘与记忆

- 多 `supported` 键盘 → 托盘菜单按 `DisplayName` 列出（FR-010）。
- 选择持久化到 `settings.json`；启动用 `CompatibleKeyboard.ResolveSelection(candidates, remembered)` 决定（data-model §6/§8）。

## C-7 重连

- 键盘断开后 MUST 自动经 `DeviceWatcher` 重新发现并重建订阅，无需重启应用（FR-011）；锁屏/休眠唤醒后同理（edge case）。

## 不变量清单（供 tasks/测试引用）

| ID | 不变量 | 来源 |
|----|--------|------|
| C-C1 | Connectivity payload < 7 字节 → null + 日志 | protocol §14.3 |
| C-C2 | > 7 字节 → 取前 7，尾部计入 TrailingBytesIgnored | MINOR 前向兼容 |
| C-B1 | 非 split 电量必 1 字节 | protocol §14.4 |
| C-B2 | split 电量必 2 字节 | protocol §14.4 |
| C-B3 | 电量 101..254 → 不可用 + out_of_range 日志 | protocol §14.4.2 |
| IV-C1 | HasSplitLink 需 IsSplit | capability 一致性 |
| IV-C3 | HasRightCharging 需 IsSplit && HasLeftCharging | capability 一致性 |
