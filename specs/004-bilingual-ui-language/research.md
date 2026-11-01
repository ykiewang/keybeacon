# Phase 0 Research: 双语切换

**Feature**: `specs/004-bilingual-ui-language` | **Date**: 2026-10-31

## R1 — macOS 本地化机制选型

**Decision**: 在 `BleWidgetCore` 新增 `Localization.swift`，内含静态 `Language` 枚举、`LanguagePreference` 枚举、`ResolvedLanguage` 解析函数，以及 `L10n`（字符串表 + 查找/回退）。字符串表以 `[String: String]` 字典按语言分组，key 与 Windows resx 对齐（`Menu_*` / `State_*` / `Conn_*` / `Battery_*` / `Output_*` / `Corner_*` / `Dialog_*`）。

**Rationale**:
- `Package.swift` 声明的 `BleWidget` 是可执行 target，SwiftPM 对 executable 的 `.lproj` / `.strings` 资源在 `swift run` 与 `.app` 打包两条路径上行为不同（需 `Bundle.module` 且仅在 target 声明 `resources:` 时生成）；本项目通过 `packaging/` 脚本构造 `.app`，引入 bundle 资源会增加打包不确定性。
- 静态表是纯数据 + 纯函数，可在 `BleWidgetTests` 里直接单测解析与回退（对齐宪法「Testing & Verification Discipline」：无 BLE 硬件即可测）。
- 回退策略集中一处（`L10n.text(_:language:)`：所选语言 → 英文 → key），避免散落在调用点，对齐 Principle IV。

**Alternatives considered**:
- `.xcstrings`（String Catalog）：需 Xcode 工程与 `Bundle.module`，SwiftPM CLI 流程不适用。
- `.strings` + `NSLocalizedString`：依赖 `Bundle.main` 与运行期 `AppleLanguages` 覆盖，切换要重启或 hack `UserDefaults` 的 `AppleLanguages` 键——不满足 FR-003「立即生效」。
- 每语言一个 swift 文件常量 enum：可行但 key 分散、回退逻辑重复。

## R2 — 立即生效的实现方式（两端）

**Decision**: 「重建」而非「原地刷新」。切换语言 → 更新偏好 → 用新语言重建菜单与面板内容（macOS 重建 `statusItem.menu`、对 `panel` 重新应用一次当前缓存状态；Windows 用新 culture 重建 `LocalizationService`，重建 `MainViewModel` / `FloatingPanel` / `TrayController` 或对其调用 refresh 并重放当前 snapshot）。

**Rationale**: 两端 UI 组件（`NSMenu` 项标题、WPF `MenuItem.Header`、`LabeledValue` 集合）在构造时绑定文案，原地改文案需要为每个控件维护引用与 setter（改造成本高、易漏）。重建路径简单、可测、一次覆盖所有可见面（FR-011 全量同步）。1s 预算充裕（菜单十几项、面板十几个 label）。

**Alternatives considered**:
- 观察者/绑定式本地化（每个控件监听 languageDidChange）：改造面大、WPF 侧要重写 VM 通知链，收益仅是省一次重建，不值得。
- 要求重启生效：违反 FR-003。

## R3 — 「跟随系统」解析与回退

**Decision**: `ResolvedLanguage.resolve(preference:systemLanguageCode:)`：
- `.chinese` → `.chinese`
- `.english` → `.english`
- `.system` → `systemLanguageCode` 以 `zh` 开头 → `.chinese`，否则 `.english`

macOS 取 `Locale.preferredLanguages.first`；Windows 取 `CultureInfo.CurrentUICulture.Name`（既有多语言解析已用 `CultureInfo`）。

**Rationale**: 明确「非中文非英文区域 → 英文」兜底（spec US3 AS3 / SC-004），与 Windows 既有 `LocalizationService.ResolveCulture` 语义一致（`System` → `CurrentUICulture`，而 resx 的 neutral 资源即英文，天然兜底）。macOS 侧必须显式兜底，因为静态表没有「neutral fallback」机制。

**Note**: 「跟随系统」在启动时解析一次；运行中系统语言变化不动态跟随（spec Assumptions / Edge Cases）。

## R4 — 与协议 / 诊断日志的边界

**Decision**: 层名（`KeyboardStatus.layerName`）、键盘设备名（`CompatibleKeyboard.displayName`）、协议版本号一律不经过 `L10n`；`DiagnosticsLogger` / Serilog 输出不经过 `L10n`。

**Rationale**: 宪法 III（身份来自协议）与 IV（诚实降级）；FR-013 / FR-015。日志语言无关也保证维护者工具链解析稳定。

## R5 — 占位符与数值格式

**Decision**: 带占位符文案（电量 `{0}%`、层回退 `L{0}`、更新时间 `更新于 {0}`、输出 `输出:{0}`）在两端均以**整条模板**存储并整体格式化；数值本身（百分比整数、时间 `HH:mm:ss`）沿用各语言 `Locale`/`CultureInfo` 格式化。

**Rationale**: FR-009 / FR-014。避免「中文前缀 + 英文数值单位」碎片拼接。

## R6 — Windows 菜单文案 key 命名

**Decision**: 新增 4 个 key，两端同名：
- `Menu_Language` — 语言
- `Menu_LanguageSystem` — 跟随系统
- `Menu_LanguageEnglish` — English
- `Menu_LanguageChinese` — 中文

**Rationale**: 与既有 `Menu_*` 命名一致；「跟随系统」采用三态单选（勾选态反映实际值，FR-012）。

## R7 — macOS 首个可测单元

**Decision**: `LocalizationTests.swift` 覆盖：① 三态解析（含 zh-Hans / zh-Hant / en-US / ja-JP）；② 缺失 key 回退顺序（zh 缺失 → en；en 也缺 → key 本身）；③ 带占位符文案整体渲染（zh vs en 不混语言）。

**Rationale**: 对齐宪法 Testing Discipline「payload/classification 逻辑用纯函数单测」的精神，本地化解析/回退同属纯函数。
