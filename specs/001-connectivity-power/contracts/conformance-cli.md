# Contract: 一致性 CLI(跨平台,KBP 1.0 + 1.1)

**Normative** · 本文件固化 `conformance/conformance_tool.py` 的**用户可观测契约**:命令行
入口、exit code、输出格式(人类可读 + `--json` 支持矩阵)、以及实现要求。实施阶段的脚本
MUST 对齐本契约。

> 现有仓库里的 `conformance/conformance_tool.py` 是 macOS/PyObjC 版本(KBP 1.0 only);
> 本次重写为**跨平台**(`bleak` 后端),覆盖 KBP 1.0 + 1.1。原文件 **git mv** 到
> `conformance/conformance_tool_macos.py` 作为 fallback 保留。

---

## 1. 命令行接口

```
python3 conformance/conformance_tool.py [OPTIONS]

Options:
  --timeout SEC         Discovery/connect timeout, default 15
  --observe SEC         Post-connect observation window to validate NOTIFY behavior, default 10
  --json                Emit the support-matrix as JSON on stdout (also includes exit intent)
  --device-filter NAME  Optional partial GAP name match to pick a specific keyboard when multiple present
  --no-color            Disable ANSI color in human-readable output
  -h, --help            Show help and exit
```

- 不接受位置参数。
- 所有选项 MUST 有短/长双形式?**不**:为降低平台特异性,只提供长选项(`--xxx`),与现有 macOS 工具的习惯一致。

---

## 2. Exit code 契约

| Code | 含义 |
|------|------|
| 0    | 所有 REQUIRED 一致性项通过;键盘声称的 MINOR 全部字段 PASS |
| 1    | 某个 REQUIRED 项失败(KBP 1.0 的 C1–C4,或 1.1 的 C7–C9 中与声称能力相关的部分) |
| 2    | 环境错误:蓝牙关闭 / 无键盘 / 连接超时 / 缺依赖(例如未装 `bleak`) |

**不变量**:
- 仅 REQUIRED 项失败才会导致 exit = 1;WARN(例如 1.0 的 C5 GAP 名、1.1 的 C11 节流违规但变化幅度 < 2 pp)**不**致命。
- 环境问题永不被当作"键盘不合规":`bleak.exc.BleakError`、BlueZ 未启动、Windows BLE Radio off 等 MUST 返回 2 而非 1。

---

## 3. 人类可读输出(默认)

对每个一致性项打印一行,格式:

```
C<n>  [PASS|FAIL|WARN|SKIP|MANUAL]  <item description>
    reason: <specific nonconformance or warning text>   # 仅 FAIL/WARN 时
```

末尾打印 verdict:

```
---
Verdict: CONFORMS to KBP 1.1 (keyboard: "Totem", address: XX:XX:XX:XX:XX:XX)
```

**不变量**:
- 每一行只对应一个 checklist 条目(C1..C12),顺序与 `conformance/checklist.md` 一致。
- 对 KBP 1.0-only 固件,C7–C12 整列 **SKIP** 并说明"keyboard does not expose KBP 1.1 characteristic"。
- SKIP 不计入 FAIL,也不触发 exit = 1。

---

## 4. `--json` 支持矩阵输出

当 `--json` flag 存在时,**人类可读输出不打印**,stdout 只打印一个 JSON object。
MUST 使用 UTF-8、带尾部 `\n`、顶层 keys 稳定排序,便于 CI 消费。

### 4.1 JSON Schema(非正式)

```jsonc
{
  "spec_version": "kbp-conformance-cli/1",
  "ran_at": "2026-10-09T12:34:56Z",
  "tool": {
    "name": "conformance_tool.py",
    "backend": "bleak",
    "version": "1.1.0"
  },
  "keyboard": {
    "name": "Totem",
    "address": "XX:XX:XX:XX:XX:XX",
    "service_uuid": "AA440AA0-F5ED-4C48-84A1-8062D20D3D55"
  },
  "declared_minor": "1.1",            // "1.0" | "1.1" | "unknown"
  "characteristics": {
    "AA440AA1": { "present": true,  "properties": ["READ","NOTIFY"], "ccc": true },
    "AA440AA2": { "present": true,  "properties": ["READ","NOTIFY"], "ccc": true },
    "AA440AA3": { "present": false, "properties": [],                "ccc": false }
  },
  "capability_bits": {                 // 仅 declared_minor == "1.1" 时存在
    "raw": "0x1F",
    "is_split":            true,
    "has_host_connection": true,
    "has_profile":         true,
    "has_split_link":      true,
    "has_output_endpoint": true,
    "has_left_charging":   false,
    "has_right_charging":  false
  },
  "field_support": {                   // 覆盖 A 组所有字段
    "is_split":        "supported",
    "host_connection": "supported",
    "profile":         "supported",
    "split_link":      "supported",
    "overall_battery": "unsupported",   // 分体键盘下该字段天然不存在
    "left_battery":    "supported",
    "right_battery":   "supported",
    "output_endpoint": "supported",
    "left_charging":   "unsupported",
    "right_charging":  "unsupported"
  },
  "checklist": [
    {
      "id": "C1",
      "level": "REQUIRED",
      "status": "PASS",
      "detail": null
    },
    {
      "id": "C9",
      "level": "REQUIRED",
      "status": "WARN",
      "detail": "Battery NOTIFY observed 3 updates in <1s with <1pp delta (expected throttle)"
    }
  ],
  "verdict": "conforms",               // "conforms" | "nonconforms" | "environment_error"
  "exit_code": 0
}
```

### 4.2 字段级 `field_support` 取值

| 值            | 含义 |
|---------------|------|
| `supported`   | 固件 capability bit = 1,且观察期内 payload 行为符合契约 |
| `unsupported` | 固件 capability bit = 0,或 characteristic 不存在 |
| `malformed`   | capability bit = 1 但 payload 不符合 §3/§4 契约(例如长度错误) |
| `skipped`     | 固件不支持 KBP 1.1(退化为 1.0 only) |

### 4.3 不变量

- **J-1**:`exit_code` 字段的值 **MUST** 与进程 exit code 一致。
- **J-2**:`checklist[].status ∈ {PASS, FAIL, WARN, SKIP, MANUAL}`。
- **J-3**:若 `declared_minor == "1.0"`,`capability_bits` 字段 MUST 为 `null`,`field_support` 中 1.1 相关字段 MUST 全部为 `"skipped"`。
- **J-4**:`characteristics` 键按 `AA440AAx` 的 x 升序。

---

## 5. 一致性检查项清单(C1..C12)

### KBP 1.0(**沿用**,仅重实现为 bleak)

| ID | Level | 检查内容 |
|----|-------|---------|
| C1 | REQUIRED | 服务 `AA440AA0-…` 存在,特征 `AA440AA1-…` 具 READ+NOTIFY+CCC |
| C2 | REQUIRED | READ 返回 ≥ 2 字节,`[layer_index][mods][layer_name]`,`layer_name` 有效 UTF-8 / 空且无尾部 NUL |
| C3 | REQUIRED | 布局/修饰键变化 → NOTIFY 发送;snapshot 未变 → 抑制 |
| C4 | REQUIRED | 已连接后仍可通过 connected-peripheral 枚举发现(即键盘已停止广播) |
| C5 | RECOMMENDED | GAP 名非空(缺失 = WARN) |
| C6 | REQUIRED(split) | 特征仅从 central 暴露(**MANUAL**,主机无法直接验证) |

### KBP 1.1(**新增**)

| ID | Level | 检查内容 |
|----|-------|---------|
| C7  | REQUIRED(if present) | `AA440AA2-…` 若存在:properties = READ+NOTIFY,带 CCC |
| C8  | REQUIRED(if present) | Connectivity READ ≥ 7 字节,各字段符合 contracts/protocol-kbp11.md §3 的 P-C1..P-C4 |
| C9  | REQUIRED(if present) | `AA440AA3-…` 若存在:properties = READ+NOTIFY,带 CCC;payload 长度与 is_split 一致 |
| C10 | REQUIRED(if present) | Connectivity 状态变化触发 NOTIFY;snapshot 未变抑制 |
| C11 | RECOMMENDED(if present) | Battery NOTIFY 节流符合 ≥ 1 pp 或 ≥ 1s **或**规则(观察期内;违规 = WARN) |
| C12 | REQUIRED(split) | 1.1 特征仅从 central 暴露(**MANUAL**) |

### SKIP 规则

- 当 `AA440AA2-…` 不存在时,C7–C12 整列 SKIP(人类可读显示 `-`、JSON 显示 `"SKIP"`)。
- 当 `AA440AA3-…` 不存在但 `AA440AA2-…` 存在时,仅 C9/C11 SKIP。

---

## 6. 实现要求

### 6.1 BLE 后端

- MUST 使用 `bleak>=0.21`(macOS 12+ / BlueZ 5.56+ / WinRT 10.0.17134+ 都在支持范围)。
- MUST 通过 `BleakScanner.discover()` + 已连接外设枚举识别键盘;macOS 下允许直接走 `CoreBluetooth.retrieveConnectedPeripherals`(经由 bleak 封装)。
- SHOULD NOT 使用 raw-HCI 工具(`hciconfig` / `bluetoothctl`),否则无法跨 Windows。

### 6.2 可观测性

- 对所有 BLE 原始事件(connect / disconnect / notify / write)用 `logging.getLogger("conformance")` 以 DEBUG 级别输出,`--verbose` 启用。
- 不写文件日志;遵循"stdout = 结论,stderr = 诊断"的 CLI 惯例。

### 6.3 依赖最小化

- `requirements.txt` 增加 `bleak>=0.21`。
- 保留 `pyobjc-framework-CoreBluetooth`(供 `conformance_tool_macos.py` 使用),但新工具 MUST **不** import PyObjC。

### 6.4 单元可测性

- Payload 解析逻辑 MUST 封装为**纯函数**(例如 `parse_connectivity(data: bytes) -> ConnectivityPayload`),与 BLE I/O 完全解耦,便于 pytest 单测在无硬件下运行。
- `tests/` 目录(可选,`conformance/tests/` 下)覆盖:C2/C8 的 happy path、短 payload、长 payload、保留位、能力位冲突。

---

## 7. 向后兼容与迁移

- **保留 PyObjC 工具**:`git mv conformance/conformance_tool.py conformance/conformance_tool_macos.py`,然后创建新 `conformance_tool.py`。旧工具保留原功能(KBP 1.0 only / macOS only),作为:
  - macOS 原生快速自测;
  - `bleak` 未安装时的 fallback;
  - 回归比对参考。
- **README 指引**:实施阶段的 `conformance/CONFORMANCE.md` MUST 加一节 "macOS legacy tool" 说明两者关系。
- **CI 考虑**:如果仓库有 CI,跨平台 CLI 可以在 macOS runner 上跑一轮 `--json` 冒烟并断言 `exit_code == 2`(no keyboard = env error),确保脚本本身不坏。

---

## 8. 与其他契约的关系

- 本契约的字段级定义(§4.1 / §4.2)**MUST** 与 `contracts/protocol-kbp11.md` 的 wire 定义一字一句对齐;若发现偏差,wire 契约优先。
- 本契约的输出 schema(§4.1 JSON)**MAY** 被 `quickstart.md` 的端到端脚本直接消费。
