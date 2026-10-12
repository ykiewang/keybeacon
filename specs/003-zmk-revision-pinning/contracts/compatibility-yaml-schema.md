# Contract: `compatibility.yaml` Schema

**Phase**: 1 · **Status**: Normative · **Owner**: zmk-keybeacon maintainer · **Last updated**: 2026-10-12

本契约规定 `../zmk-keybeacon/compatibility.yaml` 的 schema，供 `check_zmk_compat.py`、CI workflow、`update-readme-table.py` 共享消费。schema 变更即契约变更，须经 reviewer 审查并对应 `module_version` 的 semver 跃迁（见 [data-model.md](../data-model.md) 的 "状态与演化规则"）。

## 适用范围

- 文件路径：`../zmk-keybeacon/compatibility.yaml`（repo root，唯一）
- 文件编码：UTF-8，LF 行尾
- 消费端：
  - **Python**：`scripts/check_zmk_compat.py`、`scripts/validate_compat.py`、`scripts/update-readme-table.py`
  - **CMake**（间接）：通过 `execute_process` 调用 Python，不直接读 YAML
  - **CI**（间接）：workflow 由 `scripts/regen_ci.py` 从 YAML 的 `ci:` 字段派生

## JSON Schema

```yaml
# JSON Schema Draft 2020-12 (以 YAML 书写，但 schema 本身是 JSON Schema)
$schema: https://json-schema.org/draft/2020-12/schema
$id: https://github.com/<org>/zmk-keybeacon/compatibility.schema.yaml
title: zmk-keybeacon CompatibilityManifest
type: object
additionalProperties: false
required: [module_version, zmk_known_good, required_symbols, escape_hatch]
properties:
  module_version:
    type: string
    pattern: '^\d+\.\d+\.\d+$'
    description: Semver, must match the git tag at release time.

  zmk_known_good:
    type: object
    additionalProperties: false
    required: [lower, upper]
    properties:
      lower:
        type: string
        pattern: '^[0-9a-f]{7,40}$'
      upper:
        oneOf:
          - { type: string, pattern: '^[0-9a-f]{7,40}$' }
          - { type: 'null' }
      branch_hint:
        type: string
        default: main

  required_symbols:
    type: array
    minItems: 1
    uniqueItems: true          # 由 validate_compat.py 用 name 字段做严格去重
    items:
      type: object
      additionalProperties: false
      required: [name, header, used_in]
      properties:
        name:
          type: string
          pattern: '^[A-Za-z_][A-Za-z0-9_]*$'
        header:
          type: string
          pattern: '^[A-Za-z0-9_./-]+\.h$'   # 相对路径，不以 / 开头
          not: { pattern: '^/' }
        used_in:
          type: string
          pattern: '^[A-Za-z0-9_./-]+\.(c|h)$'
        fallback:
          type: array
          default: []
          items:
            type: string
            pattern: '^[A-Za-z_][A-Za-z0-9_]*$'
        emits_macro:
          type: string
          pattern: '^[A-Z_][A-Z0-9_]*$'

  escape_hatch:
    type: object
    additionalProperties: false
    required: [kconfig, default]
    properties:
      kconfig:
        type: string
        pattern: '^CONFIG_ZMK_KEYBEACON_[A-Z0-9_]+$'
      default:
        enum: [y, n]

  ci:
    type: object
    additionalProperties: false
    properties:
      schedule:
        type: string
        default: "0 6 * * *"
      matrix:
        type: object
        additionalProperties: false
        properties:
          zmk_refs:
            type: array
            minItems: 1
            default: [main, 4dd95d7, e844eca2]
            items: { type: string }
          shields:
            type: array
            minItems: 1
            default: [totem_left]
            items: { type: string }
      on_schedule_failure:
        type: object
        additionalProperties: false
        properties:
          create_issue:
            type: boolean
            default: true
          issue_label:
            type: string
            default: compat-break
            pattern: '^[a-z0-9-]+$'
```

## 校验层级

| 层级 | 校验器 | 失败后果 |
|---|---|---|
| **L1 — YAML syntax** | `yaml.safe_load` | 探测器 / CI / README-gen 任一调用点立即 abort，退出码 `3` |
| **L2 — Schema** | `scripts/validate_compat.py` 用 `jsonschema` 包验上面的 schema | PR check 变红、`make release` 中止 |
| **L3 — 语义** | `scripts/validate_compat.py` 内手写规则：<br>• `required_symbols[i].name` 全局唯一<br>• `emits_macro` 全局唯一<br>• `module_version` 与 `git describe --exact-match` 一致（release 时）<br>• 每个 `used_in` 文件实际 grep 得到 `name` 或 `fallback[*]` 的调用<br>• `known_good.lower/upper` 在 ZMK repo 存在 | 同 L2 |

L1–L3 全绿才允许进入 `check_zmk_compat.py` 的符号探测阶段。

## 向后兼容承诺

- **新增 optional 字段**：PATCH 允许（现有消费端读 YAML 时忽略未知字段，但 schema 的 `additionalProperties: false` 要求消费端更新 schema 以识别新字段——因此新增字段同时须更新 schema，由同一个 PR 完成）。
- **新增 required 字段**：MINOR，所有历史 tag 的 CI replay 不受影响（历史 tag 用历史 schema）。
- **删除字段 / 改语义**：MAJOR。本模块进入 2.x 时才考虑。

## 失败模式与错误码

| 场景 | 退出码（`validate_compat.py`） | 诊断信息包含 |
|---|---|---|
| YAML 语法错 | `3` | 行号、列号、unexpected token |
| L2 schema 错 | `4` | JSON Pointer 定位 + 期望值 vs 实际值 |
| L3 语义错 | `5` | 规则名 + 违规项的 YAML 块文本 |

退出码与 banner 契约（见 [fail-fast-banner.md](./fail-fast-banner.md)）对齐：`0 = ok`、`2 = 符号探测失败`、`3/4/5 = compatibility.yaml 自身有问题`。

## 不在本契约内（显式排除）

- `required_symbols[i].fallback` 的**顺序语义**：探测器按数组顺序尝试，第一个命中即停。顺序由本契约不规定，由 `check_zmk_compat.py` 实现文档说明。
- `ci.schedule` 的时区：GitHub Actions 默认 UTC，不可改；本契约不新增时区字段。
- 多语言 banner 的翻译键：banner 文本模板由 [fail-fast-banner.md](./fail-fast-banner.md) 规定，不在 YAML 内。
