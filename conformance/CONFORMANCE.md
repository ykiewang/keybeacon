# Making a keyboard conform to KeyBeacon (KBP)

This guide is the **complete, concrete body of work** to make a keyboard work with KeyBeacon and
to prove it. It is normative for the claim "this keyboard supports KBP". The authoritative wire
contract is [`../protocol/README.md`](../protocol/README.md); this document tells a keyboard author
**what to build**, and [`checklist.md`](checklist.md) + [`conformance_tool.py`](conformance_tool.py)
tell them **how to verify** it.

You can implement KBP on any firmware stack and any BLE library — KBP is defined only by what
appears on the air. The notes below call out the ZMK reference path where helpful, but nothing here
requires ZMK.

## 0. Prerequisite: the keyboard must own the host BLE link (central role)

KeyBeacon reports state to a desktop host over the keyboard's **host-facing BLE connection**. The
keyboard must therefore be the device the host connects to:

- **Unibody / single-MCU keyboard**: it already is the host-link device — nothing special.
- **Split keyboard**: only the half that holds the **central (host-link) role** exposes KeyBeacon.
  The peripheral half and any `settings_reset`/recovery image **must not** include it. (In the ZMK
  reference, that means the KeyBeacon kit is gated to the central build only.)

If your keyboard cannot act as the host-link BLE device, it cannot implement KBP as specified.

## 1. Expose the service and characteristic

Add one custom GATT **primary service** with one **status characteristic**:

| Item | Value |
|------|-------|
| Service UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` |
| Status characteristic UUID | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` |
| Properties | `READ` **and** `NOTIFY` |
| Descriptor | Client Characteristic Configuration (CCC, `0x2902`) — required for NOTIFY |

The **service UUID is the identity and the compatibility signal**. Do not gate behavior on device
name or model. (Verified by tool check **C1**.)

## 2. Produce the status payload (≥ 2 bytes, little-endian)

The characteristic value is the variable-length snapshot from protocol §4:

| Offset | Size | Field | Source |
|--------|------|-------|--------|
| `[0]` | 1 | `layer_index` (`uint8`) | highest active layer index |
| `[1]` | 1 | `mods` (`uint8`) | held HID modifier bitmask (see §4.1) |
| `[2..N]` | ≥ 0 | `layer_name` (UTF-8, no trailing NUL) | active layer's name; MAY be empty |

Rules:

- The payload MUST be **at least 2 bytes**. `layer_name` MAY be empty (a 2-byte payload is valid).
- `layer_name` MUST be **valid UTF-8** and carry **no trailing NUL**.
- Derive everything from the keyboard's authoritative keymap/HID state — never a second cached copy.
- Keep the whole snapshot within your negotiated ATT MTU (the reference firmware truncates
  `layer_name` to 32 bytes; that is an implementation limit, not a protocol limit).

(Verified by tool check **C2**.)

## 3. Notify on change, and suppress when unchanged

- Send a **NOTIFY** whenever the snapshot changes (a layer switch or a modifier press/release).
- **Suppress** the notification when the recomputed snapshot equals the last one you sent. An idle
  keyboard MUST produce **zero** notification traffic.
- Support **READ** for the current snapshot (the host reads it once on connect, then subscribes).

(Verified by tool check **C3**: subscription succeeds and no traffic arrives while idle.)

## 4. Stay discoverable while connected

A connected BLE HID keyboard stops advertising, so the host finds it by **enumerating already-
connected peripherals** and confirming the service over GATT. You get this for free by exposing the
service on the live host connection — just make sure the service is present on the **connected**
image. (Verified by tool check **C4** when the keyboard is connected to the test host.)

## 5. Advertise a GAP device name (recommended)

Advertise a non-empty **GAP device name**; the host uses it as the display name. If absent, the host
falls back to a generic label and still connects, so this is **RECOMMENDED, not required**.
(Reported by tool check **C5**; the tool prints the discovered name so you can confirm identity.)

## 6. Verify with the conformance tool

Run the self-test against your keyboard (connect it to the test Mac first for the reliable path):

```bash
python3 conformance/conformance_tool.py            # defaults: --timeout 15 --observe 4
```

The tool discovers your keyboard **by service UUID only**, prints the discovered GAP name, and
reports **per-item PASS/FAIL/WARN** for C1–C6 (see [`checklist.md`](checklist.md)).

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | all required items pass — the keyboard conforms to KBP 1.x |
| `1` | a required conformance item failed (the output names which one) |
| `2` | environment error — Bluetooth off, no keyboard found, connect timeout, or missing deps |

Required items are **C1–C4**; **C5** is RECOMMENDED (WARN only) and **C6** (split central-only) is a
MANUAL firmware-config check the host cannot observe. A clean reference keyboard yields exit `0`.

## 7. Requirements for the tool

macOS with Python 3 and PyObjC CoreBluetooth:

```bash
pip install pyobjc-framework-CoreBluetooth
```

Grant the terminal/app Bluetooth permission when macOS prompts.

---

<a id="zh-conformance"></a>

# 让键盘符合 KeyBeacon（KBP）— 中文版

**English** · [中文](#zh-conformance)

本指南是使键盘兼容 KeyBeacon 并加以验证的**完整、具体的工作清单**。它对"此键盘支持 KBP"这一声明具有规范性效力。权威的线上合约见 [`../protocol/README.md`](../protocol/README.md)；本文档告诉键盘作者**需要构建什么**，[`checklist.md`](checklist.md) + [`conformance_tool.py`](conformance_tool.py) 告诉他们**如何验证**。

你可以在任意固件栈和任意 BLE 库上实现 KBP——KBP 仅由空中传输的内容定义。下面的注释在有帮助时会指出 ZMK 的参考路径，但此处没有任何内容要求使用 ZMK。

## 0. 前提条件：键盘必须拥有主机 BLE 链路（central 角色）

KeyBeacon 通过键盘的**面向主机的 BLE 连接**将状态上报给桌面主机。因此键盘必须是主机所连接的设备：

- **一体式 / 单 MCU 键盘**：它本身就是主机链路设备——无需特别处理。
- **分体键盘**：只有持有 **central（主机链路）角色**的半边才暴露 KeyBeacon。副手半边和任何 `settings_reset`/恢复镜像**不得**包含它。（在 ZMK 参考实现中，这意味着 KeyBeacon kit 仅对 central 构建生效。）

如果你的键盘无法充当主机链路 BLE 设备，则它无法按规范实现 KBP。

## 1. 暴露服务与特征

添加一个包含一个**状态特征**的自定义 GATT **主服务**：

| 项目 | 值 |
|------|---|
| 服务 UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` |
| 状态特征 UUID | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` |
| 属性 | `READ` **与** `NOTIFY` |
| 描述符 | 客户端特征配置（CCC，`0x2902`）——NOTIFY 所必需 |

**服务 UUID 即是身份标识和兼容性信号**。不要基于设备名称或型号来控制行为。（由工具检查项 **C1** 验证。）

## 2. 生产状态载荷（≥ 2 字节，小端序）

特征值是来自协议 §4 的可变长度快照：

| 偏移 | 大小 | 字段 | 来源 |
|------|------|------|------|
| `[0]` | 1 | `layer_index`（`uint8`） | 最高激活层索引 |
| `[1]` | 1 | `mods`（`uint8`） | 按住的 HID 修饰键位掩码（见 §4.1） |
| `[2..N]` | ≥ 0 | `layer_name`（UTF-8，无尾部 NUL） | 当前激活层的名称；MAY 为空 |

规则：

- 载荷 MUST **至少为 2 字节**。`layer_name` MAY 为空（2 字节载荷是合法的）。
- `layer_name` MUST 是**有效的 UTF-8** 且**无尾部 NUL**。
- 从键盘权威的键映射/HID 状态派生所有内容——绝不使用第二份缓存副本。
- 将整个快照控制在你协商的 ATT MTU 范围内（参考固件将 `layer_name` 截断至 32 字节；这是实现限制，不是协议限制）。

（由工具检查项 **C2** 验证。）

## 3. 变化时通知，未变化时抑制

- 当快照变化时（层切换或修饰键按下/松开），发送 **NOTIFY**。
- 当重新计算的快照与上次发送的相同时，**抑制**通知。空闲键盘 MUST 产生**零**通知流量。
- 支持 **READ** 以获取当前快照（主机连接时读取一次，然后订阅）。

（由工具检查项 **C3** 验证：订阅成功，空闲时无流量到达。）

## 4. 连接期间保持可发现性

已连接的 BLE HID 键盘会停止广播，因此主机通过**枚举已连接外设**并通过 GATT 确认服务来找到它。只要在**已连接**镜像上暴露服务，你就自动满足此要求——确保服务存在于连接镜像中即可。（连接测试主机时由工具检查项 **C4** 验证。）

## 5. 广播 GAP 设备名称（推荐）

广播非空的 **GAP 设备名称**；主机用它作为显示名称。若缺失，主机回退到通用标签并仍然连接，因此这是**推荐而非必需**。（由工具检查项 **C5** 报告；工具会打印发现的名称供你确认身份。）

## 6. 用一致性工具进行验证

在你的键盘上运行自测（先将键盘连接到测试 Mac 以走可靠路径）：

```bash
python3 conformance/conformance_tool.py            # 默认：--timeout 15 --observe 4
```

工具仅通过**服务 UUID** 发现你的键盘，打印发现的 GAP 名称，并对 C1–C6 逐项报告 **PASS/FAIL/WARN**（见 [`checklist.md`](checklist.md)）。

**退出码：**

| 码 | 含义 |
|----|------|
| `0` | 所有必需项通过——键盘符合 KBP 1.x |
| `1` | 某必需一致性项失败（输出会指明是哪一项） |
| `2` | 环境错误——蓝牙关闭、未找到键盘、连接超时或缺少依赖 |

必需项为 **C1–C4**；**C5** 为推荐项（仅 WARN）；**C6**（分体键盘 central-only）是主机无法观测的**人工固件配置检查**。干净的参考键盘应退出 `0`。

## 7. 工具运行要求

macOS，需安装 Python 3 和 PyObjC CoreBluetooth：

```bash
pip install pyobjc-framework-CoreBluetooth
```

macOS 提示时授予终端/应用蓝牙权限。
