# Quickstart: Validate the ZMK Revision Compatibility Contract

**Phase**: 1 (Design & Contracts) · **Date**: 2026-10-12 · **Spec**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md)

本文件把 spec 中三个 user story 的 Independent Test 转化为**可逐步跑通**的验证手册。所有命令假设你在本仓根目录 `/Users/wangyuting19/kbd/keybeacon/keybeacon/`；凡涉及模块仓的命令都显式标出路径 `../zmk-keybeacon/`。

> ⚠️ 本 feature 的实现代码落在 `../zmk-keybeacon/`。在 `/speckit-tasks` → `/speckit-implement` 阶段完成之前，下面的 "Expected" 结果都是契约期望，不是当前仓状态。

## 前置条件

- `../zmk-keybeacon/` 已 clone 到与 keybeacon 同级目录，且已切到 feature 分支 `feat/compat-contract-v1.1.4`
- 本机已装 west + Zephyr SDK（能跑 `west build`）
- 本机已装 Python 3.8+，`pip install pyyaml jsonschema pytest` 可用
- 对可选 CI 验证（US2）：GitHub repo 具备 Actions 的 write 权限（通常默认即可）

## US1 Scenario 1 — 兼容 ZMK revision 下，构建通过且 host 看到 CONNECTIVITY 卡片

**对应 FR**: FR-001, FR-002, FR-008
**对应 SC**: SC-001, SC-004

### Given

```bash
# 1. 消费者的 zmk-config 已把 zmk-keybeacon pin 到 v1.1.4，zmk pin 到 known-good
cat ../zmk-config-totem/config/west.yml | grep -A1 'name: zmk' 
# 期望看到:
#   name: zmk,           revision: a3f7d21
#   name: zmk-keybeacon, revision: v1.1.4

# 2. 用户 totem_left.conf 已删除历史 workaround（如存在）
grep -c "ZMK_KEYBEACON_CHAR" ../zmk-config-totem/config/totem_left.conf
# 期望输出: 0
```

### When

```bash
cd ../zmk-config-totem
west update
west build -s zmk/app -b xiao_ble -- -DSHIELD=totem_left \
    -DZMK_EXTRA_MODULES=$PWD/../zmk-keybeacon
```

### Then（契约期望）

- `west build` 退出码 `0`
- stdout 包含一行：
  ```
  -- [zmk-keybeacon 1.1.4] ZMK revision check: a3f7d21 ∈ [known-good: d33f7ca..a3f7d21) ✓
  ```
- 产物 `build/zephyr/zmk.uf2` 存在
- 烧录后用 macOS KeyBeacon app 连接，`Connectivity & Battery` 卡片在 ≤ 1s 内渲染出 4 行（host-connection / profile / split halves / output endpoint）
- 在本仓运行 `python3 conformance/conformance_tool.py --timeout 15` 返回退出码 `0`，`characteristics.AA440AA2.present == true`

### Pass / Fail 判据

| 子项 | Pass | Fail |
|---|---|---|
| `west build` 退出码 | 0 | 非 0 |
| `✓` 行可见 | 有 | 无 |
| CONNECTIVITY 卡片渲染 | 4 行齐全 | 任一字段空 / 缺卡片 |
| conformance tool | C7/C8 PASS | 任一 FAIL |

---

## US1 Scenario 2 — 不兼容 ZMK revision 下，CMake 阶段 fail-fast 并给出 banner

**对应 FR**: FR-002, FR-003
**对应 SC**: SC-003
**对应 Contract**: [fail-fast-banner.md](./contracts/fail-fast-banner.md)

### Given

```bash
# 1. zmk-keybeacon 仍 pin 到 v1.1.4
# 2. zmk 刚被推到 ZMK main-HEAD，且该 commit 已把 zmk_endpoints_selected 重命名/删除
cd ../zmk && git log -1 --format=%h   # 记录当前 sha，用作 banner 校对
cd ../zmk-config-totem
# 不动用户 conf，不加 escape hatch
grep "CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK" config/totem_left.conf
# 期望输出: 空
```

### When

```bash
cd ../zmk-config-totem
west build -s zmk/app -b xiao_ble -- -DSHIELD=totem_left \
    -DZMK_EXTRA_MODULES=$PWD/../zmk-keybeacon \
    2>&1 | tee build.log
```

### Then（契约期望）

- `west build` 退出码 **非 0**（具体为 CMake 的 FATAL_ERROR 行为，一般 1 或 2）
- `build.log` 包含完整 banner（参照 [fail-fast-banner.md](./contracts/fail-fast-banner.md) 的 "Banner 骨架" 节）：
  - 顶部框线 "zmk-keybeacon 1.1.4 is INCOMPATIBLE..."
  - "Missing symbol: zmk_endpoints_selected"
  - "Called from: keybeacon.c"
  - "─── How to fix ───" 段落含 **三条可执行建议**
  - "─── Also ───" 段落显式劝退"在 .conf 里逐个禁子系统"
- `build.log` **不** 包含 `undefined reference to 'zmk_endpoints_selected'` 等 C 编译/链接期错误（因为根本没进 C 编译阶段）
- banner 中 "Pin ZMK back to a known-good revision" 下的 revision 字符串与 `compatibility.yaml:zmk_known_good.upper`（当前为 `4dd95d7`）一致

### 自动化回归（给 CI 的）

```bash
cd ../zmk-keybeacon
pytest scripts/tests/test_banner_render.py -v
# 期望:
#   test_banner_matches_fixture_renamed PASSED  (fixture: zmk-renamed)
#   test_banner_matches_fixture_missing PASSED  (fixture: zmk-missing)
```

### Pass / Fail 判据

| 子项 | Pass | Fail |
|---|---|---|
| configure 阶段终止 | 是 | 否（进了 C 编译） |
| banner 四段结构完整 | 齐 | 缺任一段 |
| 建议的 revision = `a3f7d21` | 一致 | 不一致 |
| `test_banner_render.py` | PASS | FAIL |

---

## US1 Scenario 3 — Escape Hatch 开启后，构建继续但留下审计痕迹

**对应 FR**: FR-004
**对应 Contract**: [escape-hatch-kconfig.md](./contracts/escape-hatch-kconfig.md)

### Given

```bash
# 延续 Scenario 2 的不兼容环境，但显式开启逃生门
echo 'CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y' >> ../zmk-config-totem/config/totem_left.conf
```

### When

```bash
cd ../zmk-config-totem
west build -p -s zmk/app -b xiao_ble -- -DSHIELD=totem_left \
    -DZMK_EXTRA_MODULES=$PWD/../zmk-keybeacon \
    2>&1 | tee build-escape.log
```

### Then（契约期望）

- CMake configure 阶段**通过**（退出码 0 从 CMake 角度看）
- `build-escape.log` 含 "CMake Warning" 而非 "CMake Error"
- warning 文本含 `would have failed on symbol zmk_endpoints_selected`
- warning 文本含 `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y — build and runtime at your own risk`
- 后续 C 编译阶段**可能**失败（本契约不保证继续通过），但失败发生在 C 层，不在契约层——用户已主动放弃契约保护

### Pass / Fail 判据

| 子项 | Pass | Fail |
|---|---|---|
| configure 阶段通过 | 是 | 否 |
| "CMake Warning" 出现 | 有 | 无 |
| 审计关键字 "would have failed on symbol" | 有 | 无 |

---

## US2 — 日度 CI 在 ZMK main breaking 后 24h 内变红 + 自动开 issue

**对应 FR**: FR-005, FR-006
**对应 SC**: SC-002
**对应 Contract**: [ci-workflow-contract.md](./contracts/ci-workflow-contract.md)

### Given

- `../zmk-keybeacon/.github/workflows/zmk-main-compat.yml` 已部署并通过首次 PR 的 `validate-manifest` + `build` 检查
- 该 repo 已创建 label `compat-break`（手动一次性操作：`gh label create compat-break --color d73a4a`）
- 维护者在 GitHub 账号上开启了对该 repo 的 issue watch（默认即开）

### When — 制造一次破坏性变更的 drill

```bash
# 1. 手动 workflow_dispatch 触发
cd ../zmk-keybeacon
gh workflow run zmk-main-compat.yml

# 2. 等待 ~5 min，查看结果
gh run list --workflow=zmk-main-compat.yml --limit 1
```

### Then（契约期望，分两种真实场景）

**场景 A — ZMK main 当前兼容**：
- 所有矩阵格 build 通过
- Run 状态 `success`
- README badge 保持绿
- 不开 issue

**场景 B — ZMK main 已 breaking（真实或 drill）**：
- 至少 `(main, *)` 的矩阵格 build 失败
- Run 状态 `failure`
- `gh issue list --label compat-break --state open` 返回 1 条新 issue
- Issue 正文含：
  - run URL（点进去直达失败日志）
  - "Likely cause: ZMK upstream renamed/removed a symbol..."
  - "Action items" checkbox 列表
- README badge 变红

### Drill 回归验证（可周期性运行）

```bash
# 构造一个 fake ZMK revision（通过 patch zmk/app/include/zmk/endpoints.h 移除符号）
# ... 具体 drill 方案在 /speckit-tasks 阶段落定 ...
# 然后触发 workflow_dispatch 并断言产出
```

### Pass / Fail 判据

| 子项 | Pass | Fail |
|---|---|---|
| 日度 cron 在当日 06:00 UTC 自动跑 | 有 run 记录 | 无 |
| 失败时开 issue | 1 条 open issue | 0 条或 >1 条（去重坏了） |
| 已有 open issue 时**不**新开 | 保持 1 条 | 开出重复 |

---

## US3 — 删除历史 workaround 后 CONNECTIVITY 恢复

**对应 FR**: FR-008, FR-009
**对应 SC**: SC-004

### Given

```bash
# 用户 totem_left.conf 中仍含 002 时期的 workaround
grep "CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n" ../zmk-config-totem/config/totem_left.conf
# 期望输出: 1 行
```

### When — 按 upgrade-notes 的指引删除 workaround

```bash
cd ../zmk-config-totem
# 按 ../keybeacon/specs/002-zmk-keybeacon-kbp11/upgrade-notes.md 清单删除:
#   - CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n
#   - 其他 CHAR_* workaround（如有）
sed -i.bak '/CONFIG_ZMK_KEYBEACON_CHAR_/d' config/totem_left.conf

west build -p -s zmk/app -b xiao_ble -- -DSHIELD=totem_left \
    -DZMK_EXTRA_MODULES=$PWD/../zmk-keybeacon
```

### Then（契约期望）

- 构建成功
- 烧录后 host 侧 Connectivity & Battery 卡片**出现**（Scenario 1 的 Then 的子集）
- `conformance_tool.py --json | jq '.characteristics["AA440AA2-..."].present'` 返回 `true`

### 对比验证（可选，用于 PR review）

```bash
# A: 保留 workaround 的 build
cp config/totem_left.conf.bak config/totem_left.conf
west build -p -s zmk/app -b xiao_ble -- -DSHIELD=totem_left \
    -DZMK_EXTRA_MODULES=$PWD/../zmk-keybeacon
# conformance_tool.py 得到 AA440AA2.present == false

# B: 删除 workaround 的 build（上面的 When）
# conformance_tool.py 得到 AA440AA2.present == true
```

### Pass / Fail 判据

| 子项 | Pass | Fail |
|---|---|---|
| 删 workaround 后仍构建成功 | 是 | 否（说明还有隐性依赖） |
| CONNECTIVITY 卡片渲染 | 有 | 无 |
| `AA440AA2.present` 翻转 | `false → true` | 无变化 |

---

## 契约自身的健康检查（给 reviewer）

在 review 本 feature 的 PR 时，手工跑：

```bash
cd ../zmk-keybeacon
# 1. YAML + schema + 语义校验
python3 scripts/validate_compat.py && echo "manifest OK"

# 2. Python 探测器单测
pytest scripts/tests/ -v

# 3. CMake 集成冒烟（三个 fixture ZMK tree 分别配 configure）
scripts/tests/smoke-cmake.sh
# 期望输出:
#   fixture zmk-known-good  → configure OK, status "✓" visible
#   fixture zmk-renamed     → configure fail-fast, banner visible
#   fixture zmk-missing     → configure fail-fast, "header missing" visible

# 4. README Compatibility 表与 git tags 一致性
python3 scripts/update-readme-table.py --check
# 期望: no changes needed (若有 diff 说明表漂移了)
```

全部通过才允许 merge。

---

## FR / SC / US 覆盖矩阵

| 场景 | 覆盖的 FR | 覆盖的 SC |
|---|---|---|
| US1 Scenario 1 | FR-001, FR-002, FR-008 | SC-001, SC-004 |
| US1 Scenario 2 | FR-002, FR-003 | SC-003 |
| US1 Scenario 3 | FR-004 | — |
| US2 | FR-005, FR-006 | SC-002 |
| US3 | FR-008, FR-009 | SC-004 |
| 自身健康检查 | FR-007, FR-010 | SC-005 |

**可见度**：spec 的全部 10 个 FR + 5 个 SC 都至少被一个 quickstart 场景或自身健康检查命中。
