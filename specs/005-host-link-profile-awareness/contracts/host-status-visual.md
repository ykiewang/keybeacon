# Contract: 五态主机状态视觉编码（host-status-visual）

**Purpose**: 给 `LocalHostStatus` 五态定义**唯一**的颜色 + 符号 + 文案映射，供 **完整模式**（卡片内「此电脑」行）与**精简模式**（单行 profile 指示点）**逐字复用**。两端（macOS `FloatingPanel` / Windows `MainViewModel`）与两模式 MUST 共用同一套编码，禁止各写一套（FR-016，constitution §III parity）。

**实现约束**：把映射抽成各自的**单一纯函数/静态表**（macOS `HostStatusVisual`、Windows `HostStatusVisual`），UI 只消费其结果。纯函数无 I/O，可穷举单测（FR-014）。

## V-1 编码表（单一真相源）

| 状态 | 颜色 | 符号 | 点样式 | 完整模式文案 | 精简模式 | 无障碍 |
|------|------|------|--------|--------------|----------|--------|
| `inUseHere` | 绿 `systemGreen` | ● | 实心圆 | 正在此电脑使用 / In use on this computer | 绿实心点 + `P{N}` | 形状=实心 |
| `activeElsewhere(slot:N)` | 橙 `systemOrange` | ◐ | 半填充 + 尾随 `▸P{N}` | 键盘正在另一台电脑使用(P{N}) / Keyboard active on another computer (P{N}) | 橙半填充点 + `P{active}` | 形状=半填充；数字给出目标 |
| `onUsb` | 蓝 `systemBlue` | ◆ | 菱形 | 键盘在 USB 输出(非本 BLE 链路) / Keyboard on USB (not this BLE link) | 蓝菱形 + `USB` | 形状=菱形 |
| `cannotDetermine` | 灰 `systemGray` | ○ | 空心圆 | 无法确定 / Cannot determine | 灰空心点 + `P{N}` | 形状=空心 |
| `disconnected` | 红 `systemRed` | ✕ | 叉 | 未连接 / Disconnected | 红叉 + `—` | 形状=叉（区别于空心） |

颜色分配理由：**绿=本机**（既有约定）、**橙=他机**（蓝已让给 USB，橙/绿对色盲更可分）、**蓝=USB**（既有）、**灰=未知**（既有）、**红=未连接**（比原灰色更醒目，符合「断开应是告警」直觉）。

## V-2 规则

- **V-2.1 单一真相源**：颜色/符号/文案只在一处定义；完整与精简两视图都调用它，改动一处即两端两模式同步。
- **V-2.2 三重冗余**：任何状态都同时给出 颜色 + 符号(形状) + 文案/悬停完整文案（精简模式无内联文字时，`tooltip` 提供完整一句话）。**禁止**仅靠颜色区分（WCAG 1.4.1，FR-016）。
- **V-2.3 灰色语义拆分**：`cannotDetermine` 与 `disconnected` MUST 视觉可分（空心灰 vs 红色叉），不得都渲染成灰点。
- **V-2.4 老固件回退**：未发现 AA4（老固件）→ 按 `cannotDetermine` 编码（灰空心），不臆造 in-use/elsewhere。
- **V-2.5 陈旧态**：字段陈旧时沿用既有 alpha 0.5 淡化；陈旧不改变颜色/符号语义。
- **V-2.6 parity**：macOS `HostStatusVisual` 与 Windows `HostStatusVisual` 的颜色集合、符号字符、映射分支逐条对齐；测试用例一一对应。

## V-3 精简模式信息预算

精简模式只允许：**一个状态点 + profile 标签**（+ `activeElsewhere` 时尾随目标 `▸P{N}`）。不得把完整文案塞进精简行；完整语义通过点样式 + 悬停 tooltip 传达。

## V-4 测试向量

纯函数 `visual(for status)` 输出 `(color, symbol, compactText, tooltip)`，对五态逐一断言（两端各一套用例、逐条对齐）：

| 输入 | 期望 color | 期望 symbol | 期望 compactText 含 |
|------|-----------|-------------|---------------------|
| `.inUseHere` | green | ● | `P{local}` |
| `.activeElsewhere(3)` | orange | ◐ | `P3` |
| `.onUsb` | blue | ◆ | `USB` |
| `.cannotDetermine` | gray | ○ | `P{local}` |
| `.disconnected` | red | ✕ | `—` |
