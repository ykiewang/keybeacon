# Contract: Fail-Fast Banner UX

**Phase**: 1 · **Status**: Normative · **Owner**: zmk-keybeacon maintainer · **Last updated**: 2026-10-12

本契约规定 `check_zmk_compat.py` 在探测失败时输出到 stderr 的 **诊断 banner** 的结构、必含字段、措辞风格、退出码。这是 spec [US1 Scenario 2](../spec.md) 和 Constitution Principle IV（Observable Degradation Over Guessing）在构建时间的集中体现。

## 契约总览

| 契约项 | 要求 |
|---|---|
| **呈现时机** | CMake `configure` 阶段，`src/*.c` 进入编译图之前 |
| **输出流** | stderr（CMake 的 `message(FATAL_ERROR)` 自动输出到 stderr） |
| **退出码** | `0` = pass；`2` = 符号探测失败（本契约主场景）；`3/4/5` = compatibility.yaml 自身错（见 [compatibility-yaml-schema.md](./compatibility-yaml-schema.md)） |
| **语言** | 英文为主；可选中文镜像段（受 `LANG`/`LC_MESSAGES` 环境变量或 `--lang zh` 参数触发） |
| **宽度** | 72 字符硬换行，便于终端 / CI 日志展示 |
| **颜色** | 不使用 ANSI escape（CMake log 多数不渲染颜色，且 CI 日志里 escape code 污染视觉） |

## Banner 骨架（必含字段）

```text
╔══════════════════════════════════════════════════════════════════════╗
║  zmk-keybeacon {MODULE_VERSION} is INCOMPATIBLE with the current     ║
║  ZMK revision                                                        ║
╚══════════════════════════════════════════════════════════════════════╝

Current ZMK:    {CURRENT_SHA}  ({ZMK_PATH})
Known-good:    [{LOWER} .. {UPPER}]  (as of zmk-keybeacon {MODULE_VERSION} release)

Missing symbol: {SYMBOL_NAME}
  Location expected:  {ZMK_INCLUDE_ROOT}/{HEADER}
  Called from:        {USED_IN}
  Likely cause:       upstream ZMK renamed/removed this symbol after
                      {UPPER_IF_NOT_NULL_ELSE_LOWER} (see ZMK main-HEAD history).

─── How to fix ─────────────────────────────────────────────────────────

Pick ONE of the following:

[1] Pin ZMK back to a known-good revision (recommended):
      In your zmk-config's west.yml, under `projects:` → `zmk`:
          revision: {UPPER_OR_LOWER}
      Then:
          west update && west build -p

[2] Upgrade zmk-keybeacon to a tag that supports newer ZMK:
      Check {RELEASES_URL}
      for a tag released after {CURRENT_SHA} landed on ZMK main.

[3] Opt out of the compatibility check (NOT RECOMMENDED — build may
    still fail with cryptic C errors, and runtime behaviour is undefined):
      In your prj.conf / {USER_SHIELD_CONF}, add:
          {ESCAPE_HATCH_KCONFIG}=y

─── Also ───────────────────────────────────────────────────────────────

Please DO NOT disable individual characteristics in your .conf as a
workaround (e.g. CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n). That path
silently removes host-side features and masks the real issue.
```

## 变量来源表（给实现方 / reviewer 参考）

| 占位符 | 来源 |
|---|---|
| `{MODULE_VERSION}` | `compatibility.yaml:module_version` |
| `{CURRENT_SHA}` | `git -C ${ZMK_PATH} rev-parse --short HEAD` |
| `{ZMK_PATH}` | CMake 变量 `${ZMK_ROOT}` 或 `${ZEPHYR_BASE}/../zmk` 的实际路径 |
| `{LOWER}`, `{UPPER}` | `compatibility.yaml:zmk_known_good.lower/upper`；`upper` 为 null 时渲染为 `HEAD-at-release` 字符串 |
| `{SYMBOL_NAME}` | 首个 fail 的 `required_symbols[i].name` |
| `{ZMK_INCLUDE_ROOT}` | 固定 `${ZMK_ROOT}/app/include` |
| `{HEADER}` | 失败项的 `header` 字段 |
| `{USED_IN}` | 失败项的 `used_in` 字段 |
| `{UPPER_IF_NOT_NULL_ELSE_LOWER}` | `upper` 非 null 时用 upper，否则用 lower |
| `{RELEASES_URL}` | hardcoded `https://github.com/<org>/zmk-keybeacon/releases` |
| `{UPPER_OR_LOWER}` | 推荐 pin：`upper` 非 null 用 upper，否则 lower |
| `{USER_SHIELD_CONF}` | 从 CMake 变量 `${APPLICATION_CONFIG_DIR}` 推断，或退化为 `<your_shield>.conf` 占位 |
| `{ESCAPE_HATCH_KCONFIG}` | `compatibility.yaml:escape_hatch.kconfig` |

## 多个符号同时失败

**Decision**: 只渲染首个失败符号的详细 banner，其余以紧凑列表追加："Also missing: `sym_a`, `sym_b` (see --verbose for details)"。原因：

1. 对消费者，一个诊断信息已足以让他做出"pin ZMK / 升级模块 / 自担风险"的决策。
2. 多符号 banner 容易拉长到 100+ 行，被 CMake 的分页截断反而不易读。
3. 维护者侧的 `--verbose` 模式输出全量，供手工复盘。

## 场景派生 banner（spec US1 Scenario 1 - 通过）

成功路径的输出是**一行 info**，不是 banner：

```text
-- [zmk-keybeacon {MODULE_VERSION}] ZMK revision check: {CURRENT_SHA} ∈ [known-good: {LOWER}..{UPPER_OR_HEAD}) ✓
```

- 走 `message(STATUS ...)`，被 CMake 以 `-- ` 前缀渲染。
- 包含 `✓` 字符（UTF-8），因为所有现代终端和 GH Actions 都支持。
- 永不换行、不加框——避免正常路径视觉噪音。

## 场景派生 banner（spec US1 Scenario 3 - escape hatch 开启）

```text
-- [zmk-keybeacon {MODULE_VERSION}] ZMK revision check: {CURRENT_SHA}
   (would have failed on symbol {SYMBOL_NAME}, continuing because
    {ESCAPE_HATCH_KCONFIG}=y — build and runtime at your own risk)
```

- 走 `message(WARNING ...)`，CMake 高亮为 "CMake Warning:"。
- 不渲染 "How to fix" 段落（用户已经做了选择）。
- 必含"would have failed on symbol X"字样——便于日后追查哪些符号被绕过。

## 失败 banner 的字节级稳定性

CI 的 banner-regression 测试（`scripts/tests/test_banner_render.py`）用 **fixture ZMK tree** 固定输入，断言 banner 输出的字节序列与 `tests/fixtures/expected_banner_v1.1.4.txt` 完全一致。好处：

- 任何对 banner 的无意修改（例如重排段落、改措辞）在 PR 阶段就被卡住。
- 有意修改必须更新 expected fixture，review 时 diff 一目了然。
- 未来翻译中文镜像时，`expected_banner_zh.txt` 做同样 pin。

## 边界条件

| 场景 | 预期行为 |
|---|---|
| `${ZMK_ROOT}` 不存在 | 退出码 `3`，banner 换成 "ZMK source tree not found at X; is `west update` done?" |
| 多个符号失败 | 首个详细 + 其余紧凑列表（上述） |
| header 文件存在但符号被 `#ifdef OUT_OF_SCOPE` 包起来 | 探测器用 regex 不懂 `#ifdef`，会误判为"符号存在" → **可接受的误报**。缓解：fallback 列表 + CI 日度 build 作为兜底。 |
| 符号在 `.c` 中以 `static inline` 定义而非 `.h` | 探测器 miss → fail-fast。缓解：`compatibility.yaml` 允许 `header` 字段支持 `.c` 后缀（但语义上少见，不推荐）。 |
| 用户传了 `--lang zh` 且 banner 翻译表不完整 | 回退英文，stderr 多一行 `info: zh banner is incomplete, falling back to en`。 |

## 不在本契约内（显式排除）

- 具体字段的中文翻译：留给未来独立的 i18n 契约。
- CMake 侧的 `message(FATAL_ERROR)` vs `error_mode` 切换逻辑：实现细节，在 `cmake/zmk_compat.cmake` 内部完成。
- 其他探测器（如未来可能加入的 Zephyr version 探测、Kconfig 冲突探测）的 banner 格式：不复用本契约，各自独立。
