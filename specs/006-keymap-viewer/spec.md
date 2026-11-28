# Feature Specification: 键位图速查（Keymap Viewer）

**Feature Branch**: `006-keymap-viewer`

**Created**: 2026-11-26

**Status**: Draft

**Input**: User description: "用户在换了新键盘、想不起键位时，可以在 KeyBeacon macOS app 里快速唤醒一张按键形状的键位图，完全自动，零配置零维护；键位数据和物理布局坐标直接从固件读取，通过新增 KBP BLE 特征，参考 ZMK physical_layout 机制，首次拉全量并缓存，后续用 CRC32 探测避免冗余传输"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 快速唤醒键位图 (Priority: P1)

用户换了新键盘，记不清某个 layer 的键位，在不离开当前工作窗口的情况下，按全局快捷键或点菜单栏「键位图」选项，1~2 秒内看到按键形状的键位图浮窗，确认后再按一次快捷键或点关闭按钮关闭浮窗。

**Why this priority**: 这是本 feature 的全部价值所在——最短路径、零思维负担地查到键位，不能有任何前置配置步骤。只实现这一条就已经是可交付的 MVP。

**Independent Test**: 连接一把已支持 KBP 1.3 的键盘，冷启动 app，按快捷键，计时到浮窗完整渲染（含按键形状和标签）。

**Acceptance Scenarios**:

1. **Given** 键盘已连接且本地无缓存，**When** 用户首次按快捷键，**Then** 浮窗在 2 秒内出现，显示 layer 0 的全部按键形状与 keycode 标签。
2. **Given** 本地已有有效缓存（CRC 未变），**When** 用户再次按快捷键，**Then** 浮窗在 300ms 内出现（从缓存直接渲染，无 BLE 传输）。
3. **Given** 键盘已刷新固件（CRC 变化），**When** app 重新连接后用户按快捷键，**Then** 浮窗先显示旧缓存内容，后台静默刷新，刷新完成后无缝更新显示。
4. **Given** 浮窗已打开，**When** 用户再次按同一快捷键，**Then** 浮窗关闭（toggle 行为）。

---

### User Story 2 - Layer 切换与实时跟随 (Priority: P1)

用户在浮窗中手动切换 layer，图示内容实时更新；同时当键盘物理激活某 layer 时（KBP 1.0 现有 layer-index notify），浮窗顶部的选择器自动高亮当前活跃 layer，但不强制覆盖用户正在查看的 layer。

**Why this priority**: 多 layer 是 ZMK 用户的核心使用模式，查键位的绝大多数场景都发生在非默认 layer。

**Independent Test**: 在键盘上按住 layer-tap 键切换 layer，观察浮窗 segmented control 是否同步高亮。

**Acceptance Scenarios**:

1. **Given** 浮窗已打开且显示 layer 0，**When** 用户点击 layer 2 选项，**Then** 浮窗内所有按键标签切换为 layer 2 的绑定值，物理布局形状不变。
2. **Given** 浮窗已打开，**When** 键盘通过 KBP 1.0 notify 上报 layer 3 激活，**Then** 浮窗 segmented control 自动高亮 layer 3 标签，但用户当前查看的 layer 视图不被强制切换。
3. **Given** 键盘有 5 个 layer，**When** 浮窗打开，**Then** segmented control 显示所有 5 个 layer 的名称（来自固件），并默认显示 layer 0。

---

### User Story 3 - 零维护自适应布局 (Priority: P2)

用户切换到另一把已支持 KBP 1.3 的键盘，键位图自动变为新键盘的物理形状，无需任何配置；不支持 KBP 1.3 的老键盘连接时，键位图入口灰显，不崩溃。

**Why this priority**: 多键盘用户场景；布局零维护是本方案相比 JSON 注册表的核心优势，但需要先有 US1 才有意义，因此降至 P2。

**Independent Test**: 先后连接两把不同形状的 KBP 1.3 键盘，确认两次渲染的物理形状各自正确匹配。

**Acceptance Scenarios**:

1. **Given** 用户先连接键盘 A（60% layout），**When** 断开后连接键盘 B（ergo 形状），**Then** 浮窗渲染出键盘 B 的物理形状，不残留键盘 A 的布局或缓存数据。
2. **Given** 连接了一把**不支持 KBP 1.3** 的老键盘，**When** 用户打开菜单栏，**Then** 「键位图」菜单项灰显或显示「当前固件不支持键位图」提示，app 不崩溃，其余功能正常。
3. **Given** 键盘断开连接，**When** 浮窗仍打开，**Then** 浮窗保留最后一次渲染的内容，并以某种方式标示「已断连」状态。

---

### Edge Cases

- 键盘有旋转键（ergo 分体常见）时，每个键的坐标和旋转角度是否正确渲染？
- 单个 layer 的 keycode 数量超过一次 BLE ATT 包时（>122 个键），分包传输是否正确拼合？
- 固件上报的 binding 类型不认识（自定义 behavior）时，显示 `?` 而不是崩溃。
- `&mt` / `&lt` 等双值 binding，只显示 tap 值，不展示 hold 值。
- Layer 名称为空字符串或超长时，UI 是否优雅截断？
- CRC 碰撞（极小概率），导致缓存内容与实际键盘不一致如何处理？→ 提供「强制刷新」菜单项作为逃生门。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: app 在首次连接 KBP 1.3 键盘时，MUST 自动拉取 `KeymapData` 特征的全量数据（物理布局坐标 + 所有 layer 的 keycode 列表）。
- **FR-002**: app 在每次连接时 MUST 先读 `KeymapMeta` 特征的 CRC32，与本地缓存比对；CRC 一致则跳过全量拉取。
- **FR-003**: 缓存 MUST 以 `keyboard_uuid + crc32` 为复合 key 存入 `AppSettings`（`UserDefaults`）；app 重启后有效。
- **FR-004**: 菜单栏 MUST 新增「键位图」选项，点击后弹出 `KeymapPanel`（独立 `NSPanel`，不影响现有 `FloatingPanel`）。
- **FR-005**: MUST 支持配置全局快捷键（`Carbon.RegisterEventHotKey`），唤醒/隐藏 `KeymapPanel`；快捷键存入 `AppSettings`。
- **FR-006**: `KeymapPanel` 顶部 MUST 显示 `NSSegmentedControl`，列出全部 layer 名称（来自固件）。
- **FR-007**: 每个键 MUST 渲染为圆角矩形 + 居中标签，坐标/尺寸来自固件推送的物理布局（单位 0.01u，1u = 54pt）。
- **FR-008**: 旋转键 MUST 使用 `CGContext` per-key 旋转变换渲染，旋转原点来自固件数据。
- **FR-009**: 收到 KBP 1.0 layer-index notify 时，MUST 高亮 `KeymapPanel` 的对应 layer 标签，但 MUST NOT 强制切换用户当前查看的 layer 内容。
- **FR-010**: Binding 渲染按三层处理：
  - **层一（完全静态展开）**：`&kp`（单行大字居中）、`&mt`/`&lt`/`&hold-tap`（双行：hold 值小字在上，tap 值大字在下）、`&mo`/`&to`/`&tog`/`&sl`（显示 layer 名，格式 `MO(Nav)`）、`&sk`（modifier 名 + 角标 `¹`）、`&trans`（显示 `▽`）、`&none`（显示 `✕`）、`&key_repeat`（显示 `↺`）、`&gresc`（显示 `` `/ESC ``）、`&caps_word`（显示 `CAPS▶`）、`&kt`（显示 `KT(A)`）。
  - **层二（简化固定标签）**：`&bt`（显示 `BT(N)`）、`&out`（显示 `USB`/`BLE`）、`&sys_reset`（显示 `RST`）、`&bootloader`（显示 `BOOT`）、`&mkp`/`&mmv`/`&msc`（显示 `MB1`/`↕`/`⟲` 等鼠标简写）、`&rgb_ug`/`&bl`（显示 `RGB`/`BL`）、`&ext_power`/`&soft_off`（显示 `PWR`/`OFF`）、`&studio_unlock`（显示 `STU`）。
  - **层三（无法展开）**：`&td`（Tap Dance，显示 `TD`）、macro（显示 `▶M` 或宏名截断至 4 字符）、`&mod_morph`（显示 `MM`）、其他未识别 behavior（显示 `?`）。
- **FR-011**: 老固件（无 `KeymapMeta` / `KeymapData` 特征）MUST 导致菜单项灰显，`KeymapPanel` 显示「固件不支持键位图」提示，app 不崩溃。
- **FR-012**: MUST 提供菜单项「强制刷新键位图」，触发忽略 CRC 的全量重新拉取。

### Key Entities *(include if feature involves data)*

- **KeymapMeta**（BLE 特征）：CRC32（4 字节）+ layer 数量 + layer 名称列表；`READ` only；用于缓存校验。
- **KeymapData**（BLE 特征）：物理布局（每键 x/y/w/h/r）+ 每个 layer 的 keycode 数组；`READ` + 分块协议；体积较大，仅在 CRC 变化时拉取。
- **KeymapCache**（本地存储）：以 `uuid+crc` 为 key，存储解析后的布局与 keycode 表；存入 `AppSettings`。
- **KeymapPanel**（macOS UI）：独立 `NSPanel`，包含 layer 选择器 + `KeymapView`（CoreGraphics 渲染）。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 有缓存时，快捷键到浮窗完整渲染 P95 ≤ 300ms。
- **SC-002**: 无缓存时，快捷键到浮窗完整渲染 P95 ≤ 2s（含 BLE 全量拉取）。
- **SC-003**: CRC 一致时，连接过程零额外 BLE payload 传输（除 `KeymapMeta` READ 本身的 1 次 transaction）。
- **SC-004**: 老固件键盘连接时，app 无崩溃，新 UI 完全隐藏或灰显，不影响现有 KBP 1.0/1.1/1.2 功能。
- **SC-005**: 旋转键渲染正确，视觉上与实际键盘物理布局匹配，无坐标偏移或旋转方向错误。

## Clarifications

### Session 2026-11-26

- Q: 全局快捷键是否有默认值？→ A: 无默认值。首次连接到 KBP 1.3 键盘时，app 弹出一次引导提示，引导用户设置快捷键；之后不再重复弹出。
- Q: `&mt`/`&lt` 等双值 binding 如何显示 hold 值？→ A: 本版本显示双行标签（KLE 风格）：hold 值小字显示在上方，tap 值大字显示在下方；未识别 behavior 显示 `?`。
- Q: 浮窗大小是否固定？→ A: 不固定，用户可自由拖拽调节浮窗大小（`NSPanel` resizable），键位图按比例缩放。

## Assumptions

- 本 feature 以 **KBP 1.3 MINOR 增量**交付（当前最新为 1.2），新增 `KeymapMeta` 和 `KeymapData` 两个可选 BLE 特征，老版本 app 忽略即可，向后兼容。
- 固件侧需同步升级 `zmk-keybeacon` 模块，序列化 ZMK `physical_layout` 节点坐标与 keymap bindings；本 spec 覆盖 app 侧，固件侧实现细节由 `zmk-keybeacon` 侧 spec/task 覆盖。
- 物理布局坐标来自固件，app 不内置任何键盘型号的布局 JSON。
- Windows 客户端（`003-windows-desktop-client`）不在本 feature 范围内，本次仅覆盖 macOS app。
- 第一版只支持「主显示值」渲染，不支持 hold 值、条件层、宏展开等高级显示。
- 全局快捷键默认无预设值，用户首次使用需手动在菜单中配置一次。
