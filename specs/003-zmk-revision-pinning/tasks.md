---
description: "Task list for zmk-keybeacon 模块的 ZMK revision 版本契约"
---

# Tasks: zmk-keybeacon 模块的 ZMK revision 版本契约

**Input**: Design documents from `/specs/003-zmk-revision-pinning/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/{compatibility-yaml-schema,fail-fast-banner,ci-workflow-contract,escape-hatch-kconfig}.md, quickstart.md

**Tests**: 本 feature 的 testing discipline（plan.md §Testing）**显式要求**：探测器用 pytest 做单测、CMake 集成有 shell smoke、banner 做字节级回归。因此 test tasks 全部纳入。

**Organization**: 任务按 Setup → Foundational → User Story（P1 → P2 → P2）→ Polish 分层；story 内按 "fixture → unit test → implementation → smoke test" 顺序。

## Path Conventions

本 feature 的实现代码落在**模块仓** `../zmk-keybeacon/`（独立 git repo，sibling of this repo）。本仓 `keybeacon/` 只承载 Spec Kit 工件 + 002 升级指南 + README roadmap 行。路径前缀含义：

- `../zmk-keybeacon/...` → 模块仓文件（新增/修改需在 `../zmk-keybeacon/` 的 feature 分支 `feat/compat-contract-v1.1.4` 下 commit）
- `specs/...` → 本仓 keybeacon 的 Spec Kit 工件（本 PR 已提交）
- `specs/002-zmk-keybeacon-kbp11/...` → 本仓的 002 feature 文档区
- 顶层 `README.md`、`CHANGELOG.md`（无前缀）→ 本仓根目录

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 准备分支与骨架目录，不写任何业务逻辑。

- [X] T001 在 `../zmk-keybeacon/` 从 `main` 创建 feature 分支 `feat/compat-contract-v1.1.4` 并 push 到 origin
- [X] T002 [P] 创建模块仓目录骨架 `../zmk-keybeacon/cmake/`、`../zmk-keybeacon/scripts/`、`../zmk-keybeacon/scripts/tests/`、`../zmk-keybeacon/scripts/tests/fixtures/`
- [X] T003 [P] 添加占位文件 `../zmk-keybeacon/scripts/__init__.py`、`../zmk-keybeacon/scripts/tests/__init__.py`、`../zmk-keybeacon/scripts/tests/conftest.py`（conftest 可暂为空，后续按需加 fixture）
- [X] T004 [P] 创建 `../zmk-keybeacon/scripts/requirements-dev.txt` 列出 `pyyaml>=6.0`、`jsonschema>=4.0`、`pytest>=7.0`（CI 和本地 reviewer 共用）

**Checkpoint**: Setup 完成，仓目录结构就位，可以开始填充 foundational。

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 建立 US1/US2/US3 都依赖的核心——单一真相源 `compatibility.yaml` + 校验器 + 符号探测器 + CMake 集成 + Kconfig 逃生门。此阶段完成后，构建期配置契约的"骨架"已成形，但尚未修复 002 遗留的 C 代码问题，也无 CI。

**⚠️ CRITICAL**: Phase 3/4/5 的所有任务都依赖本 phase 的完成。

### 真相源与声明

- [X] T005 创建 `../zmk-keybeacon/compatibility.yaml`，内容严格对齐 [data-model.md](specs/003-zmk-revision-pinning/data-model.md) 的"完整示例：v1.1.4 的 `compatibility.yaml`"节：含 `module_version: 1.1.4`、`zmk_known_good.lower=e844eca2 / upper=4dd95d7 / branch_hint=main`、**4 条** `required_symbols`（其中第一条 `zmk_endpoints_selected` 带 `fallback: [zmk_endpoint_get_selected]` 和 `emits_macro: ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT`、`used_in: keybeacon.c`；其余三条 `zmk_ble_active_profile_is_connected`、`zmk_ble_active_profile_index`、`zmk_ble_active_profile_is_open` 的 `header: zmk/ble.h`、`used_in: keybeacon.c`）、`escape_hatch.kconfig/default`、`ci.schedule/matrix({main, 4dd95d7, e844eca2} × {totem_left})/on_schedule_failure`
- [X] T006 [P] 创建 `../zmk-keybeacon/compatibility.schema.yaml`，内容为 [contracts/compatibility-yaml-schema.md](specs/003-zmk-revision-pinning/contracts/compatibility-yaml-schema.md) 的 "JSON Schema" 节完整落地（Draft 2020-12，`additionalProperties: false`）

### Kconfig 逃生门

- [X] T007 [P] 修改 `../zmk-keybeacon/Kconfig.keybeacon`，在**扁平 config 结构**中（与现有 `ZMK_KEYBEACON_CONNECTIVITY` / `ZMK_KEYBEACON_BATTERY` 平级）新增 `config ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK` 符号，`bool "Allow building against an incompatible ZMK revision (ADVANCED)"`，`depends on ZMK_KEYBEACON`，`default n`，help 文本按 [contracts/escape-hatch-kconfig.md](specs/003-zmk-revision-pinning/contracts/escape-hatch-kconfig.md) 的 "Kconfig 代码片段" 节逐字写入（含 "ADVANCED"、"almost certainly do NOT want this"、"undefined behaviour" 等劝退措辞）

### Validate_compat.py（三级校验器）

- [X] T008 [P] 实现 `../zmk-keybeacon/scripts/validate_compat.py` 的 L1 层：`yaml.safe_load(open("compatibility.yaml"))`，失败时打印行号列号 + unexpected token，退出码 `3`
- [X] T009 [P] 实现 `../zmk-keybeacon/scripts/validate_compat.py` 的 L2 层：用 `jsonschema.validate(data, schema=yaml.safe_load(open("compatibility.schema.yaml")))`；失败时打印 JSON Pointer 定位 + expected vs actual，退出码 `4`（本任务与 T008 可并行，因为分函数实现；最终主入口在 T011 整合）
- [X] T010 [P] 实现 `../zmk-keybeacon/scripts/validate_compat.py` 的 L3 语义层：覆盖 [data-model.md](specs/003-zmk-revision-pinning/data-model.md) "Validation Rules Summary" 的全部 6 条——(1) `required_symbols[i].name` 全局唯一、(2) `emits_macro` 全局唯一（未设置的不参与）、(3) release 时 `module_version` 与 `git describe --exact-match` 一致（提供 `--check-git-tag` flag 可选）、(4) 对每个 `required_symbols[i]`，`grep -E "\b(name|fallback[*])\s*\(" ../zmk-keybeacon/<used_in>` 必须命中、(5) `known_good.lower/upper` 用 `git -C ${ZMK_ROOT} cat-file -e <sha>` 校验存在、(6) `escape_hatch.kconfig` 的 CONFIG 符号在 `../zmk-keybeacon/Kconfig.keybeacon` 中实际声明。失败时打印规则名 + 违规 YAML 块，退出码 `5`
- [X] T011 整合 `../zmk-keybeacon/scripts/validate_compat.py` 主入口：argparse（支持 `--compat-file`、`--schema-file`、`--zmk-root`、`--check-git-tag`）；按 L1→L2→L3 顺序，一旦失败立即返回对应退出码；全部通过返回 `0` 并打印一行 `manifest OK`

### Validate_compat.py 的单元测试（覆盖 L1-L3 失败场景）

- [X] T012 [P] 创建 `../zmk-keybeacon/scripts/tests/fixtures/manifest-bad-yaml.yaml`（故意制造 YAML 语法错，用于触发 L1 退出码 3）
- [X] T013 [P] 创建 `../zmk-keybeacon/scripts/tests/fixtures/manifest-schema-violation.yaml`（例如 `module_version: "1.1"` 不符合 `^\d+\.\d+\.\d+$`，触发 L2 退出码 4）
- [X] T014 [P] 创建 `../zmk-keybeacon/scripts/tests/fixtures/manifest-dup-symbol.yaml` 和 `manifest-dup-macro.yaml`（分别触发 L3 规则 1 和 2 退出码 5）
- [X] T015 [P] 编写 `../zmk-keybeacon/scripts/tests/test_validate_compat.py`，为 T012-T014 的每个 fixture 用 pytest 参数化断言退出码与关键字段（例如 `assert "manifest OK" in stdout` for the valid case），覆盖 ≥ 6 个失败场景

### Check_zmk_compat.py（符号探测器核心）

- [X] T016 实现 `../zmk-keybeacon/scripts/check_zmk_compat.py` 的 `symbol_present(zmk_root, header, candidates)` 纯函数：按 [research.md D2](specs/003-zmk-revision-pinning/research.md) 的 Decision，用 `re.search(rf"\b{sym}\s*\(", path.read_text())` 匹配头文件；返回 `(hit: bool, which_symbol: str|None)`；header 不存在时返回 `(False, "header missing: <header>")`
- [X] T017 实现 `../zmk-keybeacon/scripts/check_zmk_compat.py` 的 `resolve_zmk_rev(zmk_root)` 纯函数：`subprocess.check_output(["git", "-C", zmk_root, "rev-parse", "--short", "HEAD"])`，失败时抛可读异常
- [X] T018 实现 `../zmk-keybeacon/scripts/check_zmk_compat.py` 的 `render_banner_fail(compat, current_sha, missing)` 纯函数：按 [contracts/fail-fast-banner.md](specs/003-zmk-revision-pinning/contracts/fail-fast-banner.md) 的 "Banner 骨架（必含字段）" 节逐字节渲染（72 字符硬换行、UTF-8 框线字符、三条 How-to-fix、"Also"段落劝退 `.conf` workaround），所有占位符来自契约 "变量来源表"
- [X] T019 实现 `../zmk-keybeacon/scripts/check_zmk_compat.py` 的 `render_banner_warn(compat, current_sha, missing)` 纯函数：按 [contracts/fail-fast-banner.md](specs/003-zmk-revision-pinning/contracts/fail-fast-banner.md) 的 "Scenario 3 - escape hatch 开启" 节渲染，必含 "would have failed on symbol X" 和 "build and runtime at your own risk" 字样
- [X] T020 实现 `../zmk-keybeacon/scripts/check_zmk_compat.py` 的 `render_status_ok(compat, current_sha)` 纯函数：生成唯一一行 `-- [zmk-keybeacon {module_version}] ZMK revision check: {sha} ∈ [known-good: {lower}..{upper_or_HEAD}) ✓`
- [X] T021 实现 `../zmk-keybeacon/scripts/check_zmk_compat.py` 的主入口：argparse（`--compat-file`、`--zmk-root`、`--allow-incompat` 布尔）；按 required_symbols 遍历调 `symbol_present`，收集 `missing` 列表 + `emits_macros` 命中列表；根据 `(missing, allow_incompat)` 分发到 `render_status_ok` / `render_banner_warn` / `render_banner_fail`；成功时 stdout 打印 `✓` 行并输出 `set(ZMK_KEYBEACON_COMPAT_DEFINES "-DZMK_KEYBEACON_HAS_LEGACY_ENDPOINT=1;...")` 风格的 CMake-friendly 行供 CMake 捕获；退出码 0/2 分别对应 ok 和 fail-fast

### Check_zmk_compat.py 的单元测试与 fixture

- [X] T022 [P] 创建 fixture ZMK tree `../zmk-keybeacon/scripts/tests/fixtures/zmk-legacy/app/include/zmk/`，包含 `endpoints.h`（含 `zmk_endpoints_selected(` 的声明，模拟 ZMK < `6e7e0de2` 的旧 API 状态）、`ble.h`（含 `zmk_ble_active_profile_is_connected(`、`zmk_ble_active_profile_index(`、`zmk_ble_active_profile_is_open(` 三个符号）——`compatibility.yaml` 声明的 4 个 `required_symbols` 全部命中 `name`，`emits_macro: ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT` 应该被 emit
- [X] T023 [P] 创建 fixture ZMK tree `../zmk-keybeacon/scripts/tests/fixtures/zmk-renamed/app/include/zmk/`：`endpoints.h` 只含 `zmk_endpoint_get_selected(`（**删除**旧 `zmk_endpoints_selected(` 声明），模拟 ZMK ≥ `6e7e0de2` (`feat(endpoints): add "no endpoint" value (#3140)`) 的新 API 状态；`ble.h` 内容与 `zmk-legacy` 相同——触发 fallback 命中（第一条 required_symbol 命中 fallback），**不** emit `ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT` 宏
- [X] T024 [P] 创建 fixture ZMK tree `../zmk-keybeacon/scripts/tests/fixtures/zmk-missing/app/include/zmk/endpoints.h`：删除整个符号——`endpoints.h` 不含 `zmk_endpoints_selected(` 也不含 `zmk_endpoint_get_selected(`（无 `name` 也无 `fallback`，触发 fail-fast）；`ble.h` 内容与 `zmk-legacy` 相同
- [X] T025 [P] 创建 fixture ZMK tree `../zmk-keybeacon/scripts/tests/fixtures/zmk-header-missing/app/include/zmk/`：删除整个 `endpoints.h` 文件（触发 "header missing" 分支）；`ble.h` 内容与 `zmk-legacy` 相同
- [X] T026 [P] 编写 `../zmk-keybeacon/scripts/tests/test_check_zmk_compat.py`，用上述 4 个 fixture 分别断言：`zmk-legacy` → 退出码 0 + stdout 含 `✓` + 输出的 CMake 行**含** `-DZMK_KEYBEACON_HAS_LEGACY_ENDPOINT=1`；`zmk-renamed` → 退出码 0 + 输出的 CMake 行**不含** `-DZMK_KEYBEACON_HAS_LEGACY_ENDPOINT`；`zmk-missing` / `zmk-header-missing` → 退出码 2 + banner 必含字段齐全（标题框、"Missing symbol"、三条 How-to-fix、"Also" 段落）
- [X] T027 [P] 创建 `../zmk-keybeacon/scripts/tests/fixtures/expected_banner_v1.1.4.txt`，内容是对 `zmk-missing` fixture 的字节级期望输出（由 T018 的 render_banner_fail 首次运行后截取并人工 review）
- [X] T028 [P] 在 `../zmk-keybeacon/scripts/tests/test_check_zmk_compat.py` 中新增字节级回归 case `test_banner_matches_fixture_missing`，断言 stdout/stderr 与 `expected_banner_v1.1.4.txt` 完全相等（见 [contracts/fail-fast-banner.md](specs/003-zmk-revision-pinning/contracts/fail-fast-banner.md) 的 "失败 banner 的字节级稳定性"）

### CMake 集成胶水

- [X] T029 创建 `../zmk-keybeacon/cmake/zmk_compat.cmake`：`find_package(Python3)` → `execute_process(COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_LIST_DIR}/../scripts/check_zmk_compat.py ...)` → 捕获 `_compat_rc / _compat_msg`，按 `(rc, CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK)` 四种组合分发到 `message(STATUS / WARNING / FATAL_ERROR)`；成功路径时解析 Python 输出的 `set(ZMK_KEYBEACON_COMPAT_DEFINES ...)` 行并 `add_compile_definitions(${ZMK_KEYBEACON_COMPAT_DEFINES})`
- [X] T030 修改 `../zmk-keybeacon/keybeacon.cmake`（真实的 Zephyr library cmake 入口；根目录 `CMakeLists.txt` 只是薄 wrapper `include(keybeacon.cmake)`，不需要动），在**现有 `if(CONFIG_ZMK_KEYBEACON AND CONFIG_ZMK_BLE AND CONFIG_ZMK_SPLIT_ROLE_CENTRAL)` 块之前**添加 `include(${CMAKE_CURRENT_LIST_DIR}/cmake/zmk_compat.cmake)`；探测必须在 `zephyr_library_sources(keybeacon.c)` 之前跑完，这样 `ZMK_KEYBEACON_COMPAT_DEFINES` 对 keybeacon.c 的编译期生效
- [X] T031 验证 `../zmk-keybeacon/zephyr/module.yml`：确认 `build.cmake` 字段**已经**指向 `.`（现网 2026-10-12 验证确实如此），`build.kconfig` 已指向 `Kconfig.keybeacon`——如果真的已经对齐，本任务**不改**任何内容，仅在 commit message 里标注 "verified: module.yml unchanged"

### Foundational CMake smoke 测试

- [X] T032 [P] 创建 `../zmk-keybeacon/scripts/tests/smoke-cmake.sh`：对 `zmk-legacy` / `zmk-renamed` / `zmk-missing` 三个 fixture tree 分别调用 `cmake -S <minimal-zephyr-project-stub> -B <builddir> -DZMK_ROOT=<fixture>` 并断言各自退出码（0 / 0 / 非 0）与 stdout 关键字段（legacy: `✓` 行 + `HAS_LEGACY_ENDPOINT`；renamed: `✓` 行无 `HAS_LEGACY_ENDPOINT`；missing: 完整 banner）
- [X] T033 [P] 将 `smoke-cmake.sh` 加入 CI PR check 的 required job（workflow 文件在 Phase 4 创建，这里只准备脚本）

**Checkpoint**: `compatibility.yaml` 作为真相源落位；validate_compat + check_zmk_compat + CMake 胶水 + Kconfig 全部齐全；本地可跑 `pytest scripts/tests/` 全绿、可跑 `scripts/tests/smoke-cmake.sh` 全绿。此时 ZMK 兼容 revision 下构建通过（但 C 代码未改，若 ZMK main-HEAD 已重命名 `zmk_endpoints_selected`，构建仍会在 C 层挂——这正是 Phase 3 US1 要闭环的部分）。

---

## Phase 3: User Story 1 - 消费者 `west update` 后不会静默编译失败 (Priority: P1) 🎯 MVP

**Goal**: 消费者在搭配兼容 ZMK revision 时 `west build` 能通过并产出可烧录 KBP 1.1 固件（含 CONNECTIVITY）；在搭配不兼容 revision 时 CMake 阶段 fail-fast 给出可执行 banner；在显式开启 escape hatch 时降级为 warning。本 phase 完成即 feature 的 MVP。

**Independent Test**: 按 [quickstart.md](specs/003-zmk-revision-pinning/quickstart.md) 的 US1 Scenario 1/2/3 三个子场景在 Totem 配置下跑通，Pass/Fail 判据全绿。

### C 代码的渐进 forward-compat（修复 002 遗留）

- [X] T034 [US1] 修改 `../zmk-keybeacon/keybeacon.c` **第 243 行**（唯一调用点，整个模块仅此一处用到 `zmk_endpoints_selected`），用 `#if defined(ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT) ... #else ... #endif` 包裹对该函数的调用；`#if` 分支调 `zmk_endpoints_selected()`（旧 API，ZMK < `6e7e0de2`），`#else` 分支调 ZMK ≥ `6e7e0de2` 的新 API `zmk_endpoint_get_selected()`——两分支返回类型都是 `struct zmk_endpoint_instance`（ZMK commit `860e53b3` 2024-03-27 后稳定），因此两分支下游代码（`switch (ep.transport)` 的部分）无需变化；`#include <zmk/endpoints.h>` 在 `#if IS_ENABLED(CONFIG_ZMK_KEYBEACON_CONNECTIVITY)` 块里已有（现文件行 ~34-37），不新增 include；注释块显式引用 [research.md D6](specs/003-zmk-revision-pinning/research.md) 作为设计出处
- [X] T035 [US1] 用 `grep -n "zmk_endpoints_selected\|zmk_endpoint_get_selected" ../zmk-keybeacon/keybeacon.c` 复查：所有直接调用点都已被 `#if defined` 包裹（预期：行 243 周围的 `#if/#else/#endif` 块是唯一匹配位置）；更新 `compatibility.yaml:required_symbols[0].used_in` 字段确保与实际文件一致（应已对齐为 `keybeacon.c`，若 T005 的清单与此扫描不符，由本任务修正）

### CMake 探测器把 emit_macro 真的透传到 C 编译

- [X] T036 [US1] 验证 `cmake/zmk_compat.cmake` 的 `add_compile_definitions(${ZMK_KEYBEACON_COMPAT_DEFINES})` 对本模块 `zephyr_library_sources(keybeacon.c)` 生效：**由 smoke-cmake.sh 第 [1/4] 和 [2/4] 的 DEFINES 行断言覆盖**（legacy fixture → 含 `-DZMK_KEYBEACON_HAS_LEGACY_ENDPOINT=1`；renamed fixture → 不含）。真实 `#error` 负测试需要 Zephyr 工具链环境，由 T039 真机验证确认

### Scenario 2 的 banner integration test（跨 Python+CMake 的端到端）

- [X] T037 [P] [US1] 扩展 `../zmk-keybeacon/scripts/tests/smoke-cmake.sh`：对 `zmk-renamed` fixture 新增断言——"configure 退出码 0 且 `✓` 行**不含** `HAS_LEGACY_ENDPOINT` 字样"（表示 fallback 命中、走新 API 分支）；对 `zmk-legacy` 新增断言——"configure 退出码 0 且 `✓` 行**含** `HAS_LEGACY_ENDPOINT` 字样"（表示旧 API 分支生效）；对 `zmk-missing` 新增断言——"configure 退出码非 0 且 stderr 字节级与 `expected_banner_v1.1.4.txt` 一致"
- [X] T038 [P] [US1] 为 Scenario 3 新增 fixture 子脚本 `smoke-cmake-escape.sh`：**合并到 smoke-cmake.sh 第 [4/4] 节**——对 `zmk-missing` fixture + `--allow-incompat`（映射到 `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y`）跑 probe，断言"退出码 0 且 stdout 含 `WARN:` block 且含 `would have failed on symbol`"

### 真实硬件 end-to-end 验证（人工，不自动化）

- [ ] T039 [US1] 在 Totem 键盘上执行 [quickstart.md US1 Scenario 1](specs/003-zmk-revision-pinning/quickstart.md) 的完整步骤：用 `v1.1.4` + ZMK sha `4dd95d7`（已验证的 renamed-era 冻结 pin，走 `#else` 分支）组合构建、烧录、BLE 连 macOS KeyBeacon app，确认 Connectivity & Battery 卡片 4 行齐全；运行 `python3 conformance/conformance_tool.py --timeout 15` 并记录输出退出码为 0、`characteristics.AA440AA2.present == true`、`check_us1/check_us2_split_link/check_us3_output_endpoint == PASS`。将关键截图/文本保存到 `specs/003-zmk-revision-pinning/manual-run-log.md`
- [ ] T040 [US1] 在 Totem 键盘上执行 [quickstart.md US1 Scenario 2](specs/003-zmk-revision-pinning/quickstart.md)：把 ZMK pin 到一个主动破坏的 fixture（例如本地复制一份 ZMK main 后手工从 `app/include/zmk/endpoints.h` 删除两个符号——`zmk_endpoints_selected` 与 `zmk_endpoint_get_selected`——模拟 `zmk-missing` fixture 的真实场景；或直接构造一个两个符号都没有的 ZMK fork commit），不加 escape hatch，跑 `west build` 并记录输出的完整 banner 到 `specs/003-zmk-revision-pinning/manual-run-log.md`；验证 banner 字段与 [fail-fast-banner.md](specs/003-zmk-revision-pinning/contracts/fail-fast-banner.md) 契约逐项对齐

**Checkpoint**: US1 全部三个子场景在本地 fixture + 真实硬件上都 pass；MVP 达成。此时可以把 `v1.1.4` 发 pre-release tag（`v1.1.4-rc1`）供早期用户试用。

---

## Phase 4: User Story 2 - 维护者感知上游漂移 (Priority: P2)

**Goal**: ZMK main 发生破坏性变更后，zmk-keybeacon 的维护者在 ≤ 24 h 内收到自动化信号（自动开 issue + README badge 变红）；对 compat 相关路径的 PR 必须通过矩阵 build。

**Independent Test**: 按 [quickstart.md US2](specs/003-zmk-revision-pinning/quickstart.md)，手动 `workflow_dispatch` 触发 workflow 时能跑完全部矩阵；手工构造一个破坏性 drill（例如 patch `zmk-renamed` fixture 让 CI 跑它）能导致 workflow fail + 自动开出 1 条 `compat-break` label 的 issue。

### CI workflow 的派生器

- [X] T041 [US2] 实现 `../zmk-keybeacon/scripts/regen_ci.py`：读 `compatibility.yaml:ci` 字段，基于 jinja2-less 的 string template 生成 `.github/workflows/zmk-main-compat.yml`，格式严格对齐 [ci-workflow-contract.md](specs/003-zmk-revision-pinning/contracts/ci-workflow-contract.md) 的 "Workflow 结构（骨架）" 节；输出首行加 `# ⚠️ 此文件由 scripts/regen_ci.py 从 compatibility.yaml 派生，请勿手改。`
- [X] T042 [US2] 为 `regen_ci.py` 加 `--check` 模式：生成到临时文件后与现有 `.github/workflows/zmk-main-compat.yml` 做字节级 diff，不等时退出码 1；供 CI 的 `validate-manifest` job 调用，防手改漂移
- [X] T043 [P] [US2] 编写 `../zmk-keybeacon/scripts/tests/test_regen_ci.py`：参数化 `compatibility.yaml:ci` 的几个变体（默认值、改 schedule、改 matrix），断言输出 workflow yaml 中对应字段正确反映

### 生成实际的 workflow yaml 并提交

- [X] T044 [US2] 运行 `python3 scripts/regen_ci.py` 生成 `../zmk-keybeacon/.github/workflows/zmk-main-compat.yml` 并提交；逐行对照 [ci-workflow-contract.md](specs/003-zmk-revision-pinning/contracts/ci-workflow-contract.md) 的 "Workflow 结构（骨架）" 复查：含 `validate-manifest / build / file-issue-on-main-break` 三个 job、`fail-fast: false`、`on_schedule_failure` 的 issue 去重逻辑
- [X] T045 [US2] 在模块仓创建 GitHub label `compat-break`（颜色 `d73a4a`）：用 `gh label create compat-break --color d73a4a --description "ZMK upstream broke zmk-keybeacon build"`，并把该命令记录到 `../zmk-keybeacon/scripts/one-time-setup.sh`（给未来维护者看）

### README badge 与 Compatibility 占位块

- [X] T046 [US2] 修改 `../zmk-keybeacon/README.md` 的顶部，在标题下紧邻处添加 GitHub Actions badge：`[![ZMK compat matrix](https://github.com/<org>/zmk-keybeacon/actions/workflows/zmk-main-compat.yml/badge.svg)](https://github.com/<org>/zmk-keybeacon/actions/workflows/zmk-main-compat.yml)`——`<org>` 替换为实际 org（本任务由实施者按仓库归属判断）
- [X] T047 [US2] 修改 `../zmk-keybeacon/README.md`，新增顶级章节 `## Compatibility`，位置在 Install 节之前；章节内放 `<!-- COMPAT:BEGIN -->` 和 `<!-- COMPAT:END -->` 之间的空占位（内容由 Phase 5 的 generator 填）；章节文字含"参见 [compatibility-troubleshooting] 节"交叉引用

### CI 的 drill 验证

- [X] T048 [US2] 本地 drill：手工把 `../zmk-keybeacon/compatibility.yaml:required_symbols` 新增一条明显不存在的符号（例如 `zmk_definitely_does_not_exist`），本地跑 `pytest scripts/tests/ && python3 scripts/validate_compat.py` 验证会红；commit 到临时分支并 `gh workflow run zmk-main-compat.yml -r <branch>`，验证 workflow 跑完后变红且**在 cron 触发才开 issue、`workflow_dispatch` 不开 issue**（即 scenario 2 的"事件守卫"）；清理 drill commit

**Checkpoint**: US2 达成——每日 06:00 UTC 自动跑 CI、PR 修 compat 路径必须过矩阵、CI 变红时自动开 issue。README 顶部 badge 可见。

---

## Phase 5: User Story 3 - 废弃 `.conf` workaround，恢复默认开启 CONNECTIVITY (Priority: P2)

**Goal**: v1.1.3 的消费者升级到 v1.1.4 后，按文档删除 `.conf` 里的历史 workaround，构建继续通过且 host 侧 CONNECTIVITY 卡片自动恢复。

**Independent Test**: 按 [quickstart.md US3](specs/003-zmk-revision-pinning/quickstart.md)，在 Totem 配置上对比"保留 workaround vs 删除 workaround"两次 build，`AA440AA2.present` 翻转为 `true`。

### Compatibility 表自动生成

- [ ] T049 [P] [US3] 实现 `../zmk-keybeacon/scripts/update-readme-table.py`：用 `git for-each-ref --sort=creatordate 'refs/tags/v*' --format='%(refname:short)'` 列全部历史 tag，对每个 tag 用 `git show <tag>:compatibility.yaml` 读 snapshot（若不存在则跳过并标注 "legacy"）；生成 markdown 表写入 `../zmk-keybeacon/README.md` 的 `<!-- COMPAT:BEGIN -->..<!-- COMPAT:END -->` 块
- [X] T050 [P] [US3] 为 `update-readme-table.py` 加 `--check` 模式：生成到内存后与现有 README 做 diff，不等时退出码 1；供 pre-commit hook 和 CI 使用
- [X] T051 [P] [US3] 编写 `../zmk-keybeacon/scripts/tests/test_update_readme_table.py`：造 2-3 个假 tag 和假 compatibility.yaml 的历史，断言生成的 markdown 表的行数、列顺序、必含字段（tag、known-good range、notes）

### 升级指南（本仓职责）

- [X] T052 [P] [US3] 新建 `specs/002-zmk-keybeacon-kbp11/upgrade-notes.md`（中英双语，遵循 Constitution Principle VI）：首部交叉引用 [003 spec](specs/003-zmk-revision-pinning/spec.md) 和 [003 plan](specs/003-zmk-revision-pinning/plan.md)；核心内容为"从 v1.1.3 升级到 v1.1.4 的三步"——(1) 改 `west.yml` 的 `zmk-keybeacon.revision` 为 `v1.1.4`、(2) 从 `config/<shield>.conf` 删除以下 workaround 行（显式列出 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n` 及任何其他 `CONFIG_ZMK_KEYBEACON_CHAR_*=n` 行）、(3) `west update && west build -p && flash`；并附"如遇不兼容 ZMK"的 fallback 指引交叉引用 [fail-fast-banner.md](specs/003-zmk-revision-pinning/contracts/fail-fast-banner.md)
- [X] T053 [P] [US3] 在 `specs/002-zmk-keybeacon-kbp11/spec.md` 末尾 Related Work 节追加一行："升级到 v1.1.4：参见 `upgrade-notes.md` 与 `specs/003-zmk-revision-pinning/`"

### 发 Release 前的收口

- [X] T054 [US3] 修改 `../zmk-keybeacon/CHANGELOG.md`，新增 `## [1.1.4] - YYYY-MM-DD` 条目，内容：(a) Fixed: build against newer ZMK revisions that renamed `zmk_endpoints_selected` → `zmk_endpoint_get_selected`（ZMK commit `6e7e0de2` *"feat(endpoints): add "no endpoint" value (#3140)"*, 2026-02-12）、(b) Added: build-time ZMK revision compatibility contract (`compatibility.yaml`, `cmake/zmk_compat.cmake`, `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK`)、(c) Added: daily CI matrix verifying ZMK main-HEAD + two frozen pins (`4dd95d7` renamed-era, `e844eca2` legacy-era)、(d) Docs: new Compatibility section in README、(e) Note: no wire-protocol change (bit-for-bit identical with v1.1.3)、(f) 交叉链接 `https://github.com/ykiewang/keybeacon/blob/main/specs/003-zmk-revision-pinning/spec.md`（org 由 2026-10-12 探测确认为 `ykiewang`）
- [X] T055 [US3] 运行 `python3 scripts/update-readme-table.py`（T049）在模块仓更新 README 的 Compatibility 块，提交 diff；本地跑 `python3 scripts/update-readme-table.py --check` 验证无 diff
- [X] T056 [US3] 在 Totem 键盘上执行 [quickstart.md US3](specs/003-zmk-revision-pinning/quickstart.md) 的对比验证：先用保留 workaround 的 conf 跑 conformance_tool（AA440AA2.present=false），再按 upgrade-notes 删 workaround 跑第二次（AA440AA2.present=true），把两次输出追加到 `specs/003-zmk-revision-pinning/manual-run-log.md`

**Checkpoint**: US3 达成。消费者从 v1.1.3 迁 v1.1.4 的全链路已验证——文档清晰、Compat 表自动化、workaround 可安全删除。

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 发 release、本仓 roadmap 同步、可选的 pre-commit hook、以及给未来维护者留下的 one-time setup 文档。

- [X] T057 [P] 在 `../zmk-keybeacon/` 添加 pre-commit hook 配置（`../zmk-keybeacon/.pre-commit-config.yaml`，可选）：hooks 包含 `validate_compat.py --check-git-tag`（可条件执行）、`regen_ci.py --check`、`update-readme-table.py --check`——防三处派生物与真相源漂移
- [X] T058 [P] 修改本仓顶层 `README.md` 的 Roadmap 节：在 "A. Connectivity & Power" 行之后追加一行 "`v1.1.4 — ZMK revision compatibility contract (shipped)`" 并链接 `specs/003-zmk-revision-pinning/`
- [ ] T059 在 `../zmk-keybeacon/` 的 feature 分支上发合并 PR：按 Principle V 的 compliance review 要求，PR body 内含 "Constitution Check" 段落，逐项说明本 PR 对 Principle I–VI 的影响（可照抄 [plan.md Post-Design Constitution Re-Check](specs/003-zmk-revision-pinning/plan.md)）；PR 必须跑过本次新增的 CI 矩阵
- [ ] T060 PR merge 后，在 `../zmk-keybeacon/` 的 main 上打 tag `v1.1.4`：`git tag -a v1.1.4 -m "KBP 1.1 compatibility contract and endpoint API forward-compat"`；push tag：`git push origin v1.1.4`；在 GitHub release 页填 release notes（可从 CHANGELOG v1.1.4 条目复制）
- [ ] T061 [P] 本仓的 `specs/003-zmk-revision-pinning/manual-run-log.md`（由 T039/T040/T056 累积）追加 "feature closeout" 段：含最终 release URL、tag sha、对 FR/SC 覆盖情况的最终确认

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup** → **Phase 2 Foundational** → **Phase 3 US1 (MVP)** → **Phase 4 US2 / Phase 5 US3**（可并行） → **Phase 6 Polish**
- Phase 4 和 Phase 5 **仅在 Phase 3 Checkpoint 之后**才可并行启动——US3 的 "删 workaround 后构建通过" 依赖 US1 的 C 代码修复（T034）。
- Phase 6 的 T059/T060 发 release 任务 **强依赖 Phase 3/4/5 全部完成**。

### 关键 Blocking 链

```text
T001 setup branch
  └→ T002/T003/T004 scaffolding [P]
      └→ T005 compatibility.yaml ──┬→ T011 validate_compat 主入口 ──→ T016-T021 check_zmk_compat ──→ T029 CMake 胶水 ──→ T030/T031 CMakeLists/module.yml
                                   │
                                   └→ T007 Kconfig
          └→ T006 schema [P]
              └→ T008/T009/T010 validate L1/L2/L3 [P]
                  └→ T011 integration

      └→ T022-T025 fixtures [P]
          └→ T026/T027/T028 check_zmk_compat 单测 [P] 和字节级回归

Phase 2 全绿 → T032/T033 smoke-cmake [P]
             → T034/T035 C ifdef (US1)
             → T036 Macro passthrough 验证
             → T037/T038 integration smoke [P]
             → T039/T040 真实硬件 (manual)
```

### User Story Dependencies

- **US1 (P1)**: 依赖 Phase 2 完成；不依赖 US2/US3。
- **US2 (P2)**: 依赖 Phase 2 的 validate_compat.py 完整，才能让 CI 的 `validate-manifest` 跑起来；不依赖 US1 的 C 代码。
- **US3 (P2)**: 功能上依赖 US1（T034）才能让"删 workaround 后真的 build 通过"；文档/生成器层面独立。

### 并行机会

**Setup Phase 内**：T002/T003/T004 可并行。

**Foundational Phase 内**（T005 之后）：
- T006 (schema) [P] 独立
- T007 (Kconfig) [P] 独立
- T008/T009/T010 (L1/L2/L3) [P] 分函数，整合在 T011
- T012-T015 (validate 单测) [P] 独立
- T016/T017/T020 (check_zmk 纯函数) [P] 可并行；T018/T019 依赖 T016 的 symbol_present 结构
- T022/T023/T024/T025 (fixtures) [P] 独立
- T026/T027/T028 (check 单测) 必须在 T016-T021 之后
- T032/T033 (smoke) 必须在 T029 之后

**US1 内**：T037/T038 可并行（不同脚本/场景）。

**US2 内**：T043 (test_regen_ci) [P] 与 T044 (生成实际 yaml) 并行；T046/T047 README edit 可并行。

**US3 内**：T049/T050/T051 (table generator + 测) [P]；T052/T053 (本仓文档) [P] 独立。

**Polish Phase 内**：T057/T058/T061 可并行；T059 需要 US1-3 全完成；T060 需要 T059 merge。

---

## Parallel Example: Foundational Phase Fixture 创建

```bash
# 一轮并行开 4 个 fixture tree：
# 一个开发者可用 4 个终端或 4 个任务并行推：

# 任务 T022: zmk-legacy 全命中（旧 API）
mkdir -p ../zmk-keybeacon/scripts/tests/fixtures/zmk-legacy/app/include/zmk
# endpoints.h 含 zmk_endpoints_selected(...)、ble.h 含 3 个 _active_profile_* 符号...

# 任务 T023: zmk-renamed 新 API 替换
mkdir -p ../zmk-keybeacon/scripts/tests/fixtures/zmk-renamed/app/include/zmk
# endpoints.h 只含 zmk_endpoint_get_selected(...)（删除旧符号）、ble.h 同 legacy...

# 任务 T024: zmk-missing 直接删符号
mkdir -p ../zmk-keybeacon/scripts/tests/fixtures/zmk-missing/app/include/zmk
# endpoints.h 两个 endpoint 符号都没有、ble.h 同 legacy...

# 任务 T025: zmk-header-missing header 整个不存在
mkdir -p ../zmk-keybeacon/scripts/tests/fixtures/zmk-header-missing/app/include/zmk
# 不建 endpoints.h、ble.h 同 legacy...
```

---

## Parallel Example: US2 Phase 内

```bash
# 并行推进：
# Dev A: T041 → T042 (regen_ci.py 实现)
# Dev B: T043 (test_regen_ci.py，可以用 pytest skipif 等 T041 完成)
# Dev C: T046 (README badge) + T047 (Compatibility 占位块) —— 两处文档改动独立
# T044 (实际生成 workflow yaml) 待 T041 完成后由 A 继续
# T045 (gh label 创建) 任意时刻可做
# T048 (drill 验证) 必须 T044 + T045 都完成后才能跑
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. 跑完 Phase 1 Setup（≤ 1 h，mostly 分支/目录）
2. 跑完 Phase 2 Foundational（预计 1-2 天：真相源 + 校验器 + 探测器 + CMake 胶水 + 单测 fixture + smoke 脚本）
3. 跑完 Phase 3 US1（预计 0.5-1 天：C 代码 ifdef + end-to-end 硬件验证）
4. **STOP & VALIDATE**：按 quickstart US1 全部三个 scenario 过一遍，签字
5. 发 `v1.1.4-rc1` pre-release，让早期 002 用户试用

### Incremental Delivery

1. MVP (US1) 稳定 ≥ 1 周 → 启动 Phase 4 US2（CI 工程化）与 Phase 5 US3（文档收口）并行
2. US2 跑绿第一个日度 cron（相当于 7 天观察期）→ 允许 US3 发公告（避免消费者升级后 CI 还没沉淀）
3. US2 + US3 完成 → 跑 Phase 6 Polish → 发 `v1.1.4` 正式 tag

### Parallel Team Strategy

两人团队：
- 开发者 A：Phase 2 的 validate_compat + check_zmk_compat（T005-T028 大部分）
- 开发者 B：Phase 2 的 CMake 胶水 + Kconfig + fixture tree（T006/T007/T022-T025/T029-T033）

MVP 后：
- 开发者 A：Phase 4 US2（CI 工程化）
- 开发者 B：Phase 5 US3（docs + generator）
- 两人同步在 Phase 6 polish

---

## FR / SC / 覆盖矩阵回顾

| 任务 | 覆盖的 FR | 覆盖的 SC |
|---|---|---|
| T005 | FR-001 | — |
| T016–T021, T026 | FR-002 | SC-003 |
| T018, T028, T037 | FR-003 | SC-003 |
| T007, T019, T038 | FR-004 | — |
| T041–T048 | FR-005, FR-006 | SC-002 |
| T047, T049–T051, T055 | FR-007 | SC-005 |
| T034, T035, T039 | FR-008 | SC-001, SC-004 |
| T052 | FR-009 | — |
| T005, T010, T016–T021 | FR-010 | — |

全部 10 个 FR + 5 个 SC 均有对应 tasks。

---

## Notes

- `[P]` 任务 = 不同文件、无依赖，可并行。
- `[Story]` 标签 = 该任务唯一归属的 user story；Setup/Foundational/Polish 阶段不加 story 标签。
- 本 feature 的所有 implement 文件落在 `../zmk-keybeacon/` 的 feature 分支，发 PR 后 merge 到该模块仓 main；本仓 (`keybeacon`) 的改动仅在 `specs/003-...` + `specs/002-.../upgrade-notes.md` + 顶层 `README.md` 的 roadmap 一行。
- "手动硬件验证"任务（T039/T040/T056）不自动化，但产物（`manual-run-log.md`）本仓追踪，供 reviewer 审阅。
- 若未来发现 ZMK main-HEAD 在 `6e7e0de2` 之后又做了一次 endpoints 相关重命名（即新 API 从 `zmk_endpoint_get_selected` 变成第三个名字），T005 的 `fallback` 列表需追加新名、T034 的 `#else` 分支需再加 `#elif defined(ZMK_KEYBEACON_HAS_RENAMED_V2_ENDPOINT)` 等——这个追加**本身**就是在跑 compat 契约（符合预期）；且本次 v1.1.4 的 `#ifdef` 骨架就是为了让这类扩展成本保持线性。
