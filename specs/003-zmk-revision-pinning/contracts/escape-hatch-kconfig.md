# Contract: Escape Hatch Kconfig

**Phase**: 1 · **Status**: Normative · **Owner**: zmk-keybeacon maintainer · **Last updated**: 2026-10-12

本契约规定 Kconfig 符号 `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK` 的名称、默认值、作用域、行为切换方式。该符号是 spec [US1 Scenario 3](../spec.md) 的"自担风险逃生门"，由 research D8 的 Decision 固化。

## 符号规范

| 字段 | 值 |
|---|---|
| **名称** | `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK` |
| **类型** | `bool` |
| **默认值** | `n` |
| **可见性** | 用户 `.conf` / shield conf / `prj.conf` 均可配置 |
| **Kconfig 位置** | `../zmk-keybeacon/Kconfig.keybeacon`（现有唯一 Kconfig 文件，由 `zephyr/module.yml:build.kconfig` 声明为入口），`depends on ZMK_KEYBEACON`，与现有 `ZMK_KEYBEACON_CONNECTIVITY`、`ZMK_KEYBEACON_BATTERY` 平级 |
| **引入 tag** | `v1.1.4` |
| **移除**（如果有）| MUST 配 MAJOR 跃迁（见 [data-model.md](../data-model.md) 的演化规则） |

## Kconfig 代码片段

```kconfig
# Kconfig.keybeacon（../zmk-keybeacon/Kconfig.keybeacon，节选）
# 保留现有扁平 config 结构，不引入 menuconfig 包装（遵循当前模块惯例）。

config ZMK_KEYBEACON
    bool "KeyBeacon: expose keyboard status (layer+mods) over a custom GATT characteristic"
    depends on ZMK_BLE
    default n

config ZMK_KEYBEACON_CONNECTIVITY
    bool "KeyBeacon 1.1: expose Connectivity characteristic (AA440AA2-…)"
    depends on ZMK_KEYBEACON
    default y

config ZMK_KEYBEACON_BATTERY
    bool "KeyBeacon 1.1: expose Battery characteristic (AA440AA3-…)"
    depends on ZMK_KEYBEACON
    default y

# ⬇ v1.1.4 新增（本契约）
config ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK
    bool "Allow building against an incompatible ZMK revision (ADVANCED)"
    depends on ZMK_KEYBEACON
    default n
    help
      When enabled, zmk-keybeacon's build-time ZMK revision compatibility
      check (see cmake/zmk_compat.cmake and compatibility.yaml) will emit
      a WARNING instead of a FATAL_ERROR when the installed ZMK revision
      lacks a required internal symbol.

      You almost certainly do NOT want this. The build will continue past
      the configure stage, but will likely fail at C compile time with
      "undefined reference" errors, and the runtime behaviour of the
      KeyBeacon protocol service becomes undefined.

      Enable this only as an emergency bypass while the maintainer
      prepares a patched release. See:
        <release-notes-url>/compatibility-troubleshooting

      Default: n  (fail-fast on incompatible ZMK revisions — recommended)
```

**要点**：
- `depends on ZMK_KEYBEACON`：与现有 `_CONNECTIVITY` / `_BATTERY` 对齐；用户关闭 ZMK_KEYBEACON 时本符号也不可见。
- `bool`：无 string / tristate / hex——用户要么开要么不开，不接受"部分绕过"。
- help 文本显式含 "ADVANCED"、"almost certainly do NOT want this"、"undefined behaviour"——UX 层面劝退。

## 消费者使用方式

在用户的 `config/<shield>.conf`（例如 `totem_left.conf`）里加一行：

```
CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y
```

**构建副作用**：
1. `cmake/zmk_compat.cmake` 读到 `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y`，把探测失败的 `message(FATAL_ERROR ...)` 降级为 `message(WARNING ...)`。
2. 构建继续，进入 C 编译阶段；若 ZMK 侧真的缺符号，linker/compiler 会抛标准错（undefined reference 等），但那是消费者自己选的后果。
3. Banner 内容按 [fail-fast-banner.md](./fail-fast-banner.md) 的 "escape hatch 开启"场景派生——仍含"would have failed on symbol X"审计痕迹。

## 行为切换真值表

| `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK` | 符号探测结果 | 构建行为 |
|---|---|---|
| `n`（默认） | 全部通过 | configure 成功，`message(STATUS "...  ✓")` |
| `n` | 任一失败 | configure 终止，`message(FATAL_ERROR "...banner...")`，退出码 2 |
| `y` | 全部通过 | configure 成功，无额外输出（与默认成功路径等同） |
| `y` | 任一失败 | configure 继续，`message(WARNING "...banner (降级)...")`，退出码 0 → 进入 C 编译 |
| 未定义 | 全部通过 | 等同 `n`（Kconfig 的 `default n`） |
| 未定义 | 任一失败 | 等同 `n` |

## 对 compatibility.yaml 的声明关系

`compatibility.yaml` 中：

```yaml
escape_hatch:
  kconfig: CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK
  default: n
```

**一致性要求**：
- `escape_hatch.kconfig` 的字符串 MUST 与实际 `../zmk-keybeacon/Kconfig.keybeacon` 中声明的符号名一致。`scripts/validate_compat.py` 的 L3 校验会 grep `Kconfig.keybeacon` 验证存在性。
- `escape_hatch.default` 的 `y/n` MUST 与 Kconfig 的 `default` 行一致。
- 若未来需要改名（例如 `ALLOW_INCOMPATIBLE_ZMK` → `BYPASS_COMPAT_CHECK`），MUST：
  1. 保留旧名作为 alias（在 Kconfig 用 `select` 转发），
  2. 同时更新 `compatibility.yaml` 的 `escape_hatch.kconfig`，
  3. CHANGELOG 显式声明别名并给出废弃时间表，
  4. 这是 MAJOR 跃迁。

## 对消费者 `.conf` 向后兼容的影响

- 消费者的 `.conf` 增加本符号 **不会**破坏任何现有 Kconfig 组合（因为 `default n` 不改旧语义）。
- 消费者的 `.conf` 从 v1.1.3 升到 v1.1.4 时，**无需添加本符号**；只有当他们选择"自担风险绕过"时才主动加。
- 如果消费者的 `.conf` 之前有 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n` 这种 workaround，升级到 v1.1.4 后：
  - 保留它：构建成功，但 CONNECTIVITY 功能继续缺失（与 v1.1.3 行为等价）。
  - 删掉它：构建成功，CONNECTIVITY 恢复 —— spec US3 的目标路径。
  - CI 侧也测两种配置吗？本契约建议：不测（避免矩阵爆炸）。upgrade-notes.md 显式提示用户删除。

## 边界条件

| 场景 | 预期行为 |
|---|---|
| 用户 `.conf` 同时写 `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y` 和 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n` | 两者独立生效：探测仍 warn，CONNECTIVITY 仍禁用；banner 中应额外提示"你同时启用了逃生门和子系统禁用，这两种 workaround 不互相依赖，考虑取消其中之一" |
| 用户在 `west build -- -DCONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y` 命令行传入 | 行为与 `.conf` 配置相同；Zephyr 的 Kconfig 覆盖优先级规则适用 |
| 用户在**没有**探测失败的情况下也开启了逃生门 | 构建成功，banner 不渲染（成功路径），逃生门事实上空转——可接受 |
| 用户在 ZMK 自身 `.conf` 开启本符号 | ZMK 不认识本符号（它属于本模块的 Kconfig scope），Kconfig 会报 unknown symbol warning——这是 Zephyr 的既有行为，不需要我们处理 |

## 实现层面与契约的分界

**本契约只规定**：
- 符号名、类型、默认值、help 文本的 **措辞核心**。

**本契约不规定**：
- `cmake/zmk_compat.cmake` 如何读取该 Kconfig 值的 CMake 代码细节（实现层）。
- banner 在降级为 warning 时的具体渲染（归 [fail-fast-banner.md](./fail-fast-banner.md)）。
- 该符号在 `Kconfig.keybeacon` 文件中的物理行号（归 code review）。

## 不在本契约内（显式排除）

- 其他未来可能加入的 Kconfig 开关（如 `CONFIG_ZMK_KEYBEACON_COMPAT_VERBOSE` 用于 banner 详细模式）：另立契约。
- Kconfig 的中文 help 文本：目前只提供英文（zmk-keybeacon 不在 Constitution Principle VI 的强制双语列表）。
- 从本符号到 CMake 变量的 pass-through 协议：实现细节，由 CMakeLists.txt + zephyr 的 Kconfig 处理标准完成。
