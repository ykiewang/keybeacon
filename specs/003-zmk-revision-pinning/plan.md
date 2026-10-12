# Implementation Plan: zmk-keybeacon 模块的 ZMK revision 版本契约

**Branch**: `003-zmk-revision-pinning` | **Date**: 2026-10-12 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-zmk-revision-pinning/spec.md`

**Note**: 本 feature 的落地仓是 **`../zmk-keybeacon/`**（独立 Zephyr 模块仓），而不是本仓 (`keybeacon`)。本仓只承载 spec / plan / 文档，并在 002 的 upgrade-notes 处交叉引用。

## Summary

把 "zmk-keybeacon 外部模块与 ZMK upstream 的 API 漂移会悄悄挂掉用户 build" 这个风险，从 "靠用户在 `.conf` 里逐个禁子系统" 的方式，转为 **模块侧单一真相源 `compatibility.yaml` + CMake 配置期符号探测 fail-fast + 维护者侧每日 CI** 的三位一体机制。消费者 `west update` 后要么编过，要么在 CMake 阶段看到含三条可执行修复路径的中英双语 banner，不再出现 C 编译期未定义符号的黑箱。同时作为落地样本，`v1.1.4` tag 修复 002 遗留的 `zmk_endpoints_selected()` 调用——真实唯一调用点是 `../zmk-keybeacon/keybeacon.c:243`（CONFIG_ZMK_KEYBEACON_CONNECTIVITY 路径），改为 `#ifdef` 双 API 兼容：当头文件探测到 ZMK ≥ `6e7e0de2`（2026-02-12，`feat(endpoints): add "no endpoint" value (#3140)`）时走新 API `zmk_endpoint_get_selected()`，否则走旧 API `zmk_endpoints_selected()`。同时把 002 用户 `.conf` 里的 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n` workaround 变成可删除的历史文物。

## Technical Context

**Language/Version**: C11（Zephyr app code）、CMake 3.20+、Python 3.8+（build-time 脚本；Zephyr/west 本就依赖）、YAML（声明文件）、Shell（CI runner）。

**Primary Dependencies**: Zephyr RTOS 3.5（通过 ZMK 传递）、ZMK（作为 peer module，被探测的对象）、west（manifest 工具）、GitHub Actions 的 `zmkfirmware/zmk-docker-action@v2`。无新增 pip 包。

**Storage**: 单一真相源文件 `../zmk-keybeacon/compatibility.yaml`（纯文本，git 跟踪，每次 tag 冻结）。无运行时存储。

**Testing**:
- 符号探测器 (`check_zmk_compat.py`) 用 pytest 做单元测试，fixture 用 fake ZMK tree（纯文本头文件 `app/include/zmk/endpoints.h` + `app/include/zmk/ble.h`，无硬件、无 west）。
- CMake 集成用 shell 冒烟测试：造三个 fixture ZMK tree——(a) `zmk-legacy`（旧 API `zmk_endpoints_selected` 存在、ZMK < `6e7e0de2`）、(b) `zmk-renamed`（新 API `zmk_endpoint_get_selected` 存在、ZMK ≥ `6e7e0de2`）、(c) `zmk-missing`（两个 API 都没有，模拟破坏性删除）；断言 configure 退出码分别为 0 / 0 / 2，`keybeacon.c` 在 (a)/(b) 下走到对应 `#ifdef` 分支。
- CI 侧的 workflow 本身用 `act` 或 PR 自测触发。

**Target Platform**: 消费者侧——Zephyr 兼容硬件（参考 `nice_nano_v2` + `corne_left` / `totem_left`）；CI 侧——GitHub Actions `ubuntu-latest`。

**Project Type**: ZMK external module（Zephyr add-on 工程），其产物是跟 ZMK 并列的 Zephyr module，不独立运行、不发二进制。本 spec 产出的所有代码落在 `../zmk-keybeacon/`。

**Performance Goals**: CMake configure 阶段的符号探测开销 ≤ 1s（含 Python 启动、读 5 份头文件、grep 正则）。CI 日度矩阵的单次 build < 10 min。

**Constraints**:
- MUST NOT 要求消费者安装 Zephyr 工具链以外的任何工具（Python3 是 Zephyr 既有依赖）。
- MUST NOT 把符号探测放到 C 预处理/编译期——必须在 CMake configure 期停下（见 US1 scenario 2）。
- MUST 兼容 ZMK `main` 分支随时漂移的现实：探测方式是**头文件符号 grep**，不是 commit sha 比对。
- Bilingual：错误 banner 的"How to fix"段落至少英文清晰（README Compatibility 表英文优先，可选中文镜像）；本仓 (`keybeacon`) 下的 upgrade-notes 补充双语（遵循 Constitution Principle VI）。

**Scale/Scope**:
- 1 个外部模块仓（`../zmk-keybeacon/`，单文件 `keybeacon.c` 528 行、`Kconfig.keybeacon` 26 行、`keybeacon.cmake` 13 行、`zephyr/module.yml` 已声明 `build.cmake: .` + `build.kconfig: Kconfig.keybeacon`）
- 初始 4 个符号探测点（`compatibility.yaml` 中的 `required_symbols`，与 `keybeacon.c` 实际调用一一对应：`zmk_ble_active_profile_is_connected`、`zmk_ble_active_profile_index`、`zmk_ble_active_profile_is_open`、`zmk_endpoints_selected`/`zmk_endpoint_get_selected`（任一命中））
- CI 矩阵：3 个 ZMK ref（`main` + 已验证 renamed 后的 pinned sha `4dd95d7` + 已验证 legacy 的 pinned sha `e844eca2`）× 1 个代表性 shield（`xiao_ble + totem_left`，和用户现网 CI 一致）= 3 组
- 本仓改动：002 的 `upgrade-notes.md` + README 交叉引用，总行数预估 ≤ 100 行

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | 适用性 | 是否通过 | 说明 |
|---|---|---|---|
| I. Wire-Contract Self-Containment | ✅ 适用 | ✅ 通过 | 本 feature 完全不触碰 `protocol/`，`v1.1.4` 的 wire 行为与 `v1.1.3` 位对位相同（CHANGELOG 必须显式声明"no wire change in this release"）。 |
| II. Backward Compatibility | ✅ 适用（模块侧 semver） | ✅ 通过 | `v1.1.3 → v1.1.4` 是 PATCH：无 wire 变更、无 KBP MINOR 新特性、Kconfig escape hatch 默认 `n`（即旧行为）。消费者 `.conf` 原有 workaround 行可继续兼容（即使保留 `CHAR_CONNECTIVITY=n` 也不出错，只是功能缺失，与 v1.1.3 行为等价）。 |
| III. Identity From Protocol, Not Branding | ⚪ 不适用 | — | 本 feature 不涉及 host 侧设备识别逻辑。 |
| IV. Observable Degradation Over Guessing | ✅ 适用（放大镜版本） | ✅ 通过并强化 | fail-fast banner 是 "observable degradation" 原则在构建时间的投影：宁可停下并说清楚（"ZMK revision incompatible"），也不让用户看到 cryptic 的 undefined symbol。符号缺失时**绝不**自动降级、禁用子系统或"猜一个 default"——那正是本 feature 要根除的反模式。 |
| V. Spec-First Development | ✅ 适用（NON-NEGOTIABLE） | ✅ 通过 | 本 plan 本身即工作流一部分。实现代码只在 `/speckit-tasks` → `/speckit-implement` 后合入 `../zmk-keybeacon/`。 |
| VI. Bilingual Normative Docs | ⚠️ 部分适用 | ✅ 通过（分流处理） | 本 spec/plan 用中文（符合"内部设计文件可中文only"）。`../zmk-keybeacon/README.md` 不在 constitution 的强制双语列表（该列表限 `protocol/`、`conformance/`、本仓顶层 README）；但为降低国际贡献门槛，Compatibility 章节与 fail-fast banner 的 "How to fix" 段落**英文为主、中文可选并列**。本仓 002 的 upgrade-notes 遵循双语。 |

**Platform Scope Check**：本 feature 不改变 constitution 中声明的 Platform Scope（macOS 12+ host、ZMK 参考固件）。CI 新增的 `ubuntu-latest` runner 只跑模块构建，不是新的交付目标平台。

**Testing & Verification Discipline Check**：
- 新增 Python 探测器 `check_zmk_compat.py` 带 pytest 单测（覆盖 `symbol_present` / `resolve_zmk_rev` / `render_banner` 三个纯函数）。
- CMake 集成有 fixture 冒烟测试。
- US1/US2/US3 的 Independent Test 已在 spec 定义，`quickstart.md` 会把它们转成 Given/When/Then。
- 本 feature 不涉及 XCTest / BleWidgetCore / 协议 wire，相关验证路径 N/A。

**Gate result**: ✅ PASS（无需 Complexity Tracking）。

## Project Structure

### Documentation (this feature)

```text
specs/003-zmk-revision-pinning/
├── plan.md              # 本文件（/speckit-plan 输出）
├── research.md          # Phase 0 输出（5 个 Decision）
├── data-model.md        # Phase 1 输出（compatibility.yaml schema）
├── quickstart.md        # Phase 1 输出（US1/US2/US3 的 Given/When/Then）
├── contracts/           # Phase 1 输出
│   ├── compatibility-yaml-schema.md    # 声明文件格式契约
│   ├── fail-fast-banner.md             # 错误 banner 的 UX 契约
│   ├── ci-workflow-contract.md         # CI workflow 输入输出契约
│   └── escape-hatch-kconfig.md         # Kconfig 符号契约
├── checklists/
│   └── requirements.md  # /speckit-specify 已产出
└── tasks.md             # /speckit-tasks 后续产出
```

### Source Code (落地仓：`../zmk-keybeacon/`，本仓只做引用)

```text
# 外部模块仓 ../zmk-keybeacon/ 的目标结构（基于真实现网 tree 2026-10-12）
../zmk-keybeacon/
├── compatibility.yaml                     # ⬅ 新增：单一真相源
├── cmake/
│   └── zmk_compat.cmake                   # ⬅ 新增：配置期符号探测入口（从 keybeacon.cmake 顶部 include()）
├── scripts/
│   ├── check_zmk_compat.py                # ⬅ 新增：符号探测核心（Python 3 header grep）
│   ├── update-readme-table.py             # ⬅ 新增：Compatibility 表自动生成
│   └── tests/
│       ├── test_check_zmk_compat.py       # ⬅ 新增：pytest 单测
│       └── fixtures/
│           ├── zmk-legacy/app/include/zmk/           # 旧 API：zmk_endpoints_selected 存在
│           ├── zmk-renamed/app/include/zmk/          # 新 API：zmk_endpoint_get_selected 存在
│           └── zmk-missing/app/include/zmk/          # 两个 API 均不存在（破坏性删除）
├── Kconfig.keybeacon                      # ⬅ 修改：新增 CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK
├── CMakeLists.txt                         # ⬅ 不动（薄 wrapper）
├── keybeacon.cmake                        # ⬅ 修改：顶部 include(cmake/zmk_compat.cmake)
├── keybeacon.c                            # ⬅ 修改：行 243 的 #ifdef 双 API 兼容（唯一调用点）
├── .github/
│   └── workflows/
│       └── zmk-main-compat.yml            # ⬅ 新增：日度 + PR CI
├── README.md                              # ⬅ 修改：新增 Compatibility 章节 + CI badge
├── CHANGELOG.md                           # ⬅ 修改：v1.1.4 条目
└── zephyr/
    └── module.yml                         # ⬅ 不动（build.cmake 已指向 .、build.kconfig 已指向 Kconfig.keybeacon）

# 本仓 keybeacon/ 的改动（最小化）
specs/002-zmk-keybeacon-kbp11/
└── upgrade-notes.md                       # ⬅ 新增：如何从 v1.1.3 升级到 v1.1.4（含删除 .conf workaround 清单）
README.md                                  # ⬅ 可选：Roadmap 表加一行 KBP 1.1.1 patch 已发
```

**Structure Decision**: 这是 **ZMK external module** 项目——其核心交付物不是本仓的产物，而是通过 west manifest 被消费者在 `west update` 时拉取的 Zephyr module。因此：
1. 真正的"源码树"在 `../zmk-keybeacon/`，本仓只贡献 spec + 升级指南。
2. 本仓的 `tests/` / `src/` 不涉及，模板 Option 1 的目录结构 **不适用**。
3. 所有实现文件路径以 `../zmk-keybeacon/` 为根（但 Spec Kit 工件保持在本仓 `specs/003-...` 下）。
4. **真实的 ZMK external module 结构 — 单文件布局**：`keybeacon.c` 直接在根目录（不是 `src/connectivity.c`），`Kconfig.keybeacon`（不是 `Kconfig`），`keybeacon.cmake` 作为真实 cmake 入口，`CMakeLists.txt` 是薄 wrapper 仅 `include(keybeacon.cmake)`。本 plan 的所有探测/修改以此结构为准，不要臆造 `src/`、`cmake/zmk_compat.cmake` 可以新建但 `#ifdef` 落点在 `keybeacon.c:243` 这唯一调用点。
5. 本 feature 的 `/speckit-implement` 阶段，实际 commit 落在 `../zmk-keybeacon/` 的 feature 分支上（例如 `feat/compat-contract-v1.1.4`），本仓只提交 upgrade-notes。

## Post-Design Constitution Re-Check

*GATE: 在 Phase 1 产出 `data-model.md` / `contracts/*` / `quickstart.md` 之后重跑一次，防止设计阶段偷偷引入了违反 constitution 的决策。*

| Principle | Pre-design 结论 | Post-design 结论 | 新增证据 |
|---|---|---|---|
| I. Wire-Contract Self-Containment | ✅ 通过 | ✅ 通过 | contracts 全部位于 `specs/003-.../contracts/`，`protocol/` 与 `conformance/` 无改动；banner 是构建期诊断、非 wire 行为。 |
| II. Backward Compatibility | ✅ 通过 | ✅ 通过 | [compatibility-yaml-schema.md](./contracts/compatibility-yaml-schema.md) 的"向后兼容承诺"节固定了 PATCH/MINOR/MAJOR 的 schema 跃迁规则；[escape-hatch-kconfig.md](./contracts/escape-hatch-kconfig.md) 保证新 Kconfig `default n` ⇒ 旧行为。 |
| III. Identity From Protocol | ⚪ 不适用 | ⚪ 不适用 | 本 feature 完全不触及 host 侧设备识别。 |
| IV. Observable Degradation | ✅ 通过并强化 | ✅ 通过并强化 | [fail-fast-banner.md](./contracts/fail-fast-banner.md) 把 "hidden over invented" 原则推到构建时间：banner 显式说清楚缺哪个符号，而不是"猜一个 default 让它编过"。 |
| V. Spec-First Development | ✅ 通过 | ✅ 通过 | Phase 0 + Phase 1 工件齐全；`/speckit-implement` 不会越过本阶段。 |
| VI. Bilingual Normative Docs | ✅ 分流通过 | ✅ 分流通过 | upgrade-notes.md（本仓 002 下，面向本仓读者）走双语；`../zmk-keybeacon/` 不在强制列表、英文为主、Compatibility 表英文优先。 |

**Testing & Verification Discipline Re-Check**：
- 契约层：`contracts/*.md` 四份契约都在"Validation Rules"或"Pass/Fail 判据"节给出可机器化的回归点。
- 实现层：`quickstart.md` 的所有 Pass/Fail 判据可直接复用为 `/speckit-tasks` 的 integration test items。
- 回归层：`fail-fast-banner.md` 的 "字节级稳定性" 节固定了 banner 的 fixture-based regression test，防措辞偶发修改。

**Gate result**: ✅ PASS。可以进入 `/speckit-tasks`。

### 2026-10-12 二次复盘 Re-Check（基于 CI run 38043117244 的实证证据）

本次 /speckit-plan 补修订后，重新审视 pre+post 两道 constitution gate：

| 检查维度 | 结论 | 证据 |
|---|---|---|
| ZMK API 漂移根因 | ✅ 已钉死 | spec.md Clarifications 2026-10-12 节；ZMK commit `6e7e0de2`（2026-02-12）确实做了重命名 |
| 符号探测清单与实际代码一致性 | ✅ 已对齐 | `keybeacon.c` 真实调用 4 个 ZMK 符号（见 data-model.md 完整示例），探测清单一一对应 |
| 文件布局正确性 | ✅ 已订正 | plan.md Project Structure 使用单文件 `keybeacon.c` + `Kconfig.keybeacon` + `keybeacon.cmake`，与 `../zmk-keybeacon/` 实况一致 |
| CI matrix 冻结 pin 可行性 | ✅ 已验证 | `4dd95d7` 来自真实 CI run 日志、`e844eca2` 来自本地 ZMK clone HEAD，两个 commit 都是公开可访问的 ZMK commit |
| Constitution 任一原则违反 | ❌ 无 | pre 阶段六项结论无变化；post 阶段六项结论无变化 |
| Complexity Tracking 新增 | ❌ 无 | 无额外复杂度条目需登记 |

**结论**：PASS。/speckit-plan 的 Phase 0 + Phase 1 工件已基于订正后的事实链全量刷新（spec.md Clarifications、research.md D5/D6/D7、data-model.md Entity: RequiredSymbol + 完整示例 + Validation Rules、contracts/*/*.md 的 4 份契约、quickstart.md 的 board / 符号路径），可以进入 `/speckit-tasks` 增量更新 tasks.md。

## Complexity Tracking

> Constitution Check 全部通过（pre + post），无需填写。
