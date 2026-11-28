# Quickstart: 006-keymap-viewer

**Date**: 2026-11-26

## 前置条件

- 已连接一把支持 KBP 1.3（含 `AA440AA5`/`AA440AA6` 特征）的键盘
- macOS app 已构建并运行（菜单栏图标可见）

---

## 场景 1 — 首次拉取并显示键位图（FR-001、FR-004、FR-005）

**SC-001 / SC-002**

```
Given  键盘已连接，本地无 keymap 缓存
When   用户按下已配置的全局快捷键（或点菜单栏「键位图」）
Then   KeymapPanel 在 2 秒内打开
       layer 0 的所有按键以圆角矩形渲染，各键显示正确的 keycode 标签
```

验证步骤：
1. 首次运行前删除 UserDefaults 中所有 `keymapCache_*` 键
2. 冷启动 app，连接 KBP 1.3 键盘
3. 触发全局快捷键，计时至 KeymapPanel 完整渲染
4. 目视确认按键形状与数量与键盘实物一致

---

## 场景 2 — 缓存命中，快速渲染（FR-002、FR-003）

**SC-001 / SC-003**

```
Given  本地已有有效缓存（uuid + crc32 匹配）
When   用户再次按快捷键（首次连接之后）
Then   KeymapPanel 在 300ms 内打开，BLE 仅产生 1 次 KeymapMeta READ transaction
```

验证步骤：
1. 首次连接后关闭 KeymapPanel
2. 断开并重新连接键盘（触发 CRC 检查）
3. 再次按快捷键，使用 Instruments 或 nRF Sniffer 确认无 `AA440AA6` READ
4. 计时 ≤ 300ms

---

## 场景 3 — 固件刷新后自动重拉（FR-002、FR-012）

**SC-002**

```
Given  本地有旧缓存，键盘固件已重新烧录（CRC 变化）
When   app 重新连接键盘
Then   浮窗先显示旧缓存内容，后台重新拉取 KeymapData
       拉取完成后无缝刷新为新 keymap 内容
```

验证步骤：
1. 修改 `.keymap` 文件并重新烧录固件
2. 重连键盘，观察 KeymapPanel 是否先显示旧内容再刷新
3. 确认新按键标签正确

---

## 场景 4 — Layer 切换（FR-006、FR-009）

**US2-SC-001 / US2-SC-002**

```
Given  KeymapPanel 已打开，显示 layer 0
When   用户点击 segmented control 中的 layer 2
Then   所有按键标签切换为 layer 2 的 binding，物理形状不变

Given  键盘通过 KBP 1.0 notify 上报 layer 3 激活
Then   segmented control 高亮 layer 3，用户当前查看的 layer 视图不被强制切换
```

---

## 场景 5 — 老固件降级（FR-011）

**SC-004**

```
Given  连接一把不支持 KBP 1.3 的键盘（无 AA440AA5 特征）
When   用户打开菜单栏
Then   「键位图」菜单项灰显
       KBP 1.0/1.1/1.2 功能正常，app 不崩溃
```

---

## 场景 6 — 旋转键渲染（FR-008）

**SC-005**

```
Given  键盘物理布局含旋转键（r ≠ 0）
When   KeymapPanel 打开
Then   旋转键以正确角度渲染，视觉上与实际键盘位置匹配
       无坐标偏移或旋转方向错误
```

---

## 场景 7 — 强制刷新（FR-012）

```
Given  本地有有效缓存（CRC 未变）
When   用户点击菜单栏「强制刷新键位图」
Then   app 忽略 CRC，重新拉取完整 KeymapData 并更新显示
```

---

## 场景 8 — Toggle 行为（FR-005）

**US1-SC-004**

```
Given  KeymapPanel 已打开
When   用户再次按同一全局快捷键
Then   KeymapPanel 关闭
```

---

## 场景 9 — 断开连接时 stale 状态（US3-SC-003）

```
Given  KeymapPanel 已打开，键盘断开连接
Then   浮窗保留最后一次渲染内容
       以某种方式标示「已断连」（如标题栏或覆盖提示）
       app 不崩溃
```

---

## FR / SC 映射表

| 场景 | FR | SC |
|------|----|----|
| 1 | FR-001, FR-004, FR-005 | SC-002 |
| 2 | FR-002, FR-003 | SC-001, SC-003 |
| 3 | FR-002, FR-012 | SC-002 |
| 4 | FR-006, FR-009 | — |
| 5 | FR-011 | SC-004 |
| 6 | FR-008 | SC-005 |
| 7 | FR-012 | SC-003 |
| 8 | FR-005 | — |
| 9 | FR-011 | SC-004 |
