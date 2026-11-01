# Phase 1 Data Model: 双语切换

**Feature**: `specs/004-bilingual-ui-language` | **Date**: 2026-10-31

本 feature 不涉及网络 / 持久化数据模型变更（协议零改动）。以下为客户端内部的语言偏好与本地化字符串实体。

## Entity: LanguagePreference

用户在菜单中可见的三态语言选择。

| Value | 语义 | 持久化编码（macOS UserDefaults） | 持久化编码（Windows settings.json） |
|-------|------|-------------------------------|-----------------------------------|
| `system` | 跟随操作系统区域（默认） | 字符串 `"system"`（缺省即此值） | 枚举 `"System"` |
| `chinese` | 强制简体中文 | 字符串 `"chinese"` | 枚举 `"Chinese"` |
| `english` | 强制英文 | 字符串 `"english"` | 枚举 `"English"` |

**Validation / 规则**
- 未知 / 损坏的持久化值 → 回退 `system`（不崩溃、不空白）。
- 默认值 = `system`（新装用户零配置，对齐 spec US3）。
- 仅影响 UI 文案，不影响协议字段（FR-013）。

**Stores**
- macOS：`AppSettings`（`UserDefaults` key `uiLanguage`，与 `panelDisplayMode` 等并列）。
- Windows：`AppSettings.UICulture`（既有 `UiCulturePreference` 枚举，`System`/`English`/`Chinese`）。

## Entity: ResolvedLanguage

启动时由 `LanguagePreference` + 系统区域解析出的实际生效语言。

| Value | 资源子集 | 说明 |
|-------|---------|------|
| `zh-CN` | 中文字符串表 / `Resources.zh-CN.resx` | 简体中文 |
| `en` | 英文字符串表 / `Resources.resx`（neutral） | 英文，兼作兜底 |

**解析函数（两端语义一致）**

```
resolve(preference, systemCode):
  switch preference:
    chinese -> zh-CN
    english -> en
    system  -> systemCode.hasPrefix("zh") ? zh-CN : en
```

**规则**
- 启动时解析一次（spec Assumptions：运行中系统语言变化不动态跟随）。
- `system` 模式下非中文区域一律 `en`（US3 AS3 / SC-004）。
- 选中态反映 `LanguagePreference` 原值而非 `ResolvedLanguage`（FR-012）。

## Entity: LocalizedString

由 key 标识的可见文案条目，在两种语言下各一条定义。

| 属性 | 说明 |
|------|------|
| `key` | 稳定标识（`Menu_Language`、`State_Disconnected`、`Conn_Online`、`Battery_Percent`…），两端对齐 |
| `en` | 英文模板 |
| `zh` | 简体中文模板 |
| `hasPlaceholder` | 是否含 `{0}` / `{1}` 等占位符 |

**回退查找（L10n.text）**

```
text(key, language):
  table = strings[language]
  if table[key] != nil: return table[key]
  if strings.en[key] != nil: return strings.en[key]   # 缺失 → 英文
  return key                                            # 英文也缺 → key 本身
```

**带占位符文案（整体渲染，FR-009 / FR-014）**

| key | en | zh |
|-----|----|----|
| `Battery_Percent` | `{0}%` | `{0}%` |
| `Layer_Fallback` | `L{0}` | `L{0}` |
| `State_UpdatedAt` | `updated {0}` | `更新于 {0}` |
| 输出（完整模式） | `Output: USB` 等 | `输出:USB` 等 |
| 输出（保留码，完整模式） | `Output: unknown (0x{0:02X})` | `输出:未知(0x{0:02X})` |

**规则**
- 占位符以整条模板存储，渲染时按 `ResolvedLanguage` 的 Locale 整体格式化，禁止跨语言片段拼接。
- 缺失时按上表回退，绝不返回空串或崩溃（FR-010 / Principle IV）。

## 状态转换（语言偏好）

```
[system] --user picks Chinese--> [chinese] --persist--> 重启后仍 chinese
[system] --user picks English--> [english] --persist--> 重启后仍 english
[chinese|english] --user picks System--> [system] --重启-> resolve(system)
任意 --切换--> 立即重建全部可见 UI（1s 内，FR-003/FR-011）
```

## Key Entities → 实现落点

| Entity | macOS 落点 | Windows 落点 |
|--------|-----------|-------------|
| LanguagePreference | `AppSettings.languagePreference` + `LanguagePreference` enum（`Localization.swift`） | `AppSettings.UICulture` + `UiCulturePreference`（已存在） |
| ResolvedLanguage | `ResolvedLanguage` enum + `resolve(...)`（`Localization.swift`） | `LocalizationService.ResolveCulture(...)`（已存在） |
| LocalizedString | `L10n.strings` 静态表 + `L10n.text(...)` | `Resources.resx` / `Resources.zh-CN.resx` + `LocalizationService.Get(...)` |
