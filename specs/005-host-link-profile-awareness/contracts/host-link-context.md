# Contract: 每连接主机上下文 wire 增量（host-link-context）

**Feature**: `specs/005-host-link-profile-awareness` | **Phase**: 1 | **Source of truth**: `protocol/README.md`（本文件**引用不复制** wire 契约，人工起草区；ratify 后并入 `protocol/`）

本契约定义 KBP **1.2 MINOR** 的唯一 wire 增量：**新增一个独立只读特征 `AA440AA4-…`** 承载 `local_link_profile`。**不改动**任何既有特征（AA0/AA1/AA2/AA3）的任何字节、属性或语义，service UUID 不变（宪法 §II）。字节级真相见 [data-model.md §1](../data-model.md) 与 ratify 后的 `protocol/README.md §14`。

---

## HW-1 版本与兼容

- **KBP MINOR**: `1.1` → `1.2`（`protocol/VERSION`、`protocol/CHANGELOG.md`、`protocol/README.md §13`）。
- **KBP MAJOR (service UUID)**: 不变 `AA440AA0-…`。
- **Breaking changes**: 无。既有 AA0/AA1/AA2/AA3 逐字节不变。
- **双向兼容**（宪法 §II，FR-011/FR-012）：
  - 1.1 主机 + 1.2 固件 → 1.1 主机不发现 AA4，行为与 1.1 **完全一致**。
  - 1.2 主机 + 1.1 固件 → GATT 发现不到 AA4 → 主机降级 `cannot-determine`，仅显示 link 级状态，**绝不**臆造 slot（C-L2）。

## HW-2 新特征 `AA440AA4-…`

| 项 | 值 |
|----|-----|
| UUID | `AA440AA4-F5ED-4C48-84A1-8062D20D3D55`（同一主服务 `AA440AA0-…` 下） |
| 属性 | **`READ` only**（MUST NOT `NOTIFY`；MUST NOT 暴露 CCC `0x2902`） |
| Optional | 是——整只特征 MAY 缺省（固件不实现 per-link 时 GATT 发现不到） |
| 存在性 | 即 per-link 能力信号（与 1.1 以 AA2/AA3 存在性判能力一致） |

### HW-2.1 payload 布局（≥ 1 字节）

| Offset | Size | Field | 编码 |
|--------|------|-------|------|
| `[0]` | 1 | `local_link_profile` | bits 0–6：本连接 slot（1-based；`0` = 未确定/不适用）；bit 7：reserved，MUST 0 |
| `[1..N]` | ≥0 | reserved trailing | 未来 MINOR；consumer MUST ignore |

### HW-2.2 per-connection 语义

- READ 响应中的 `local_link_profile` = **发起该 READ 的这条 BLE 连接**对应的 slot。
- AA4 无 NOTIFY，故**不存在广播污染**，消费者对 AA4 的任何读都得到本连接值。

## HW-3 生产者不变量（固件 MUST）

- **P-L1**：AA4 若暴露 → 属性恰为 `READ`（无 `NOTIFY`、无 CCC）。
- **P-L2**：无法把 peer 解析到 slot（含 open/未配对/私有地址不匹配）→ `[0].bits0–6 = 0`，MUST NOT 猜测。
- **P-L3**：`[0].bits0–6 > 0` 时 MUST ≤ `profile_max_slots`（AA2 `[3]`）。
- **P-L4**：`[0].bit7` MUST 0。
- **P-L5**：仅 split 键盘的中心（host-link）角色暴露 AA4（延伸 §14 C12）。

## HW-4 消费者规则（主机 MUST）

- **C-L1**：发现 AA4 → READ 一次取 `local_link_profile`；无需订阅。
- **C-L2**：未发现 AA4 → 不渲染 in-use/elsewhere，仅 link 级（`disconnected`/`cannot-determine`）。
- **C-L3**：AA4 payload < 1 字节 → 视未确定 + 发 `hostlink.cannot_determine`。
- **C-L4**：slot > `profile_max_slots` → clamp + `profile.out_of_range`。
- **C-L5**：payload `[1..]` 尾部 MUST ignore。
- **C-L6**：AA2 的 `[0..6]` 解析与 `C-C1..C-C7` 全部不变。

## HW-5 发现与读取流程（延伸 §14.5）

- 服务发现后请求发现**全部**特征；按 UUID 存在性判定：
  - 仅 `AA1` → 1.0；无 1.1/1.2 UI。
  - `AA1`+`AA2`(+`AA3`) → 1.1（连接/电量）。
  - 额外存在 `AA4` → 1.2 per-link 可用：READ `AA4` 学本机 slot。
  - 见到 `AA4` 却无 `AA2` → 异常：发 `discovery.anomaly`，按不可用处理（per-link 需要 AA2 的 active/output 做比较）。
- 每次重连 MUST 重新 READ `AA4`（会话级学习）。

## HW-6 一致性清单扩展（`conformance/checklist.md` C13/C14）

- **C13**：若 `AA440AA4-…` 存在 → 属性恰为 `READ`（无 `NOTIFY`、无 CCC），READ payload ≥ 1 字节且 `[0].bit7 = 0`（REQUIRED if present）。
- **C14**：若 `AA4` 存在 → `[0].bits0–6 ∈ {0} ∪ [1, profile_max_slots]`（不越界；0 允许表示未确定）（REQUIRED if present）。

> C13/C14 **静态可判**（单次 READ 即可验证），不要求跨连接实测；跨连接行为（真机 + 两台电脑）由 quickstart 手工剧本覆盖（宪法 Testing Discipline）。
