# Quickstart: 双语切换验证

**Feature**: `specs/004-bilingual-ui-language` | **Date**: 2026-10-31

本文件给出双端的可运行验证场景，映射到 spec.md 的 FR / SC。命令均在仓库根 `specs/004-bilingual-ui-language` 的上级（仓库根）执行。

## 先决条件

- macOS 12+，Xcode Command Line Tools（`swift --version` 可用）
- Windows 10 2004+ / 11，.NET SDK 8.0（`dotnet --version` 可用）
- 一把已实现 KBP 的键盘（可选，用于实时状态联动；仅验证本地化可无键盘）

---

## macOS

### 构建

```bash
cd app/macos
swift build
swift test          # 含 LocalizationTests：解析 + 回退 + 占位符
swift run BleWidget
```

### 场景

- **SC-002 / FR-003 / FR-005 / FR-012 — 即时切换 + 选中态**
  1. 启动 `swift run BleWidget`，点菜单栏图标。
  2. 打开「语言」子菜单：应为「跟随系统 / 中文 / English」，当前生效项打勾。
  3. 选 English → 菜单项、悬浮窗标题、状态文本、电量/输出文案**立即**变英文，无需重启。
  4. 再选中文 → 立即变中文。断言项：`Menu_*`、`State_*`、`Conn_*`、`Battery_*`、`Output_*`、`Corner_*` 全部随语言切换。

- **SC-003 / FR-004 — 持久化**
  1. 选 English，`killall BleWidget`（或菜单退出）。
  2. 重新 `swift run BleWidget` → 仍为英文。

- **SC-004 / FR-002 — 跟随系统**
  1. `defaults delete com.<your.bundle.id> uiLanguage`（或首次运行）。
  2. 系统区域为中文时启动 → 中文；`defaults write ... AppleLanguages -array en` 或英文系统 → 英文；`ja` → 英文兜底。

- **SC-001 / FR-007 / FR-013 — 抽取完整性 + 不翻译协议字段**
  1. 在两种语言下肉眼扫描菜单与面板，确认无残留中文（英文模式下）/ 无残留英文（中文模式下）。
  2. 连接键盘，切换层：层名按键盘上报原样显示，**不**随语言翻译；设备名同理。

- **SC-006 / FR-009 / FR-010 — 占位符与回退**
  - 单测覆盖：`swift test --filter LocalizationTests` 应全绿，含：
    - zh 缺失某 key → 回退英文；en 亦缺 → 返回 key。
    - `Battery_Percent` 在 zh / en 均整条渲染。

---

## Windows

### 构建

```bash
cd app/windows
dotnet build src/KeyBeacon.App/KeyBeacon.App.csproj
dotnet test tests/KeyBeacon.Core.Tests/KeyBeacon.Core.Tests.csproj
dotnet run --project src/KeyBeacon.App/KeyBeacon.App.csproj
```

### 场景

- **SC-002 / FR-003 / FR-005 / FR-012 — 即时切换 + 选中态**
  1. 右键托盘图标 → 打开「语言 / Language」子菜单（三态：跟随系统 / 中文 / English）。
  2. 选「English」→ 托盘菜单、悬浮窗、状态文本立即变英文（无需重启）。
  3. 再选「中文」→ 立即变中文；选中态勾选当前项。

- **SC-003 / FR-004 — 持久化**
  1. 选 English → 退出（菜单 Quit）。
  2. 重新 `dotnet run` → 仍 English（`%LOCALAPPDATA%\KeyBeacon\settings.json` 中 `UICulture: "English"`）。

- **SC-004 / FR-002 — 跟随系统**
  1. 首次运行（无 settings.json），系统区域中文 → 中文；英文 → 英文。

- **SC-005 / FR-008 — 无硬编码残留**
  - 审查 `app/windows/src`：所有 `MenuItem.Header` / VM 文案均经 `_loc.Get(...)`；新增 `Menu_Language*` 四键在 `Resources.resx` 与 `Resources.zh-CN.resx` 各有一条。

---

## 两端一致性断言（SC-001 / FR-011）

| 检查点 | macOS | Windows |
|--------|-------|---------|
| 菜单 + 面板 + 对话框同时切换 | 重建 `statusItem.menu` + 重渲染 `panel` | 重建 `TrayController` + `FloatingPanel`（或 refresh + 重放 snapshot） |
| 选中态反映 preference 原值 | 「语言」子菜单 checkmark | 「Language」子菜单 IsChecked |
| 协议字段不翻译 | 层名 / 设备名原样 | 层名 / 设备名原样 |
| 诊断日志不翻译 | `DiagnosticsLogger` 不变 | `DiagnosticsLogger` / Serilog 不变 |

## 期望结果

- 两端在中文与英文两套资源下，全部可见文案 100% 覆盖（SC-001）。
- 语言切换 < 1s 完成，无需重启、不中断 BLE 状态（SC-002）。
- 重启保持偏好（SC-003）；首装跟随系统并英文兜底（SC-004）。
