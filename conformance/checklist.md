# KBP 1.x conformance checklist

Each line is an **individually verifiable** requirement from KeyBeacon Protocol §10 (KBP 1.0) and
§14 (KBP 1.1). The right column names the automated check in
[`conformance_tool.py`](conformance_tool.py) that covers it. Build guidance for each item is in
[`CONFORMANCE.md`](CONFORMANCE.md); the wire contract is
[`../protocol/README.md`](../protocol/README.md).

A keyboard **conforms to KBP 1.x** when every REQUIRED item passes. KBP 1.1 items (C7–C12) only
apply when the keyboard exposes the corresponding optional characteristic; a KBP 1.0-only keyboard
yields `SKIP` on all 1.1 rows and still conforms.

## KBP 1.0 (unchanged)

| # | Requirement | Level | Tool check |
|---|-------------|-------|-----------|
| 1 | Exposes service `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` with characteristic `AA440AA1-…`, properties `READ`+`NOTIFY`, and a CCC (`0x2902`) descriptor. | REQUIRED | **C1** |
| 2 | A READ returns a snapshot **≥ 2 bytes** matching the `[layer_index][mods][layer_name]` layout; `layer_name` is valid UTF-8 (or empty) with no trailing NUL. | REQUIRED | **C2** |
| 3 | NOTIFY fires on every layer/modifier change **and is suppressed when the snapshot is unchanged** (an idle keyboard emits zero notifications). | REQUIRED | **C3** |
| 4 | Remains discoverable **while connected** via connected-peripheral enumeration (it has stopped advertising once connected). | REQUIRED | **C4** |
| 5 | Advertises a **non-empty GAP device name** (else the host uses a generic fallback). | RECOMMENDED | **C5** (WARN) |
| 6 | For split keyboards: the feature is present **only on the central (host-link) role** and absent from the peripheral and `settings_reset` images. | REQUIRED (split) | **C6** (MANUAL) |

## KBP 1.1 (added)

| # | Requirement | Level | Tool check |
|---|-------------|-------|-----------|
| 7 | If exposed: Connectivity characteristic `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` has properties `READ`+`NOTIFY` and a CCC (`0x2902`). | REQUIRED (if present) | **C7** |
| 8 | If exposed: Connectivity READ returns a payload **≥ 7 bytes** matching protocol §14.3; invariants P-C1..P-C5 all hold (`has_split_link ⇒ is_split`; `profile_index ≤ profile_max_slots`; reserved bits/bytes are 0; `has_right_charging ⇒ has_left_charging ∧ is_split` and the integer-board `charging_flags.bit 1 = 0` rule). | REQUIRED (if present) | **C8** |
| 9 | If exposed: Battery characteristic `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` has `READ`+`NOTIFY` and CCC; payload length matches `is_split` (1 byte overall, 2 bytes split). | REQUIRED (if present) | **C9** |
| 10 | If exposed: Connectivity NOTIFY fires on every state-ish field change **and is suppressed when the snapshot is byte-identical**. | REQUIRED (if present) | **C10** |
| 11 | If exposed: Battery NOTIFY throttling respects **≥ 1 pp change OR ≥ 1 s since last emit** (OR relation); violations without hardware justification report WARN. | RECOMMENDED (if present) | **C11** (WARN) |
| 12 | For split keyboards: the 1.1 characteristics are exposed **only on the central (host-link) role** (extension of C6). | REQUIRED (split) | **C12** (MANUAL) |

## How verification maps to results

- **C1–C4** gate the exit code: any FAIL ⇒ the tool exits `1` and names the failing item.
- **C5** is RECOMMENDED — a missing GAP name is reported as **WARN**, not a failure.
- **C6** cannot be observed from the host; the tool marks it **MANUAL**. Confirm in your firmware
  build config that the KeyBeacon service is compiled into the **central** image only.
- **C7–C10** gate the exit code **only when the corresponding characteristic is present** (the tool
  reports `SKIP` when a 1.1 characteristic is absent — that is not a failure, just a KBP 1.0 host).
- **C11** is RECOMMENDED (WARN only) for Battery throttling; sub-percent jitter under heavy typing
  is observed and reported but does not fail the run.
- **C12** cannot be observed from the host; the tool marks it **MANUAL** (same policy as C6).
- Environment problems (Bluetooth off, no keyboard, connect timeout, missing deps) exit `2` — a
  tooling/setup issue, not a conformance verdict.

## Quick self-test

```bash
python3 conformance/conformance_tool.py              # cross-platform (bleak)
python3 conformance/conformance_tool.py --json       # support matrix for CI
# exit 0 = conforms · 1 = a required item failed · 2 = environment error
```

The legacy macOS-only PyObjC tool is retained as
[`conformance_tool_macos.py`](conformance_tool_macos.py) for KBP 1.0 regression and as a fallback
when `bleak` is unavailable.

---

<a id="zh-checklist"></a>

# KBP 1.x 一致性检查清单(中文版)

**English** · [中文](#zh-checklist)

每一行都是来自 KeyBeacon 协议 §10（KBP 1.0）与 §14（KBP 1.1）的**可独立验证**的要求。右列标明
[`conformance_tool.py`](conformance_tool.py) 中覆盖该项的自动检查。每一项的构建指引见
[`CONFORMANCE.md`](CONFORMANCE.md);线上合约见 [`../protocol/README.md`](../protocol/README.md)。

当每个 REQUIRED(必需)项都通过时,键盘即**符合 KBP 1.x**。KBP 1.1 的项目（C7–C12）**仅当键盘暴露
对应的可选特征时才适用**；KBP 1.0-only 键盘在 1.1 行上全部 `SKIP` 且仍视为符合。

## KBP 1.0（不变）

| # | 要求 | 级别 | 工具检查 |
|---|------|------|---------|
| 1 | 暴露服务 `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` 及特征 `AA440AA1-…`,属性为 `READ`+`NOTIFY`,并带 CCC(`0x2902`)描述符。 | REQUIRED | **C1** |
| 2 | READ 返回符合 `[layer_index][mods][layer_name]` 布局、**≥ 2 字节**的快照;`layer_name` 为有效 UTF-8(或为空)且无尾部 NUL。 | REQUIRED | **C2** |
| 3 | NOTIFY 在每次层/修饰键变化时触发,**且在快照未变化时被抑制**(空闲键盘发出零条通知)。 | REQUIRED | **C3** |
| 4 | 在**已连接**状态下仍可通过已连接外设枚举被发现(连接到主机后它已停止广播)。 | REQUIRED | **C4** |
| 5 | 广播**非空的 GAP 设备名称**(否则主机使用通用占位名)。 | RECOMMENDED | **C5**(WARN) |
| 6 | 对于分体键盘:该功能**仅存在于中央(主机链路)角色**,副手与 `settings_reset` 镜像中均不存在。 | REQUIRED(分体) | **C6**(MANUAL) |

## KBP 1.1（新增）

| # | 要求 | 级别 | 工具检查 |
|---|------|------|---------|
| 7 | 若暴露：Connectivity 特征 `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` 的属性为 `READ`+`NOTIFY` 并带 CCC(`0x2902`)。 | REQUIRED（若暴露） | **C7** |
| 8 | 若暴露：Connectivity READ 返回符合协议 §14.3 的 **≥ 7 字节** 载荷；不变量 P-C1..P-C5 全部成立（`has_split_link ⇒ is_split`；`profile_index ≤ profile_max_slots`；保留位/保留字节为 0；`has_right_charging ⇒ has_left_charging ∧ is_split` 且整板 `charging_flags.bit 1 = 0`）。 | REQUIRED（若暴露） | **C8** |
| 9 | 若暴露：Battery 特征 `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` 具 `READ`+`NOTIFY` 与 CCC；载荷长度与 `is_split` 一致（整板 1 字节，分体 2 字节）。 | REQUIRED（若暴露） | **C9** |
| 10 | 若暴露：Connectivity NOTIFY 在任一状态性字段变化时触发，**且在字节一致的快照上被抑制**。 | REQUIRED（若暴露） | **C10** |
| 11 | 若暴露：Battery NOTIFY 节流符合 **≥ 1 pp 变化 或 距上次 notify ≥ 1 秒**（或 关系）；在无硬件原因下违反该规则报告 WARN。 | RECOMMENDED（若暴露） | **C11**（WARN） |
| 12 | 对于分体键盘：1.1 特征**仅在 central(主机链路)角色**暴露（扩展自 C6）。 | REQUIRED（分体） | **C12**（MANUAL） |

## 验证如何映射到结果

- **C1–C4** 决定退出码:任一 FAIL ⇒ 工具退出 `1` 并指明失败项。
- **C5** 为 RECOMMENDED —— 缺失 GAP 名称报告为 **WARN**,而非失败。
- **C6** 无法从主机侧观测;工具标记为 **MANUAL**。请在你的固件构建配置中确认 KeyBeacon 服务仅编入**中央**镜像。
- **C7–C10** **仅当对应特征存在时**决定退出码（1.1 特征缺失时工具报告 `SKIP` —— 这不是失败，而是 KBP 1.0-only 主机的正常行为）。
- **C11** 为 RECOMMENDED（仅 WARN），用于 Battery 节流观测；重度打字时的亚百分点抖动会被观测并报告，但不影响运行结果。
- **C12** 无法从主机侧观测；工具标记为 **MANUAL**（与 C6 同一策略）。
- 环境问题(蓝牙关闭、无键盘、连接超时、缺少依赖)退出 `2` —— 属于工具/环境问题,而非一致性结论。

## 快速自测

```bash
python3 conformance/conformance_tool.py              # 跨平台（bleak）
python3 conformance/conformance_tool.py --json       # CI 可消费的支持矩阵
# 退出 0 = 符合 · 1 = 某必需项失败 · 2 = 环境错误
```

macOS 专用的 PyObjC legacy 工具保留为 [`conformance_tool_macos.py`](conformance_tool_macos.py)，
作为 KBP 1.0 回归工具与 `bleak` 不可用时的 fallback。
