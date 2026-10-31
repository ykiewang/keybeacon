# Tasks: macOS / Windows 客户端双语切换（中英文用户可选）

**Feature**: `specs/004-bilingual-ui-language` | **Date**: 2026-10-31

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, quickstart.md ✓

**Organization**: 按「共享 Core → macOS UI → Windows UI → 验证」排列。两端可独立交付。

## Phase 1: Setup

- [x] T001 确认分支 `feat/bilingual-ui-language` 与 `.specify/feature.json` 指向本 feature

## Phase 2: macOS Core 本地化层

- [x] T002 在 `app/macos/Sources/BleWidgetCore/` 新增 `Localization.swift`：`LanguagePreference` 枚举（system/chinese/english）、`ResolvedLanguage` 枚举（zh-CN/en）、`resolve(preference:systemCode:)` 纯函数、`L10n` 静态字符串表（en + zh-CN，key 对齐 Windows resx）与 `text(_:language:)` 回退访问器
- [x] T003 在 `app/macos/Sources/BleWidgetCore/AppSettings.swift` 新增 `languagePreference` 持久化（`UserDefaults` key `uiLanguage`，默认 system，损坏值回退 system），并暴露解析后的 `resolvedLanguage`
- [x] T004 新增 `app/macos/Tests/BleWidgetTests/LocalizationTests.swift`：三态解析（zh-Hans/zh-Hant/en-US/ja-JP）、缺失 key 回退、带占位符整体渲染

## Phase 3: macOS UI 接线

- [x] T005 `app/macos/Sources/BleWidget/AppDelegate.swift`：新增「语言」子菜单（三态单选，checkmark 反映 preference），新增 `setLanguage(_:)` 动作：写偏好 → 更新 `L10n.currentLanguage` → `panel.applyLanguage()` → 重建菜单；`buildMenu` / tooltip 硬编码中文改为 `L10n`
- [x] T006 `app/macos/Sources/BleWidget/FloatingPanel.swift`：所有硬编码中文改为 `L10n`；新增 `applyLanguage()` 重渲染静态文案并重放缓存状态；`PinnedCorner/DisplayMode.displayName` 改为经 `L10n` 取
- [x] T007 `swift build` 通过，`swift test` 全绿（101 tests, 0 failures）

## Phase 4: Windows 接线

- [x] T008 `Resources.resx` 与 `Resources.zh-CN.resx` 各补 `Menu_Language` / `Menu_LanguageSystem` / `Menu_LanguageEnglish` / `Menu_LanguageChinese` / `Dialog_Ok` / `Dialog_Cancel`
- [x] T009 `TrayController.cs`：新增「语言」子菜单 + 三态单选 + `LanguageSelected` 事件 + `SetLanguage(pref)` 选中态同步
- [x] T010 `App.xaml.cs`：`BuildTray()` 抽取；接入 `LanguageSelected` → 持久化 `_settings.UICulture` → 重建 `_loc` → `MainViewModel.SetLocalization` + 重放缓存 snapshot → 重建 tray 菜单；`MainViewModel` 增 `SetLocalization`
- [x] T011 (`dotnet build` 本机不可用，改用 resx XML 校验 + key 对齐 + C# 静态审查)

## Phase 5: Verification

- [x] T012 macOS：`swift build` + `swift test` 全绿
- [x] T013 Windows：resx XML 合法、en/zh key 完全对齐（55/55）、C# API 引用核对（无 dotnet 环境）
- [x] T014 对照 quickstart.md 逐条核对代码可验证部分

## 依赖

- T002 → T003 → T005/T006（macOS 依赖 Core 层）
- T008 → T009 → T010（Windows 资源 → 菜单 → 编排）
- T007 依赖 T002–T006；T011 依赖 T008–T010
