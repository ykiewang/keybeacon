# Quickstart & 验收剧本: 每连接主机上下文（Per-Link Host Context）

**Feature**: `specs/005-host-link-profile-awareness` | **Date**: 2026-11-02 | **Plan**: [plan.md](./plan.md)

本文件提供 (A) 构建/测试命令、(B) Given/When/Then 验收剧本（映射 FR/SC，宪法 Testing Discipline 要求）、(C) 降级负测矩阵。端到端需**参考键盘 + 第二台电脑**（宪法 Platform Scope）。

> 当前阶段：本 feature 为 **spec+plan+contracts** 规划产物；实现落点在两侧 `app/**` 与 `protocol/`、`conformance/`。以下命令为落地后的期望用法。

---

## A. 构建 / 测试

### A.1 纯逻辑单测（无需蓝牙硬件）

```bash
# macOS（XCTest）
cd app/macos && swift test

# Windows（xUnit）
cd app/windows && dotnet test tests/KeyBeacon.Core.Tests/KeyBeacon.Core.Tests.csproj
```

### A.2 一致性

```bash
python3 conformance/conformance_tool.py          # exit 0=符合 1.2；1=必需项失败；2=环境问题
python3 conformance/conformance_tool.py --json    # CI 支持矩阵
python3 -m pytest conformance/tests/ -q           # 解析向量回归
```

### A.3 应用运行

```bash
# macOS
cd app/macos && swift run
# Windows
cd app/windows && pwsh ./run.ps1
```

---

## B. 端到端验收剧本（Given/When/Then）

> 前提：键盘为 **KBP 1.2（per-link-aware）固件**，绑定 Host A（P1）与 Host B（P2），两端 app 运行。

### S1 — 消歧义（US1 / FR-005/006 / SC-001）
- **Given** 键盘活跃在 P1，A、B 均连接；
- **When** 两 app 正常渲染；
- **Then** A 显示「In use on this computer / 正在此电脑使用」，B 显示「active elsewhere (P1)」。
- **When** 键盘切到 P2；
- **Then** ≤ 1 s 内 A 翻为「active elsewhere (P2)」、B 翻为「in use on this computer」，两侧 BLE 均不断连。
- **覆盖**：US1-AS1/2。

### S2 — 连续切换不卡陈旧（SC-001 / edge 快速切换）
- **Given** S1 环境；
- **When** 连续 20 次切换 active profile（含 1 s 内两次）；
- **Then** 每次都 settle 到最终 active，无任一主机残留「in use」误报。

### S3 — 零配置学 slot（US2 / FR-001 / SC-002）
- **Given** 全新安装的 app（无任何设置）；
- **When** 连接已绑定的键盘；
- **Then** 首屏即显示正确的「此电脑」状态，**无需**输入任何 slot。
- **When** 将键盘重新配对到另一 slot 并重连；
- **Then** app 自动学到新 slot，状态正确，无需手工重配。

### S4 — 断连优先（FR-009 / edge link drops）
- **Given** A 处于「in use」；
- **When** 键盘关机/离开范围，A 的 BLE 断开；
- **Then** A 立即显示「Disconnected」，**不保留** in-use 痕迹。

### S5 — USB 输出区分（edge USB output）
- **Given** 键盘已绑定但 active 输出端点 = USB；
- **When** 主机渲染；
- **Then** 显示「Keyboard on USB (not this BLE link)」，**不**显示「In use over BLE」。

### S6 — open / 无法确定（edge open slot / unresolved）
- **Given** active profile 为 open（waiting-to-pair），或固件无法把本连接解析到 slot（读 AA4 回 `local_link_profile=0`）；
- **When** 主机渲染；
- **Then** 显示「Cannot determine / 无法确定」，且**恰好一条**诊断（`hostlink.cannot_determine` 或 `hostlink.unresolved`）。

---

## C. 降级 / 负测矩阵（SC-003，必须 100% 落在诚实态）

| 场景 | 输入 | 期望状态 | 期望诊断（恰一条） |
|------|------|----------|--------------------|
| slot 不可解析 | 发现 AA4，读回 `[0]=0` | cannot-determine | `hostlink.unresolved` |
| open slot | AA2 `profile_index.bit7=1` | cannot-determine | `hostlink.cannot_determine` |
| USB 输出 | `output_endpoint=1` ∧ connected | on-usb | （沿用状态变更日志） |
| 链路丢失 | `link.connected=0` | disconnected | `connection.state_changed` |
| AA4 空包 | AA4 READ < 1B | cannot-determine | `hostlink.cannot_determine` |
| slot 越界 | AA4 `[0].bits0–6 > maxSlots` | clamp 后显示 | `profile.out_of_range` |
| 有 AA4 无 AA2 | 发现 AA4 但无 AA2 | cannot-determine | `discovery.anomaly` |
| 老固件 | 未发现 AA4 | cannot-determine（仅 link 级） | `hostlink.cannot_determine` |
| 缺 active | `has_profile=0` | cannot-determine | `hostlink.cannot_determine` |

> 断言铁律：以上任一场景**绝不允许**出现 `in-use-here`（FR-008 / SC-003）。

---

## D. 向后兼容回归（SC-004）

- **新 app + 老固件（1.1，无 AA4）**：不发现 AA4，仅 link 级状态，无 in-use/elsewhere，无新 UI 错乱。
- **老 app + 新固件（1.2，有 AA4）**：老 app 不发现/不读 AA4（不在其特征列表），对 AA0/AA1/AA2/AA3 的解析**字节级不变**，无新 UI。
- **验证方式**：分别用「上一版 app 构建」与「1.1 固件」交叉运行，记录前后 render 一致。

---

## E. 单元测试要点（FR-014）

- 两端新增 `LinkSlot.parse` 与 `deriveLocalHostStatus` / `DeriveLocalHostStatus` 的**穷举**测试（AA4 单字节解析 + 输入×状态全组合）。
- macOS `app/macos/Tests/BleWidgetTests/HostLinkProfileAwarenessTests.swift`（复用 `ConnectivityStatusTests.swift` 的 payload 构造模式）。
- Windows `app/windows/tests/KeyBeacon.Core.Tests/HostContextStatusTests.cs`（复用 `Payload(...)` helper + `[Theory]/[InlineData]`）。
- 覆盖：AA4 单字节解析（slot/bit7 忽略/空包）、slot clamp、open、USB、缺 active、未发现 AA4、断连优先。
