# KBP 1.x conformance checklist

Each line is an **individually verifiable** requirement from KeyBeacon Protocol §10. The right
column names the automated check in [`conformance_tool.py`](conformance_tool.py) that covers it.
Build guidance for each item is in [`CONFORMANCE.md`](CONFORMANCE.md); the wire contract is
[`../protocol/README.md`](../protocol/README.md).

A keyboard **conforms to KBP 1.x** when every REQUIRED item passes.

| # | Requirement | Level | Tool check |
|---|-------------|-------|-----------|
| 1 | Exposes service `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` with characteristic `AA440AA1-…`, properties `READ`+`NOTIFY`, and a CCC (`0x2902`) descriptor. | REQUIRED | **C1** |
| 2 | A READ returns a snapshot **≥ 2 bytes** matching the `[layer_index][mods][layer_name]` layout; `layer_name` is valid UTF-8 (or empty) with no trailing NUL. | REQUIRED | **C2** |
| 3 | NOTIFY fires on every layer/modifier change **and is suppressed when the snapshot is unchanged** (an idle keyboard emits zero notifications). | REQUIRED | **C3** |
| 4 | Remains discoverable **while connected** via connected-peripheral enumeration (it has stopped advertising once connected to the host). | REQUIRED | **C4** |
| 5 | Advertises a **non-empty GAP device name** (else the host uses a generic fallback). | RECOMMENDED | **C5** (WARN) |
| 6 | For split keyboards: the feature is present **only on the central (host-link) role** and absent from the peripheral and `settings_reset` images. | REQUIRED (split) | **C6** (MANUAL) |

## How verification maps to results

- **C1–C4** gate the exit code: any FAIL ⇒ the tool exits `1` and names the failing item.
- **C5** is RECOMMENDED — a missing GAP name is reported as **WARN**, not a failure.
- **C6** cannot be observed from the host; the tool marks it **MANUAL**. Confirm in your firmware
  build config that the KeyBeacon service is compiled into the **central** image only.
- Environment problems (Bluetooth off, no keyboard, connect timeout, missing PyObjC) exit `2` — a
  tooling/setup issue, not a conformance verdict.

## Quick self-test

```bash
python3 conformance/conformance_tool.py
# exit 0 = conforms · 1 = a required item failed · 2 = environment error
```

---

<a id="zh-checklist"></a>

# KBP 1.x 一致性检查清单(中文版)

**English** · [中文](#zh-checklist)

每一行都是来自 KeyBeacon 协议 §10 的**可独立验证**的要求。右列标明 [`conformance_tool.py`](conformance_tool.py)
中覆盖该项的自动检查。每一项的构建指引见 [`CONFORMANCE.md`](CONFORMANCE.md);线上合约见
[`../protocol/README.md`](../protocol/README.md)。

当每个 REQUIRED(必需)项都通过时,键盘即**符合 KBP 1.x**。

| # | 要求 | 级别 | 工具检查 |
|---|------|------|---------|
| 1 | 暴露服务 `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` 及特征 `AA440AA1-…`,属性为 `READ`+`NOTIFY`,并带 CCC(`0x2902`)描述符。 | REQUIRED | **C1** |
| 2 | READ 返回符合 `[layer_index][mods][layer_name]` 布局、**≥ 2 字节**的快照;`layer_name` 为有效 UTF-8(或为空)且无尾部 NUL。 | REQUIRED | **C2** |
| 3 | NOTIFY 在每次层/修饰键变化时触发,**且在快照未变化时被抑制**(空闲键盘发出零条通知)。 | REQUIRED | **C3** |
| 4 | 在**已连接**状态下仍可通过已连接外设枚举被发现(连接到主机后它已停止广播)。 | REQUIRED | **C4** |
| 5 | 广播**非空的 GAP 设备名称**(否则主机使用通用占位名)。 | RECOMMENDED | **C5**(WARN) |
| 6 | 对于分体键盘:该功能**仅存在于中央(主机链路)角色**,副手与 `settings_reset` 镜像中均不存在。 | REQUIRED(分体) | **C6**(MANUAL) |

## 验证如何映射到结果

- **C1–C4** 决定退出码:任一 FAIL ⇒ 工具退出 `1` 并指明失败项。
- **C5** 为 RECOMMENDED —— 缺失 GAP 名称报告为 **WARN**,而非失败。
- **C6** 无法从主机侧观测;工具标记为 **MANUAL**。请在你的固件构建配置中确认 KeyBeacon 服务仅编入**中央**镜像。
- 环境问题(蓝牙关闭、无键盘、连接超时、缺少 PyObjC)退出 `2` —— 属于工具/环境问题,而非一致性结论。

## 快速自测

```bash
python3 conformance/conformance_tool.py
# 退出 0 = 符合 · 1 = 某必需项失败 · 2 = 环境错误
```
