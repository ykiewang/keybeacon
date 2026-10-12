# Data Model: zmk-keybeacon 模块的 ZMK revision 版本契约

**Phase**: 1 (Design & Contracts) · **Date**: 2026-10-12 · **Spec**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md) · **Research**: [research.md](./research.md)

本 feature 的"数据"不是运行时持久化数据，而是 **构建期配置契约**（declarative config）。本文件定义 `../zmk-keybeacon/compatibility.yaml` 的 schema、各字段的语义与校验规则、以及它被谁消费、怎么派生出下游产物。

## 实体概览

```text
                          ┌────────────────────────┐
                          │  compatibility.yaml    │
                          │  (SOURCE OF TRUTH)     │
                          └───────────┬────────────┘
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         │                            │                            │
         ▼                            ▼                            ▼
  check_zmk_compat.py        zmk-main-compat.yml         update-readme-table.py
  (configure-time probe)     (GitHub Actions CI)         (release-time doc gen)
         │                            │                            │
         ▼                            ▼                            ▼
  CMake 诊断 / 宏注入          build pass/fail + issue       README.md Compatibility 表
```

**单一真相源原则**：任何改到"模块支持哪些 ZMK revision"的改动，有且仅有一个修改点——`compatibility.yaml`。其余三处（Python 探测、CI、README 生成器）从该文件派生，禁止手改。

## Entity: CompatibilityManifest（即 `compatibility.yaml` 根对象）

| 字段 | 类型 | 必填 | 默认值 | 语义 |
|---|---|---|---|---|
| `module_version` | string (semver) | ✅ | — | 本 `compatibility.yaml` 对应的 zmk-keybeacon tag；发 tag 时必须与 git tag 一致（CI 校验） |
| `zmk_known_good` | `KnownGoodRange` 对象 | ✅ | — | 用户面向的"推荐 pin"信息（仅出现在诊断/文档，不作硬 gate） |
| `required_symbols` | `RequiredSymbol[]` 数组 | ✅ | — | 本 tag 的 C 代码调用的 ZMK 内部符号清单；每一项都是一个硬 gate |
| `escape_hatch` | `EscapeHatch` 对象 | ✅ | — | 用户自担风险开关的声明（名称 + 默认值） |
| `ci` | `CiConfig` 对象 | ❌ | 见 D4/D7 | CI matrix 与通知渠道的可覆盖配置 |

**顶层校验规则**：
- `module_version` MUST 匹配 `^\d+\.\d+\.\d+$`。
- 所有 `required_symbols[].name` 在数组内 MUST 唯一（防止同名符号被声明两次导致探测器行为不一致）。
- `yaml.safe_load` MUST 成功（禁止 Python object tag 等不安全特性）。

## Entity: KnownGoodRange

```yaml
zmk_known_good:
  lower: d33f7ca       # inclusive，7 位 git short sha
  upper: a3f7d21       # inclusive，可为 null 代表 unbounded
  branch_hint: main    # upper 来自哪个 ZMK 分支，用于诊断信息渲染
```

| 字段 | 类型 | 必填 | 语义 |
|---|---|---|---|
| `lower` | string (7-40 chars hex) | ✅ | 本 tag 测试过的最旧 ZMK commit |
| `upper` | string (7-40 chars hex) \| `null` | ✅ | 本 tag 测试过的最新 ZMK commit；`null` 表示"仍在跟 main，没遇到破坏性变更" |
| `branch_hint` | string | ❌ | 默认 `main`；多分支支持时标识 upper 所在分支 |

**语义约束**：
- `lower` 与 `upper` 都 MUST 是 ZMK repo 中真实存在的 commit sha；CI 的 workflow 可做校验（`git -C zmk cat-file -e <sha>`）。
- 该范围 **仅用于渲染诊断信息和 README 表**，不作构建通过与否的硬 gate——硬 gate 是 `required_symbols` 的探测结果（见 research D2）。

## Entity: RequiredSymbol

```yaml
required_symbols:
  - name: zmk_endpoints_selected
    header: zmk/endpoints.h
    used_in: keybeacon.c
    fallback:
      - zmk_endpoint_get_selected
    emits_macro: ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT
```

| 字段 | 类型 | 必填 | 默认值 | 语义 |
|---|---|---|---|---|
| `name` | string (C identifier) | ✅ | — | 主符号名，优先在 header 中探测 |
| `header` | string (相对路径) | ✅ | — | 相对 `${ZMK_ROOT}/app/include/` 的头文件路径（例如 `zmk/endpoints.h`） |
| `used_in` | string (相对路径) | ✅ | — | 本模块调用该符号的 C 文件，用于诊断信息"called from"字段 |
| `fallback` | string[] | ❌ | `[]` | 候补符号名列表（上游重命名后的新名），探测器按顺序尝试 |
| `emits_macro` | string (C macro name) | ❌ | 无 | 若命中 `name`（而非 fallback），探测器 MUST 向 CMake emit 该宏；用于 C 代码 `#if defined()` 分叉（见 research D6） |

**语义约束**：
- `name` 和 `fallback` 中的每一项 MUST 是合法的 C 标识符（`^[A-Za-z_][A-Za-z0-9_]*$`）。
- `header` MUST 不以 `/` 开头（必须是相对路径）。
- `emits_macro` 的"命中条件"：当且仅当探测器在 `header` 中成功匹配到 `\bname\s*\(` 时 emit；若匹配到 `fallback[i]` 则不 emit（表示上游已重命名，C 代码走 `#else` 分支）。
- 若 `name` 和所有 `fallback` 都未匹配，探测器 MUST fail-fast。

- **派生物**：
- 探测器输出 `-D<emits_macro>` 到 CMake，CMake 转发到 `target_compile_definitions`。
- 诊断信息"Called from"字段直接引用 `used_in`。
- 本列表 MUST 与模块中的实际符号调用严格对应——`check_zmk_compat.py` 的测试 fixture 要求 "`compatibility.yaml` 声明的每个 `required_symbols[].used_in` 文件 **必须** `grep` 得到对应 `name` 或 `fallback[i]` 的调用"。这是防止"声明和代码脱钩"的 lint。

## Entity: EscapeHatch

```yaml
escape_hatch:
  kconfig: CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK
  default: n
```

| 字段 | 类型 | 必填 | 默认值 | 语义 |
|---|---|---|---|---|
| `kconfig` | string | ✅ | — | 用户显式 `=y` 用于绕过 fail-fast 的 Kconfig 符号名 |
| `default` | `y` \| `n` | ✅ | — | 该 Kconfig 的默认值；按 research D8 的 Decision 固定为 `n` |

**语义约束**：
- 本 feature 的 Kconfig 符号命名由 research D8 固定：`CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK`，`default n`。
- 该字段写入 YAML 是为了让 `check_zmk_compat.py` 的诊断 banner 能直接从 `compatibility.yaml` 读取"开启后可绕过"的指引文本，不写死在 Python 源码里。

## Entity: CiConfig (可选)

```yaml
ci:
  schedule: "0 6 * * *"                        # cron，默认日度
  matrix:
    zmk_refs: [main, 4dd95d7, e844eca2]        # ZMK revision 列表（见 research D7）
    shields:  [totem_left]                     # ZMK shield 列表（和用户现网 CI 一致）
  on_schedule_failure:
    create_issue: true
    issue_label: compat-break
```

| 字段 | 类型 | 必填 | 默认值 | 语义 |
|---|---|---|---|---|
| `ci.schedule` | string (cron) | ❌ | `"0 6 * * *"` | 日度触发时间；按 research D4 可从日→周调整以控成本 |
| `ci.matrix.zmk_refs` | string[] | ❌ | `[main, 4dd95d7, e844eca2]` | 要测的 ZMK ref（branch/tag/sha）；默认覆盖 ZMK main + renamed-era 冻结 pin + legacy-era 冻结 pin |
| `ci.matrix.shields` | string[] | ❌ | `[totem_left]` | 要测的 shield 名（zmk-config 中的 shield）；默认与用户现网 CI 对齐 |
| `ci.on_schedule_failure.create_issue` | bool | ❌ | `true` | 日度 cron 失败时是否自动开 issue |
| `ci.on_schedule_failure.issue_label` | string | ❌ | `compat-break` | issue 的 label；用于去重查询 |

**语义约束**：
- 若 `ci` 整个块缺失，`.github/workflows/zmk-main-compat.yml` 使用上述所有默认值；若存在但只给部分字段，缺失字段也用默认。
- CI workflow 文件本身是**从 `compatibility.yaml` 的 `ci` 字段派生并提交到 git**（不是运行时生成）：维护者修改 `compatibility.yaml` 的 `ci` 字段 → 跑 `make regen-ci` → 提交生成的 `.yml` → PR review。好处是 workflow 永远与声明一致，坏处是多一个生成器。决策详见 contracts/ci-workflow-contract.md。

## 完整示例：v1.1.4 的 `compatibility.yaml`

```yaml
# compatibility.yaml — single source of truth for ZMK revision contract.
# Consumed by:
#   cmake/zmk_compat.cmake            (fail-fast at configure time)
#   .github/workflows/zmk-main-compat.yml (daily smoke build)
#   scripts/update-readme-table.py    (regenerate README table on release)

module_version: 1.1.4

zmk_known_good:
  # 跨 commit 6e7e0de2 (feat(endpoints): add "no endpoint" value (#3140), 2026-02-12)
  # 该 commit 把 zmk_endpoints_selected → zmk_endpoint_get_selected
  # 本模块通过 required_symbols[0].fallback 吃进来，故 known_good 跨越这个事件
  lower: e844eca2       # legacy-era 实证 commit（zmk_endpoints_selected 存在）
  upper: 4dd95d7        # renamed-era 实证 commit（zmk_endpoint_get_selected 存在，验证自 CI run 38043117244）
  branch_hint: main

required_symbols:
  # keybeacon.c:243 — 唯一跨 API 漂移点
  - name: zmk_endpoints_selected
    header: zmk/endpoints.h
    used_in: keybeacon.c
    fallback:
      - zmk_endpoint_get_selected
    emits_macro: ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT

  # keybeacon.c:218
  - name: zmk_ble_active_profile_is_connected
    header: zmk/ble.h
    used_in: keybeacon.c

  # keybeacon.c:222
  - name: zmk_ble_active_profile_index
    header: zmk/ble.h
    used_in: keybeacon.c

  # keybeacon.c:231
  - name: zmk_ble_active_profile_is_open
    header: zmk/ble.h
    used_in: keybeacon.c

escape_hatch:
  kconfig: CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK
  default: n

ci:
  schedule: "0 6 * * *"
  matrix:
    zmk_refs: [main, 4dd95d7, e844eca2]
    shields:  [totem_left]
  on_schedule_failure:
    create_issue: true
    issue_label: compat-break
```

## 状态与演化规则

本数据没有运行时状态机，但有 **tag-to-tag 的演化规则**，用于 reviewer 判断一个 PR 是否违反契约：

| 变更类型 | 允许的 `module_version` 跃迁 | 示例 |
|---|---|---|
| 新增一个 `required_symbols` 项（增加探测点） | PATCH 或 MINOR | v1.1.3→v1.1.4，新增 `zmk_endpoints_selected` 探测 |
| 更新 `known_good.upper` 到更新 sha | PATCH | 周期性对齐 ZMK main-HEAD |
| 为某个 `required_symbols` 项添加 `fallback`（吃上游重命名） | PATCH | ZMK 把 X 改名为 Y，模块通过 fallback 吃进来 |
| 移除某个 `required_symbols` 项（本模块已不再调用该符号） | MINOR | 代码重构 |
| 修改 `escape_hatch.kconfig` 符号名 | MAJOR | 对消费者 .conf 不兼容 |
| 修改 `escape_hatch.default` 的默认值 | MAJOR | 默认行为变 |

该表作为未来 reviewer checklist 的输入，不写死到工具里。

## Validation Rules Summary（给 reviewer / CI 使用）

1. **文件格式**：`compatibility.yaml` MUST pass `yaml.safe_load`，根对象为 mapping，无顶层 list。
2. **版本一致性**：发 tag `vX.Y.Z` 时，CI MUST 校验 `compatibility.yaml:module_version == X.Y.Z`。
3. **符号与代码一致性**：对每个 `required_symbols[i]`，`grep -E "\b(name|fallback\[0..\])\s*\(" ${used_in}` MUST 命中（防止 "声明了但代码不调用" 的死符号）。
4. **sha 存在性**：`known_good.lower/upper` MUST 在 ZMK repo 存在（CI check via `git cat-file -e`）。
5. **宏唯一性**：所有 `required_symbols[i].emits_macro` 在数组内 MUST 唯一；未设置 `emits_macro` 的项不参与此检查。
6. **Kconfig 一致性**：`escape_hatch.kconfig` MUST 以 `CONFIG_ZMK_KEYBEACON_` 开头，并实际在 `../zmk-keybeacon/Kconfig.keybeacon` 中声明。

Validation 1–6 由 `scripts/validate_compat.py`（可作为 `scripts/tests/` 的一部分）承载，CI 的 PR check 自动跑。

## 不在 Data Model 内的东西（显式排除）

- **运行时数据**：本模块的运行时数据（如 Connectivity 字符的 payload）在 KBP 1.1 协议中，由 `../protocol/README.md §14` 定义，不属于本 feature。
- **Zephyr `module.yml`**：仍遵循 Zephyr/west 标准 schema，本 feature **不改动** `module.yml`（现有 `build.cmake: .` + `build.kconfig: Kconfig.keybeacon` 已满足；`cmake/zmk_compat.cmake` 由 `keybeacon.cmake` 顶部 `include()` 调起，不需要新增 Zephyr module 入口）。
- **消费者 west.yml**：消费者侧的 `west.yml` 由消费者维护，模块侧不干预；但 README 的 Compatibility 章节会给示例片段。
