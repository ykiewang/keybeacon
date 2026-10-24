# Contract: 诊断包（diagnostics-bundle）

**Feature**: `specs/003-windows-desktop-client` | **Phase**: 1 | **满足**: FR-018, FR-022, FR-023, FR-024, FR-025；US6；SC-011, SC-012

面向开源后的 issue 定位：用户一键导出一个可分享文件，维护者仅凭它即可定位多数连接/解析问题，无需用户本地开发环境、无需远程访问硬件。

## B-1 日志持久化（FR-022）

- 位置：`%LOCALAPPDATA%\KeyBeacon\logs\keybeacon-.log`（Serilog rolling file）。
- 滚动上限：按天 + 按大小双限（默认：单文件 ≤ 10 MB，保留 ≤ 7 个 / 7 天，取先到者）。重启后近期历史仍可用（US6 场景 4）。
- 格式：结构化行（时间戳、级别、category、事件名、键值字段），字段对齐 [research.md §4](../research.md)。
- 每个降级事件恰好一条（FR-018）；常规级别只记降级+关键生命周期事件，空闲零噪声。

## B-2 详细日志开关（FR-024）

- `Settings.VerboseLogging`（托盘菜单可切）。
- 详细模式额外记录：成功解析路径、每次 notify 的**原始 payload hex**、GATT 发现的 service/char 列表、各 async 调用耗时。用于复现偶发问题（US6 场景 2）。
- 常规模式 MUST NOT 记录原始 payload（降噪 + 隐私）。

## B-3 诊断包内容（FR-023 / SC-012）

导出单一 `.zip`（`System.IO.Compression`），至多 3 步从托盘菜单生成（SC-011）：

```
keybeacon-diagnostics-{yyyyMMdd-HHmmss}.zip
├── environment.json        # 见 B-4
├── logs/                   # 近期滚动日志文件副本（受 B-1 上限约束）
│   └── keybeacon-*.log
└── README.txt              # 包说明 + 维护者阅读指引（中英，见 Principle VI）
```

## B-4 环境信息（environment.json，FR-023）

| 字段 | 示例 | 脱敏 |
|------|------|------|
| appVersion | `1.1.0` | — |
| osVersion | `Windows 11 23H2 (build 22631)` | — |
| architecture | `x64` / `arm64` | — |
| dotnetRuntime | `.NET 8.0.x` | — |
| bluetoothAdapter | 适配器型号/厂商 + 状态（on/off） | 保留型号，省略地址 |
| detectedKbpVersion | `1.0` / `1.1(hasBattery)` / `unsupported` | — |
| keyboards[] | 每把：displayName、形态、连接状态、能力位 hex | **见 B-5** |
| capabilityByte / lastConnectivityHex / lastBatteryHex | 最近原始值（仅详细模式） | — |

## B-5 脱敏与知情（FR-025 / US6 场景 3）

- 潜在可识别字段（设备名、蓝牙地址/标识符）MUST 默认**省略或打码**：
  - 蓝牙地址/`DeviceInformation.Id` → MUST 省略或哈希，NOT 明文。
  - 设备名（用户可能自定义含姓名）→ 默认保留**首个 token + 长度**（如 `Corne-***(12)`）；用户可在导出前选择包含完整名。
- 导出前 MUST 向用户呈现「将包含哪些信息」的审阅点（对话框/摘要），用户确认后再写盘，使其自行决定是否分享。
- README.txt MUST 声明本包可能包含的可识别信息与脱敏策略（中英双语）。

## B-6 验收点

- SC-011：托盘菜单 → 导出 → 确认审阅，≤ 3 步得到 `.zip`，无需外部工具。
- SC-012：包内含 app/os/协议版本 + 近期降级事件 + （详细模式下）失败 payload，足以离线定位一个典型连接/解析问题。
