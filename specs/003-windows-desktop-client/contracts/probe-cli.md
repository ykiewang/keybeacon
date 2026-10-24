# Contract: Phase 0 可行性 probe CLI（probe-cli）

**Feature**: `specs/003-windows-desktop-client` | **Phase**: 0 | **满足**: FR-014；SC-006
**Project**: `app/windows/tools/KeyBeacon.Probe`（`net8.0-windows10.0.19041.0`，`[MTAThread]` 入口）

最小命令行工具，在真实 Windows 主机 + 真实 KBP 键盘上验证 research.md §2 的 P1–P6，产出可审阅的 run log。probe 复用 `KeyBeacon.Core`（解析器），其 WinRT BLE 封装即正式客户端的地基。

## CLI-1 调用

```
KeyBeacon.Probe [--device <DeviceInformation.Id>] [--timeout <seconds>] [--json <path>] [--verbose]
```

| 参数 | 默认 | 说明 |
|------|------|------|
| `--device` | 无（枚举并交互/取首个 supported） | 指定目标设备 Id，跳过选择 |
| `--timeout` | 10 | 单个 GATT async 调用超时（秒），用于验证 P6 陈旧连接 |
| `--json` | stdout | run log 写入路径（JSON）；省略则打印到 stdout |
| `--verbose` | off | 打印每次 async 调用耗时与原始字节 hex |

## CLI-2 执行步骤（映射 P1–P6）

1. **P1**：确认入口在 MTA；发起一次 WinRT 异步并确认非挂起返回。
2. **P2**：`GetDeviceSelectorFromConnectionStatus(Connected)` + `FindAllAsync`，打印已连接设备列表（Id + Name）。
3. 选定设备（`--device` 或首个在 P4 判定 supported 者）。
4. **P3**：建立 GATT 连接后保持 N 秒，提示操作者在键盘上打字，记录是否中断（人工确认 + 记录）。
5. **P4**：发现 service/char，打印 `AA0/AA1/AA2/AA3` 命中情况 + `KbpUuids.Classify` 结果。
6. **P5**：`ReadValueAsync(AA1)` 一次；订阅 Notify；提示操作者切层/按修饰键；收到首个 `ValueChanged` 打印 payload hex 并用 `KeyBeacon.Core` 解析出层名/修饰键。
7. **P6**：对每个 GATT async 记录耗时；若触碰超时记为 timeout（非阻塞，喂给实现默认超时值）。

## CLI-3 输出（run log JSON schema）

```json
{
  "timestamp": "2026-10-24T12:00:00Z",
  "host": { "osVersion": "...", "arch": "x64", "dotnet": "8.0.x" },
  "checks": {
    "P1_mta":            { "pass": true,  "detail": "..." },
    "P2_enumerate":      { "pass": true,  "devices": [{ "id": "...", "name": "Corne" }] },
    "P3_hid_coexist":    { "pass": true,  "detail": "typing uninterrupted (operator-confirmed)" },
    "P4_services":       { "pass": true,  "classify": "supported", "chars": ["AA1","AA2","AA3"] },
    "P5_read_subscribe": { "pass": true,  "firstNotifyHex": "02 22 4e 61 76", "parsedLayer": "Nav", "mods": "shift" },
    "P6_stale_timeout":  { "pass": true,  "observedMaxMs": 420, "note": "no stale device encountered" }
  },
  "verdict": "PASS"
}
```

## CLI-4 退出码

| 码 | 含义 |
|----|------|
| 0 | 全部**阻塞项**（P1–P5）PASS → 门禁开，推进 Phase 1 |
| 1 | 某阻塞项 FAIL → 触发 research §3 回退评估 |
| 2 | 环境错误（无蓝牙适配器 / 无已连接键盘 / 权限） |
| 3 | 参数错误 |

> P6 为非阻塞：即使触碰超时也不单独致 verdict FAIL，但其 `observedMaxMs` MUST 记录，供实现设定连接超时默认值。

## CLI-5 结论回填

probe 运行后，其 verdict 与 checks MUST 回填到 [research.md §5](../research.md) 的「真机验证结论」表，作为 Phase 1 实现的门禁依据（SC-006：结论有据可查）。
