# Quickstart: Windows 桌面客户端

**Feature**: `specs/003-windows-desktop-client` | **Phase**: 1 | **Plan**: [plan.md](./plan.md)

本文件给出构建/运行步骤与端到端验收剧本（Given/When/Then）。**环境约束**：当前仓库主机为 macOS，无法编译/运行/BLE 测试 Windows 代码；以下在 Windows 10 2004+/11 主机上执行。

## 0. 先决条件

- Windows 10 version 2004（build 19041）及以上 / Windows 11，x64 或 ARM64。
- .NET 8 SDK。
- 一把已在系统层完成 BLE 配对并连接的 KBP 键盘（参考键盘：Corne/KBP 固件）。
- 蓝牙适配器已开启。

## 1. 构建

```powershell
cd app/windows
dotnet restore KeyBeacon.sln
dotnet build KeyBeacon.sln -c Release
```

纯解析测试（**无需蓝牙硬件**，对应 SC-005）：

```powershell
dotnet test tests/KeyBeacon.Core.Tests -c Release
```

## 2. Phase 0：先跑 probe（门禁）

```powershell
dotnet run --project tools/KeyBeacon.Probe -c Release -- --json probe-run.json --verbose
```

- 退出码 0 ⇒ P1–P5 全 PASS ⇒ 门禁开，继续 §3。
- 退出码 1 ⇒ 阻塞项 FAIL ⇒ 按 [research.md §3](./research.md) 回退，**不**推进客户端实现。
- 把 `probe-run.json` 的 verdict/checks 回填到 research.md §5。

## 3. 运行客户端

```powershell
dotnet run --project src/KeyBeacon.App -c Release
```

启动后应只见系统托盘图标 + 常驻置顶悬浮窗，不占任务栏、不抢焦点（FR-008/FR-020）。

## 4. 端到端验收剧本

### S1 核心：层 + 修饰键（US1 / SC-001, SC-002）
- **Given** KBP 键盘已连接、客户端已启动
- **When** 切换到 Navigation 层
- **Then** 悬浮窗/托盘在 3 秒内显示 `Nav`（或该层名）
- **When** 按住左 Shift
- **Then** Shift 指示器激活；松开恢复
- **When** 键盘上报空层名
- **Then** 回退显示 `L{index}` 而非空白

### S2 诚实降级（US2 / SC-003）
- **Given** 客户端正显示状态
- **When** 断开键盘
- **Then** 3 秒内切「未连接」，停显旧层/修饰键，日志出现一条 `connection.state_changed`
- **When** 关闭蓝牙适配器
- **Then** 显「蓝牙不可用」；重新开启后自动恢复发现
- **When** 键盘保持连接但某字段 3 秒内无更新
- **Then** 该字段显示最后已知值 + 「更新于 hh:mm:ss」且视觉弱化，而非清空或伪造
- **When** 连接一个 KeyBeacon 家族但不支持的 MAJOR
- **Then** 显「协议版本不受支持」，不尝试解析

### S3 连接与电量（US5 / SC-008, SC-009）
- **Given** KBP 1.1 分体键盘已连接
- **Then** 按能力位显示左右半电量与连接状态；不支持的字段完全不出现（无占位）
- **When** 某电量为哨兵 255
- **Then** 显「不可用」而非 0%
- **Given** 仅 KBP 1.0 键盘
- **Then** 整个连接与电量区域不出现

### S4 多键盘（US3 / SC-007）
- **Given** 两把 KBP 键盘均连接
- **Then** 托盘菜单按设备名列出两者
- **When** 选其一
- **Then** ≤10 秒显示该键盘状态；重启后沿用上次选择

### S5 诊断包（US6 / SC-011, SC-012）
- **Given** 客户端运行并发生过断开/解析失败
- **When** 托盘菜单 →「导出诊断信息」→ 审阅将包含的信息 → 确认
- **Then** ≤3 步得到单一 `.zip`，含 environment.json + 近期日志 + README.txt
- **When** 开「详细日志」后复现问题
- **Then** 日志含失败 payload 的原始 hex
- **When** 重启客户端后再导出
- **Then** 仍含重启前近期日志
- **Then** 蓝牙地址/标识符默认不以明文出现（FR-025）

### S6 本地化（SC-010）
- **When** 系统区域为中文
- **Then** 界面标签为中文
- **When** 系统区域为英文
- **Then** 界面标签为英文

## 5. macOS 零回归确认（SC-004）

本 feature 不触碰 `app/macos/`。回归确认：

```bash
cd app/macos && swift test   # 在 macOS 主机上
```

应全绿，行为与改动前一致。
