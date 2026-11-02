# Contract: 主机端消费流程与状态派生（consumer-flow）

**Feature**: `specs/005-host-link-profile-awareness` | **Phase**: 1 | **Source of truth**: `protocol/README.md`；wire 细节见 [data-model.md](../data-model.md)

本契约定义 **macOS / Windows 两端同构**的运行时流程与不变量：如何发现并读取 AA4、何时重读、如何派生五态、如何降级与记日志。两端共享同一份逻辑语义（纯函数），仅 BLE/UI 管道不同。

---

## CF-1 发现（沿用，附增量）

- 沿用两端既有发现流程（macOS `BLEClient.swift:475-546`；Windows `KeyboardMonitor.cs:190-213`）。
- 在特征发现列表中**加入 `AA440AA4-…`**：macOS `discoverCharacteristics([AA1,AA2,AA3,AA4], for:)`；Windows 发现后筛出 AA4 引用。
- 能力探测按**特征存在性**（HW-5）：发现 AA4 → per-link 可用；否则按老固件处理。

## CF-2 读取 AA4（无需帧区分）

- **AA4 只读**（无 NOTIFY），故对它的任何读回必是本连接 READ 响应——**两端都无需区分 READ/NOTIFY 帧**（这是方案 A 相对「AA2 尾部加字段」方案的核心简化）。
- **macOS**：发现 AA4 后 `peripheral.readValue(for: aa4)`；回调 `didUpdateValueFor` 按 `uuid == AA4` 分发到 `handleLinkSlotRead`。新增公开 `readLinkSlot()` 供重读。
- **Windows**：发现 AA4 后 `ReadAsync(_linkSlotChar)`（`KeyboardMonitor.cs:270-281`）直接返回值解析；重读复用同一调用。
- **AA4 不订阅 CCC**（无 NOTIFY）。

## CF-3 重读时机（MUST）

对 `AA440AA4-…` 发起 READ 刷新 `local_link_profile` 的时机：
1. 连接/重连后首次发现；
2. 观察到 AA2 的 `profile_open` 由 `1 → 0`（分配到 slot）；
3. 收到 AA2 NOTIFY 且 `active_profile_index` 变化（重派生 + 重读一致性）；
4. 周期兜底（默认 60 s，可配置）。

- 重读是 host→keyboard READ，不产生键盘 NOTIFY，不违反「未变化不通知」（宪法 §IV 仅约束生产者 NOTIFY）。
- 读到新 slot 且与缓存不同 → 发 `hostlink.read_back_slot`（信息级）。

## CF-4 五态派生（纯函数，两端同构）

- 唯一实现 `deriveLocalHostStatus(hasAA4, cap, link, active, local, output)`（见 [data-model.md §6.1](../data-model.md)），输入解析后字段 + AA4 是否存在，输出五态枚举。
- 调用点（每次任一输入变化都重派生）：
  - AA2 notify 到达（active/output/link 变化）；
  - AA4 READ 刷新了 `local_link_profile`；
  - 连接/断开（link.connected 变化）；
  - 兜底 tick。

## CF-5 降级与严格性（对齐宪法 §IV / FR-008/009）

- 任一路径**不得**在缺乏正向确认时渲染 `inUseHere` / `activeElsewhere`；缺失/未知/不一致 → `cannotDetermine` 或 `disconnected`。
- 断连 MUST 立即 `disconnected`（覆盖任何缓存 in-use），发 `connection.state_changed` + 置所有字段陈旧。
- 每降级事件恰好一条结构化诊断：
  - `hostlink.unresolved`（发现 AA4 但读回 slot=0，对端无法解析）；
  - `hostlink.cannot_determine`（主机侧输入不足，附缺失输入类别：未发现 AA4 / active 未知 / open）；
  - `hostlink.read_back_slot`（读回刷新）；
  - 复用 `profile.out_of_range`（slot 越界）、`discovery.anomaly`（有 AA4 无 AA2）。

## CF-6 UI 呈现（两语，FR-010）

- 单行「此电脑」状态，与键盘**全局状态**视觉区分；文案见 [data-model.md §6](../data-model.md) 五态双语表。
- macOS：`FloatingPanel.renderHostRow` 分支扩展；`L10n` 新增 5 key（英/中两表同加）。
- Windows：`MainViewModel.ApplyConnectivity/ApplyCompact` 分支扩展；`Resources.resx` + `Resources.zh-CN.resx` 新增 5 key（同加）。
- `activeElsewhere` 文案含 `P{N}`（N=active slot）。

## CF-7 更新时延（FR-006 / SC-001）

- 从 active profile 变化（AA2 notify）到 UI 更新 MUST ≤ 1 s；无重连要求。
- 快速切换（1 s 内两次）MUST settle 在最终 active，不残留陈旧 in-use。

## CF-8 向后兼容行为（FR-012 / SC-004）

| 组合 | 期望 |
|------|------|
| 新 app + 老固件（无 AA4） | 不发现 AA4；仅 link 级状态；不出现 in-use/elsewhere；无新 UI 错乱 |
| 老 app + 新固件（有 AA4） | 老 app 不发现/不读 AA4（不在其特征列表）；AA0/AA1/AA2/AA3 解析字节级不变；无新 UI |
