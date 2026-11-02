# Phase 0 Research: 每连接主机上下文（Per-Link Host Context）技术决策

**Feature**: `specs/005-host-link-profile-awareness` | **Date**: 2026-11-02 | **Plan**: [plan.md](./plan.md)

本文件沉淀 plan.md Technical Context 中各项选择的「为什么」，并把「现有两端 BLE/解析/状态层如何承接新信号」的实现落点逐条记录（带 `文件:行号`）。所有「未知/未验证」项显式标注，禁止臆测。

> 范围提醒：本 feature 的**固件生产者**在兄弟仓库 `zmk-keybeacon`；本仓库仅落地**协议文档**（`protocol/`）、**跨平台测试向量**（`conformance/`）与**两个 host app 消费者**（`app/macos/**`、`app/windows/**`）。本文件与 plan/contracts 属仓库内部文档，不在宪法 §VI 双语强制范围。

---

## 1. 核心问题与决策摘要

ZMK 键盘可同时与多台主机保持 BLE 链路，但只有**全局活跃 profile** 接收按键；而现有 KBP 1.1 Connectivity 特征 `AA440AA2-…` 通过**广播 NOTIFY** 下发、各主机收到的字节**完全相同**——因此两台主机都看到同一个 `profile_index`，都误判「在用」。

**决定性使能点**：GATT 的 **READ 是每连接（per-connection）的**——固件知道是哪条链路在发读请求，可对每台主机返回**不同**的 `local_link_profile`。

> **已验证（2026-11-02）**：Zephyr 官方 `include/bluetooth/gatt.h` 的 Characteristic Attribute read callback 签名为 `ssize_t (*read)(struct bt_conn *conn, const struct bt_gatt_attr *attr, void *buf, uint16_t len, uint16_t offset)`——`@param conn Connection object` 明确存在。固件在 READ 回调里可 `bt_conn_get_dst(conn)` 取 peer 并映射到 bonded slot。方案根基成立。

于是每台主机**零配置**学到「我是 P几」，再与广播的 `active_profile_index` 比对，得出五态之一。

---

## 2. 技术决策（Decisions）

### D1. wire 承载：新增独立**只读**特征 `AA440AA4-…`（方案 A，已选定）

- **Decision**：新增一个可选特征 `AA440AA4-F5ED-4C48-84A1-8062D20D3D55`，**properties = `READ` only（无 `NOTIFY`、无 CCC）**，payload `[0].bits0–6 = local_link_profile`（1-based，`0` = 未确定/不适用），`[0].bit7 = reserved（MUST 0）`。**`AA440AA2-…` Connectivity 的 `[0..6]`（含 byte0 bit7）一个字节都不改。**
- **Rationale**（相较「在 AA2 尾部加 `[7]` + 重定义 bit7」的被否决方案，见 D1-alt）：
  1. **消除 host 侧 READ/NOTIFY 帧区分**——只读特征物理上不可能推送 NOTIFY，host 对它的每一次 `didUpdateValueForCharacteristic`（macOS）/`ReadAsync` 返回（Windows）都**必然**是本连接的 READ 响应，不存在被广播帧污染的竞态。
  2. **语义干净**——「本链路是哪个 slot」是一个**稳定的 per-connection 事实**，天然适合独立特征，而非塞进会随时变化的广播快照。
  3. **能力探测走特征存在性**——与 KBP 1.1 探测 `AA2/AA3` 完全一致（§14.5「按特征 UUID 存在性判定 MINOR」），比重定义一个保留能力位更自洽。
  4. **AA2 零改动**——向后兼容论证最强：老 app 对 AA2 的解析逐字节不变，新特征老 app 根本不发现。
- **属 MINOR**：`protocol/README.md §9`「MINOR 可新增可选 characteristic」；§14.6「未来 1.2+ 可 append new characteristics」。service UUID 不变。
- **代价**：多一次「发现 + 读」AA4（一次性，可忽略）；active 与 local 来自两个特征需 host 组合（host 本就跨特征组合，无本质复杂度增加）。

### D1-alt. 被否决方案：在 AA2 尾部加 `[7]` + 重定义 byte0 bit7

- 方案：Connectivity payload 追加 `[7].local_link_profile`，把 `byte0.bit7`（1.1 reserved）重定义为 `has_local_link_profile`。
- **否决理由**：AA2 同时具 `READ|NOTIFY`，per-link 值只在 READ 帧有意义、NOTIFY 帧无意义 → **host 必须区分这一帧是 READ 响应还是广播通知**。而 **CoreBluetooth 的 READ 响应与 NOTIFY 共用同一个 `peripheral:didUpdateValueForCharacteristic:error:` 回调、无区分标志**，只能用「读请求在途」标志近似判定，存在竞态（读在途时恰好来 NOTIFY 会误判）。方案 A 从根上消除该脆弱点，代价仅一个新特征，故否决本方案。

### D1-alt2. 被否决方案：host 侧监听 HID 输入流量自行推断

- 方案：不改固件，host 监听自己是否还在收到 HID 按键报告，有流量=在用。
- **否决理由**：无法区分「切到别的机器」与「用户只是没打字」（静默≠切走），违反 FR-005 即时性；且需 Input Monitoring 隐私授权，与 KeyBeacon「BLE GATT 观察者」定位不符。记录备查。

### D2. 状态派生：五态纯函数（两端同构）

`Local Host Status` 由 {`local_link_profile`（读 AA4 学到）、`active_profile_index`（AA2 广播）、`output_endpoint`（AA2）、`link.connected`（AA2）} 派生，五态唯一：

| 状态 | 判定（按优先级） |
|------|------------------|
| `disconnected` | `link.connected == false`（**最高优先级**，链路丢失覆盖一切缓存） |
| `on-usb` | `has_output_endpoint ∧ output_endpoint == USB(1) ∧ connected` |
| `in-use-here` | `local_link_known ∧ active_index == local_slot ∧ connected`（且非 USB） |
| `active-elsewhere(N)` | `local_link_known ∧ active_index != local_slot ∧ connected` |
| `cannot-determine` | 其余：未发现 AA4 / `local_slot == 0` / active n/a 或 open / 缺 `has_profile` / 输入不一致 |

- **Rationale**：严格满足 FR-005 五态与 FR-008「无正向确认不得渲染 in-use-here」。派生为**纯函数**（输入解析后字段 → 输出枚举），可穷举单测（FR-014）。
- **profile_open**：`active.isOpen == 1`（等待配对）→ 无活跃目标 → `cannot-determine`（对应 spec 边界「open → pair/not applicable」）。

### D3. 读取与重读时机

- **首读**：发现 `AA440AA4-…` 后立即 READ 一次 → 学到本机 slot。
- **重读**（MUST）：(a) 连接/重连后；(b) 观察到 `profile_open` 由 1→0（刚分配到 slot）；(c) 收到 AA2 NOTIFY 且 `active_profile_index` 变化时（重派生，并按需重读保证一致）；(d) 周期兜底（默认 60 s）。
- **Rationale**：`local_link_profile` 为**会话级**缓存（重新配对到别的 slot 靠下次连接/重读再学）。重读是 host→keyboard 的主动 READ，不产生键盘 NOTIFY，不违反「未变化不通知」（宪法 §IV 仅约束生产者 NOTIFY）。

### D4. macOS 侧实现落点（CoreBluetooth / AppKit）

- **BLE**：CoreBluetooth。UUID 常量 `BLEClient.swift:53-64`（新增 `AA440AA4` 常量）；发现 service `:402-409`/`:203`；`discoverCharacteristics([AA1,AA2,AA3], for:)` `:194-201`/`:475-482` → **加入 `AA4`**；`didDiscoverCharacteristicsFor` `:485-546` 保存 `AA4` 引用并 `readValue(for:)`；`didUpdateValueFor` `:548-565` 按 `characteristic.uuid == AA4` 分发到新 `handleLinkSlotRead`。
- **无需 pendingRead 标志**（方案 A 的直接收益）：AA4 只读 → 回调必是 READ 响应。
- **新增 re-read**：`BLEClient` 上加公开 `readLinkSlot()` → `peripheral?.readValue(for: linkSlotCharacteristic)`，接入 reconnect / active 变化 / 兜底。
- **解析**：**不改** `ConnectivityStatus`（`ConnectivityStatus.swift:160-172`）与 `CapabilityMatrix`（bit7 仍是 `reserved7`）。新增独立纯类型 `LinkSlot`（解析 AA4 单字节）+ 五态派生函数 `deriveLocalHostStatus(...)`，置于新文件 `LocalHostStatus.swift`。
- **状态/UI**：现有 `BLEConnectionState`（`BLEClient.swift:7-12`，4 态 transport 级）**不复用**；新增 `LocalHostStatus`（5 态）。连接卡片 `renderHostRow`（`FloatingPanel.swift:870-892`）按新枚举分支。双语 `L10n`（`Localization.swift:76`，英表 `:146-165`、中表 `:205-224`）新增 5 key。
- **陈旧/降级**：`StalenessTracker`（`StalenessTracker.swift:21`）；断开 `forceStaleAll()`（`FloatingPanel.swift:676-679`）。诊断 `DiagnosticsLogger`（`DiagnosticsLogger.swift:19`，category `:25-29`）新增 `hostlink.*`。
- **单测**：XCTest（`app/macos/Tests/BleWidgetTests/`），穷举样例 `ConnectivityStatusTests.swift:11-161`。新增 `HostLinkProfileAwarenessTests.swift` 对 `LinkSlot.parse` 与 `deriveLocalHostStatus` 做穷举。

### D5. Windows 侧实现落点（WinRT / WPF）

- **BLE**：WinRT（`KeyboardMonitor.cs:10-13`）。发现 service `:190-203`、characteristic `:204-213`（**加入 `AA4` 发现**）；`ReadAsync` 已有 `:270-281`（直接返回值，天然区分 READ）；订阅无需改（AA4 不订阅 NOTIFY）；断连钩子 `OnConnectionStatusChanged` `:386-396`、`ReconnectAsync` `:100-104`。
- **读取**：发现 AA4 → `ReadAsync(_linkSlotChar)` → 解析；重读复用同一调用，接入 reconnect / active 变化 / 兜底。
- **解析**：**不改** `ConnectivityStatus`（`ConnectivityStatus.cs:102-114`）与 `CapabilityMatrix`。新增 `LinkSlot`（record）+ 纯函数 `DeriveLocalHostStatus(...)` 于 `KeyBeacon.Core`。
- **状态/UI**：现有 `MonitorState`（`KeyboardSnapshot.cs:8-16`，6 态 transport）**不复用**；新增 `HostContextStatus`（5 态）经 `KeyboardSnapshot` 携带。`MainViewModel.ApplyConnectivity`（`MainViewModel.cs:298-325`）/`ApplyCompact`（`:204-257`）加渲染分支；文案 switch `:147-167`。双语 `.resx`（`Resources.resx` + `Resources.zh-CN.resx`，经 `LocalizationService.cs:14-39`）新增 5 key。
- **陈旧/降级**：`StalenessTracker`（`StalenessTracker.cs:15-69`），断连 `ForceStaleAll()` `:47`（`KeyboardMonitor.cs:390-391`）。诊断事件常量 `DiagnosticsLogger.cs:39-69` 新增 `hostlink.*`。
- **单测**：xUnit（`KeyBeacon.Core.Tests`），helper `Payload(...)` `ConnectivityStatusTests.cs:8`。新增 `HostContextStatusTests.cs` 对 `LinkSlot` 与 `DeriveLocalHostStatus` 穷举。

### D6. 协议与一致性文档（bilingual 强制）

- **Decision**：本 feature **发布**协议增量，故 `protocol/README.md`（§14.2 两特征表增一列或新增 §14.9 描述 AA4、§14.5 发现流程、§14.6、§13 changelog、§11）、`protocol/CHANGELOG.md`、`conformance/checklist.md`（C13/C14）**MUST 英中双语**（宪法 §VI）。
- **conformance 工具**：`conformance/conformance_tool.py` 新增 `parse_link_slot` 读 AA4 单字节；新增特征发现/属性校验（READ-only、无 CCC）。
- **版本**：`protocol/VERSION` `1.1.0` → `1.2.0`（MINOR）。

---

## 3. 未验证 / 风险（显式标注）

| ID | 风险 / 未知 | 处置 |
|----|-------------|------|
| R1 | **固件能否把连接 peer 稳定映射到 bonded slot**（resolvable-private-address 可能导致 peer≠bonded identity） | 固件无法解析时 MUST 发 `local_link_profile = 0`（未确定），主机降级 `cannot-determine`（FR-003）。属**可接受诚实降级**。在 zmk-keybeacon 仓库验证 `zmk_ble_profile_index(addr)` 可行性。 |
| R2 | iOS 可能缓存 READ 结果 | spec 已排除 iOS；macOS/Windows 无此问题。快速切换靠「active 变化即重读 + ≤1 s」缓解（D3）。 |
| R3 | AA4 为只读、host 是否真的免于帧区分 | 是——只读特征不可能产生 NOTIFY，`ReadValueAsync`/`readValue` 回调必是 READ 响应。方案 A 的核心收益。 |
| R4 | 周期兜底读与「未变化不通知」冲突？ | 不冲突——兜底是 host→keyboard 主动 READ，不触发键盘 NOTIFY（宪法 §IV 约束的是生产者 NOTIFY）。 |

---

## 4. 诊断与严格降级（对齐宪法 §IV）

每一条降级路径 MUST 恰好一条结构化诊断日志：
- `hostlink.unresolved` — 发现了 AA4 但读回 `local_link_profile = 0`（固件无法解析 peer→slot）。
- `hostlink.cannot_determine` — 主机侧输入不足/不一致（未发现 AA4、active 未知、open slot）。
- `hostlink.read_back_slot` — 主机重读后刷新了本机 slot（信息级，便于诊断「重新配对后学到新 slot」）。
- 沿用既有 `profile.out_of_range`（slot 越界）/ `connection.state_changed` / `staleness.field_stale` 等，不新增重复语义。

---

## 5. 关键路径速查（两端对照）

| 关注点 | macOS | Windows |
|--------|-------|---------|
| AA2 Connectivity 解析 | `ConnectivityStatus.swift:160-172`（**不改**） | `ConnectivityStatus.cs:102-114`（**不改**） |
| 新增 AA4 常量/发现 | `BLEClient.swift:53-64` / `:194-201` | `KbpUuids.cs` / `KeyboardMonitor.cs:204-213` |
| 读 AA4 | 新增 `readLinkSlot()`（`readValue`） | 复用 `ReadAsync` `:270-281` |
| 帧区分 | **不需要**（AA4 只读） | **不需要**（ReadAsync 天然区分） |
| 新实体 | `LinkSlot` + `LocalHostStatus`（新文件） | `LinkSlot` + `HostContextStatus`（新文件） |
| 断连→全陈旧 | `FloatingPanel.swift:676-679` | `KeyboardMonitor.cs:390-391` |
| 双语 | `Localization.swift:146-224` | `Resources.resx` + `Resources.zh-CN.resx` |
| 单测框架 | XCTest | xUnit |
| 诊断 category | `DiagnosticsLogger.swift:25-29` | `DiagnosticsLogger.cs:39-69` |
