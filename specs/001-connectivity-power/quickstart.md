# Quickstart: 验证 KBP 1.1 连接与电量指标

**用途**:端到端跑一遍本 feature 的核心路径,确认协议、固件、一致性 CLI、macOS 应用四个
面都接起来了。本文件不含完整实现代码——那些由 `/speckit-tasks` 之后的 implement 阶段
按 `data-model.md` + `contracts/*.md` 产出。

> 执行时间参考:冒烟一轮 ~ 5 min,完整七个剧本 ~ 15 min。

---

## 1. 前置条件

### 1.1 硬件

- 一把**支持 KBP 1.1 的 ZMK 分体键盘**(central + peripheral,固化了 `zmk-keybeacon`
  module 的 1.1 版本);推荐 Totem(本仓库 README 的 reference keyboard)。
- 另一把**仅支持 KBP 1.0 的整板键盘**(用于回归验证 SC-004 的向后兼容)。可以是旧固件
  的同一把 Totem 刷回 1.0 测试。
- 一台 macOS 12+ 主机。

### 1.2 软件

```bash
# macOS 应用:走 Swift Package Manager
cd app/macos
swift build -c release
swift test                             # 跑 XCTest(KBP 1.0 + 1.1 单测)

# 一致性 CLI:跨平台,bleak 后端
python3 -m pip install -U "bleak>=0.21"
python3 conformance/conformance_tool.py --help    # 验证入口可运行

# 协议文档校对
test -f protocol/VERSION && cat protocol/VERSION  # 期望输出 1.1.0
```

### 1.3 蓝牙权限

- macOS "系统设置 → 隐私与安全性 → 蓝牙",允许 Terminal(跑一致性 CLI)+ BleWidget.app 访问蓝牙。
- 键盘已完成一次性配对、且主机上 **已连接**(KBP 的发现是 "connected-peripheral enumeration",未连状态查不到)。

---

## 2. 冒烟:单命令确认链路

```bash
# 1) 协议文档存在且版本正确
cat protocol/VERSION                                      # 1.1.0

# 2) 一致性 CLI 跑一轮,拿 JSON 支持矩阵
python3 conformance/conformance_tool.py --json | tee /tmp/kbp11_matrix.json

# 3) 简单断言(需要 jq)
jq '.declared_minor' /tmp/kbp11_matrix.json               # 期望 "1.1"
jq '.capability_bits.is_split' /tmp/kbp11_matrix.json     # 期望 true(分体键盘下)
jq '.exit_code' /tmp/kbp11_matrix.json                    # 期望 0
```

CLI exit code 为 0 即过冒烟。

---

## 3. 七剧本:手工端到端验证

每个剧本有明确的 **Given / When / Then**,通过与否完全可观察,无需拆开 app 盒子。

### 3.1 剧本 A — Story 1:主机连接 + profile 可见(FR-002/FR-003,SC-001)

| 步骤 | 操作 | 预期观察 |
|------|------|---------|
| Given | 分体键盘 Totem,profile #2 已连上主机 | — |
| When  | 打开 BleWidget 的 FloatingPanel | 面板出现「连接与电量」卡片;主机连接行显示绿点 + "已连接";profile 行显示 5 个徽标,#2 粗边框填充 |
| When  | 键盘上切换到 profile #4(open 状态) | ≤ 1s 内 #4 徽标高亮 + 虚线边框 + "待配对" 文案 |
| Then  | 没有任何额外 UI 占位(例如电量不乱跳) | — |

**通过标准**:两个 When 均 ≤ 1s 完成,SC-002 的 P50 ≤ 1s 得到初步证据。

---

### 3.2 剧本 B — Story 2:分体掉线与每半电量(FR-004/FR-005,SC-003)

| 步骤 | 操作 | 预期观察 |
|------|------|---------|
| Given | 分体键盘左右半均在线,双电量显示(例如 "左 72% / 右 68%") | — |
| When  | 关掉 peripheral(右)半的电源 | ≤ 2s 右半标红 "离线",右侧电量条灰显 + "最后更新 hh:mm:ss" |
| Then  | 左半数字和条形体保持实时,**不**被右半影响 | — |
| When  | 右半开机回连 | ≤ 5s 右半恢复实时;两条电量条数字与键盘实际读数相差 ≤ 5pp |

**通过标准**:两次状态翻转都在时限内发生;整体满足 SC-002 (P95 ≤ 2s)、SC-003 (电量 ±5pp)。

---

### 3.3 剧本 C — Story 3:输出端点切换(FR-006,SC-002)

| 步骤 | 操作 | 预期观察 |
|------|------|---------|
| Given | 键盘 USB 直连 + 已选 USB 输出 | 面板显示 "输出:USB" |
| When  | 在键盘上触发 `BT_SEL 0`(或等价快捷键)切 BLE 输出 | ≤ 1s 变 "输出:BLE";USB 线保持连接但不作为输出 |
| When  | 切回 USB 输出 | ≤ 1s 回到 "输出:USB" |

---

### 3.4 剧本 D — Story 4:充电字段不占位(FR-007,SC-006)

| 步骤 | 操作 | 预期观察 |
|------|------|---------|
| Given | 当前 Totem 固件**未**实现 charger GPIO(典型情况) | — |
| When  | 查看面板 | **没有**充电图标、**没有** "未充电" 文案、**没有**占位区域 |
| Then  | 一致性 CLI 的 JSON 中 `field_support.left_charging = "unsupported"` 且 `field_support.right_charging = "unsupported"` | — |

---

### 3.5 剧本 E — 陈旧值 3 秒阈值(FR-015,Clarify Q1)

| 步骤 | 操作 | 预期观察 |
|------|------|---------|
| Given | 键盘已连,所有字段实时渲染 | — |
| When  | 关闭键盘主开关(central 断电) | ≤ 1s 内所有字段 50% 透明 + 时间戳(**不**等 3 秒,因为断连事件立即触发) |
| When  | 开机但使固件 Connectivity 任务卡死 **>** 3 秒(可通过构建带 debug sleep 的测试固件复现) | **3.0 ± 0.5 秒**后字段降级为陈旧;恢复后立即回实时 |

**通过标准**:两次路径都触发了陈旧视觉;可从 `log stream --predicate 'subsystem == "com.keybeacon.app" AND category == "staleness"'` 看到 `staleness.field_stale` 日志。

---

### 3.6 剧本 F — 向后兼容(FR-016,SC-004)

| 步骤 | 操作 | 预期观察 |
|------|------|---------|
| Given | 把 Totem 刷回 KBP 1.0 固件(或换一把 1.0-only 键盘) | — |
| When  | 新版 BleWidget 连接 | 层/修饰键显示正常;「连接与电量」卡片**整张不出现** |
| Then  | 一致性 CLI 跑一轮,JSON `declared_minor = "1.0"`,`exit_code = 0`,C7–C12 全 SKIP | — |

对 **老版本 app + 新固件** 的反向验证需要先打一个 1.0 版本 app 的 release 包,**本剧本可以留给 release 前再做**,不强制在冒烟阶段完成。

---

### 3.7 剧本 G — 完整连环场景(SC-007)

一次完整演练,不中断:

```
主机断连 → 10s 后重连 → 切 profile 1→3 → 切输出 USB→BLE
→ 关 peripheral → 15s 后恢复 → 恢复 USB 输出 → 全部回到实时态
```

**通过标准**:整个过程无人工重启 app、无崩溃;FloatingPanel 每一步都如实反映;**不**出现"面板和实际不一致 ≥ 2 秒"的卡顿。

---

## 4. 一致性 CLI 的自动化冒烟

把剧本 A 之后的 `--json` 产物接到 CI(可选,未来一步):

```bash
python3 conformance/conformance_tool.py --json > /tmp/matrix.json
jq -e '
  .exit_code == 0
  and .declared_minor == "1.1"
  and (.checklist | map(select(.level == "REQUIRED" and .status == "FAIL")) | length == 0)
  and (.field_support.is_split == "supported")
  and (.field_support.host_connection == "supported")
' /tmp/matrix.json
```

Exit code = 0 即过。

---

## 5. 跨平台 CLI 的平台矩阵冒烟(可选)

同一命令在 Linux / Windows 上都应至少**启动不崩**:

```bash
# Linux (Ubuntu 22.04, bluetoothd 已启动)
python3 conformance/conformance_tool.py --help
python3 conformance/conformance_tool.py --timeout 5     # 若无键盘,预期 exit 2

# Windows 10/11 (PowerShell, Python 3.11)
python conformance\conformance_tool.py --help
python conformance\conformance_tool.py --timeout 5      # 若无键盘,预期 exit 2
```

**通过标准**:两个平台都能跑 `--help`、能在无键盘时正确退出 2(env error),**不**崩溃也**不**误报 1。

---

## 6. 回归套件(XCTest)

每次改动 BleWidgetCore 后:

```bash
cd app/macos
swift test
```

新测试文件必须全部 PASS,KBP 1.0 的既有测试(KeyboardStatusTests、CompatibilityTests、
KeyboardIdentityTests、MigrationTests)**不得退化**。

---

## 7. 跨组件引用索引

- 协议端字节级契约:[`contracts/protocol-kbp11.md`](./contracts/protocol-kbp11.md)
- 一致性 CLI 用户契约:[`contracts/conformance-cli.md`](./contracts/conformance-cli.md)
- macOS UI 契约:[`contracts/macos-ui.md`](./contracts/macos-ui.md)
- 数据模型:[`data-model.md`](./data-model.md)
- 规范:[`spec.md`](./spec.md)
- 决策依据:[`research.md`](./research.md)
