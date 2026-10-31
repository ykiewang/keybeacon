# Implementation Plan: macOS / Windows 客户端双语切换（中英文用户可选）

**Branch**: `feat/bilingual-ui-language` | **Date**: 2026-10-31 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/004-bilingual-ui-language/spec.md`

## Summary

为 KeyBeacon 的两个桌面客户端（macOS `app/macos`、Windows `app/windows`）提供中英文用户可选切换。核心做法：统一引入三态语言偏好（跟随系统 / 中文 / English），在各自既有设置存储中持久化；启动时按偏好解析出实际语言；在菜单栏 / 托盘菜单暴露「语言」子菜单，切换后**立即**重建全部可见界面（无需重启）。

两端现状不同：
- **Windows** 已有完整的本地化栈（`LocalizationService` + `Resources.resx`(en) + `Resources.zh-CN.resx`(zh) + `UiCulturePreference` 枚举 + `AppSettings.UICulture`），只缺托盘「语言」菜单入口与「立即生效」编排。
- **macOS** 目前所有可见文案硬编码为中文，无本地化层。本 feature 需新增本地化资源层、抽取全部可见字符串，并接入「语言」菜单与持久化。

## Technical Context

**Language/Version**: Swift 5.9（macOS 12+，SwiftPM 包 `app/macos/Package.swift`）；C# / .NET（Windows 10 2004+ / 11，项目 `app/windows/src/KeyBeacon.App`）

**Primary Dependencies**: macOS — AppKit；Windows — WPF + H.NotifyIcon；两端共享 `protocol/` 线协议（本 feature 不改协议）

**Storage**: macOS — `UserDefaults`（`AppSettings.swift`）；Windows — `%LOCALAPPDATA%\KeyBeacon\settings.json`（`AppSettings.cs`，System.Text.Json）

**Testing**: macOS — XCTest（`app/macos/Tests/BleWidgetTests`）；Windows — xUnit（`app/windows/tests/KeyBeacon.Core.Tests`）

**Target Platform**: macOS 12+（菜单栏 accessory app）；Windows 10 2004+ / Windows 11（托盘 app）

**Project Type**: desktop-app（双平台原生实现，共享协议，不引入跨语言 core/FFI）

**Performance Goals**: 语言切换后 UI 重建在 1 秒内完成（SC-002）；切换不阻塞 BLE 状态更新

**Constraints**: 不本地化协议 / BLE GAP 字段（层名、设备名）；不本地化结构化诊断日志；简体中文 + 英文两语，其它区域回退英文

**Scale/Scope**: 双端 UI 文案约 50 条（Windows 现有 49 条 resx key，macOS 需对齐并补齐面板文案）；新增 1 个菜单子系统 + 1 个偏好字段 + 1 个解析函数

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | 评估 | 结论 |
|-----------|------|------|
| I. Wire-Contract Self-Containment | 本 feature 不触碰 `protocol/`、不改 wire 格式 | PASS |
| II. Backward Compatibility | 语言偏好为纯客户端本地设置，不影响协议字节布局 | PASS |
| III. Identity From Protocol, Not Branding | 明确不本地化层名 / 设备名，身份仍来自协议与 GAP（FR-013） | PASS |
| IV. Observable Degradation Over Guessing | 缺失翻译回退英文、再回退 key，不伪造不空白；诊断日志保持语言无关（FR-010, FR-015） | PASS |
| V. Spec-First Development | 本 feature 经 specify → plan → tasks 流程，改动 `app/*/Sources` 有可追溯 spec | PASS |
| VI. Bilingual Normative Docs | `spec.md` / `plan.md` / `research.md` 为仓库内部工作文档，豁免；`protocol/**` 等规范性文档本 feature 不修改 | PASS |

**门禁结论**: 无违规，无需 Complexity Tracking。

## Project Structure

### Documentation (this feature)

```text
specs/004-bilingual-ui-language/
├── plan.md              # 本文件
├── spec.md              # 规格（已存在）
├── research.md          # Phase 0：技术决策（本地化机制选型、回退策略）
├── data-model.md        # Phase 1：LanguagePreference / ResolvedLanguage / LocalizedString
├── quickstart.md        # Phase 1：双端验证场景
├── checklists/
│   └── requirements.md  # 规格质量清单（已存在）
└── tasks.md             # Phase 2（由 /speckit-tasks 生成，非本命令）
```

### Source Code (repository root)

```text
app/macos/
├── Package.swift
├── Sources/
│   ├── BleWidgetCore/
│   │   ├── AppSettings.swift        # 新增 languagePreference 持久化 + ResolvedLanguage 解析
│   │   └── Localization.swift       # 新增：L10n 字符串表（en / zh-CN）+ 回退
│   └── BleWidget/
│       ├── AppDelegate.swift        # 抽取硬编码文案 + 新增「语言」子菜单 + 切换后重建
│       └── FloatingPanel.swift      # 抽取硬编码文案（标题/状态/电量/输出/提示/无障碍标签）
└── Tests/BleWidgetTests/
    └── LocalizationTests.swift      # 新增：解析与回退的纯函数测试

app/windows/
├── src/KeyBeacon.App/
│   ├── Localization/
│   │   ├── LocalizationService.cs   # 已存在；复用
│   │   ├── Resources.resx           # 补 Menu_Language / Menu_LanguageSystem / Menu_LanguageEnglish / Menu_LanguageChinese
│   │   └── Resources.zh-CN.resx     # 同上中文
│   ├── Settings/AppSettings.cs      # 已存在 UiCulturePreference；复用
│   ├── Ui/TrayController.cs         # 新增「语言」子菜单 + LanguageSelected 事件 + SetLanguage
│   └── App.xaml.cs                  # 接入 LanguageSelected → 持久化 → 重建 loc/vm/panel/tray
└── tests/KeyBeacon.Core.Tests/
    └── LocalizationTests.cs         # 可选：ResolveCulture 映射测试
```

**Structure Decision**: 沿用两端既有桌面 app 结构。macOS 新增一个 Core 层 `Localization.swift`（纯函数 + 静态字符串表，可无 UI 单测），Windows 复用既有 `LocalizationService`。两端各自原生实现，互不依赖（spec Edge Case）。

## Phase 0: Research

见 [research.md](./research.md)。关键决策：
- **macOS 本地化机制**：采用 `Localization.swift` 内的静态 `[Language: [String: String]]` 字符串表 + `L10n` 访问器，而非 `.strings`/`.xcstrings` 资源包——理由：SwiftPM executable target 不含 App bundle 资源处理流程、`.build` 运行期加载 `.lproj` 需 bundle 配置，静态表更可控、可单测、回退逻辑集中（对齐宪法 IV）。
- **Windows 复用既有栈**：`LocalizationService` + resx 已具备 zh-CN / en 回退（`Get()` 返回 key 兜底），仅补菜单与编排。
- **立即生效策略**：两端均为「重建」而非「增量刷新」——重建菜单 + 重新渲染面板；Windows 现有 `_loc` / `_viewModel` / `_panel` / `_tray` 需按新 culture 重建（或在 culture 变更后统一 `Apply` 一次 snapshot）。

## Phase 1: Design

- [data-model.md](./data-model.md)：`LanguagePreference`、`ResolvedLanguage`、`LocalizedString`。
- [quickstart.md](./quickstart.md)：双端 Given/When/Then 验证场景。
- contracts/：本 feature 为纯 UI 本地化，无对外接口契约（不产生 contracts 目录）。

### Constitution Check (post-design)

重跑六原则，结论与上表一致：全部 PASS，无新增违规（本地化仅作用于 UI 层，协议零改动，退化路径诚实）。

## Complexity Tracking

无宪法违规，无需填写。
