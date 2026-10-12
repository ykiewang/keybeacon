# Research: zmk-keybeacon 模块的 ZMK revision 版本契约

**Phase**: 0 (Outline & Research)
**Date**: 2026-10-12
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

本文件把 spec 中刻意留白的实现决策点逐一收敛，每个点以 **Decision / Rationale / Alternatives considered / Risk** 结构落地。所有 Decision 都会反过来被 `data-model.md`、`contracts/*` 和未来的 `tasks.md` 引用。

---

## D1. 兼容性声明文件的物理形态

**Decision**: 独立文件 `../zmk-keybeacon/compatibility.yaml`，作为 CMake / Python / CI / README-generator 共享的**单一真相源**。

**Rationale**:
- `module.yml` 的 schema 由 Zephyr/west 定义，自定义字段虽技术上可塞但没有 schema 保护，第三方工具（如 `west manifest --freeze`）可能忽略或告警。
- Kconfig 注释块是人读的，不是机器可解析的；一旦有多个消费端（CMake、CI、README 生成器），注释块必须每处同步，违背"单一真相源"。
- 独立 YAML：可用 pyyaml 一行解析、便于 git diff 审阅、Pre-commit hook 可做 schema 校验、未来扩字段（例如 `optional_symbols`、`deprecated_in`）无需改 Zephyr/Kconfig 结构。

**Alternatives considered**:
- `module.yml` 自定义字段 `x-zmk-compat:`：拒绝，理由上面已列。
- `Kconfig` 顶部注释：拒绝，不可机器消费。
- JSON 替代 YAML：拒绝，YAML 对注释、多行 scalar、显式类型更友好；且 Zephyr/west 生态里 YAML 更常见（`west.yml` / `module.yml` 本就是 YAML）。
- TOML：拒绝，Zephyr 生态几乎无先例。

**Risk**: `compatibility.yaml` 可能被未来 ZMK 社区的其他模块作者模仿；若模仿后又分叉，会形成多种方言。缓解：Decision 固定文件名 + schema，并在 README 里鼓励社区复用。

---

## D2. ZMK API 可用性的探测方式

**Decision**: **头文件符号 grep**（正则匹配 `\b<symbol>\s*\(` 在 `${ZMK_ROOT}/app/include/<header>` 中），不比对 commit sha、不尝试编译 probe。

**Rationale**:
- 消费者可能 pin `zmk: main`（revision 每日漂移），sha 比对无意义——会出现"sha 不在白名单但符号实际存在"的假阳性。
- 尝试编译 probe（例如 CMake `try_compile` 一个最小 `.c` 调用目标符号）：代价 2–5 秒 × N 个符号，严重拖慢 configure；且 Zephyr 的交叉编译链 bringup 本身在 configure 阶段尚未就绪。
- Grep 头文件：
  - ZMK 的公共 API 都在 `app/include/zmk/*.h` 声明；
  - 代价 < 10ms 每个符号；
  - 支持 `fallback` 列表直接吃上游重命名（`required_symbols[i].fallback`）；
  - 失败时能精确报出"哪个符号在哪个头里找不到"，诊断信息质量远高于 undef-symbol 的 linker 错。

**Alternatives considered**:
- Commit sha 范围 `known_good.lower..upper`：**保留为诊断信息字段**，但不作为硬 gate（见 D1 的 `compatibility.yaml` schema）。决策理由：sha 范围是给用户看的"推荐 pin 到这里"的指引，不是构建成败的真相源。
- `try_compile`：拒绝（上面已论证）。
- 运行时反射：Zephyr 嵌入式环境无动态反射能力，根本不可行。
- 解析 ZMK 的 `module.yml` version：ZMK 自身的 `module.yml` 不声明 API 版本，纯占位。

**Risk**:
- 若 ZMK 把符号从 `.h` 挪到 `.c`（inline → non-inline，或反之），grep 失败但符号实际存在。缓解：`compatibility.yaml` 的 `required_symbols[i].header` 允许声明多个候选 header，并在 CI 探测时报告"在哪个 header 命中"便于日后调整。
- 若 ZMK 把 header 路径改了（如 `zmk/endpoints.h` → `zmk/connectivity/endpoints.h`）：探测报 "header missing"，fail-fast 时的建议动作中新增一行 "check if the header has been moved"。

---

## D3. 探测器实现语言

**Decision**: **Python 3**（`scripts/check_zmk_compat.py`），从 CMake 通过 `execute_process` 调用。

**Rationale**:
- Zephyr 构建系统本身强依赖 Python 3（`west`、`zephyr/scripts/*.py`），消费者机器上必有，零新增依赖。
- 相比纯 CMake 的 `file(READ)` + `string(REGEX MATCH)` + 多层 `if/endif`，Python 的 YAML 解析、正则、字符串格式化（banner 渲染）、异常处理都是母语级别，可读性与可测性 >>  CMake 脚本。
- Python 代码可直接用 pytest 做单测，CMake 脚本的单测必须跑真实 CMake 工程，CI 成本高。

**Alternatives considered**:
- 纯 CMake：拒绝，可读性差、测试难。
- Shell + awk：拒绝，Windows 消费者（WSL 之外）不可用。
- C 小工具编译后调用：拒绝，configure 阶段还没交叉编译链；用 host-cc 又引入新的构建步骤。
- 内嵌到 west extension：拒绝，west extension 的入口是 `west build` 之前，无法干预 CMake 内部。

**Risk**: Python 版本漂移（3.8 vs 3.11）。缓解：脚本只用 stdlib + `pyyaml`，`pyyaml` 已是 Zephyr `scripts/requirements.txt` 的间接依赖。显式声明 `>=3.8`，与 Zephyr main 对齐。

---

## D4. CI 的通知渠道

**Decision**: **三位一体**——(a) README CI badge（永久可见）+ (b) 日度定时失败时自动创建 GitHub Issue（主动通知维护者）+ (c) 对 PR 的 required-check 门禁（阻止把 compat 退化合并进来）。不单独加 webhook / Discord / Slack 集成。

**Rationale**:
- Badge：成本 0（GitHub Actions 自带），对消费者和潜在用户都是"这个模块活不活"的最低可见度。
- Auto issue：相比 webhook 到外部服务，GitHub issue 原生去重（见 spec US2 的 scenario 1 伪代码的 `listForRepo({state:'open', labels:'compat-break'})`），且 issue 带 run URL 便于直接点进调查。
- Required check：避免有人在 PR 里改坏 compat 探测本身却合进了 main——这是 CI 的本职工作。

**Alternatives considered**:
- 仅 badge：拒绝。被动，可能变红一周都没人看到。
- Webhook 到 Discord/Slack：拒绝。模块仓目前没有运营化的频道；要加也应该是维护者在仓外自建 "subscribe to issues with label compat-break"，不入 workflow。
- 邮件通知：GitHub 的 issue watch 自动触发，无需自定义；放弃显式集成。

**Risk**: 日度 cron 的 CI 费用（GitHub Actions 公共仓免费、私仓按分钟计费）。缓解：`compatibility.yaml` 若引入 `ci.schedule` 可配置字段，维护者可按需从日度→周度，不改 workflow 文件。

---

## D5. v1.1.4 是否拆成两个 tag（代码修复 vs 契约机制）

**Decision**: **单 tag `v1.1.4` 同时承担两件事**——(a) `keybeacon.c:243` 的 `#ifdef` forward-compat 修复 002 的 `zmk_endpoints_selected` 问题（唯一调用点）；(b) 本 feature 的全部契约机制（`compatibility.yaml` + `cmake/zmk_compat.cmake` + CI + README）。

**Rationale**:
- 若先发 "v1.1.4 = 只有契约机制、代码仍调 `zmk_endpoints_selected`"，则 v1.1.4 本身在最新 ZMK main（≥ `6e7e0de2`）上会被自己的契约 fail-fast 挡住——配 ZMK main 的用户升级到 v1.1.4 后仍然编不过，只是错误信息从 cryptic 变成了 banner。这不解决 002 遗留问题，还浪费一个 tag。
- 若先发 "v1.1.4 = 只有代码修复、仍无契约"，就是 002 的 workaround 永久化，与本 spec 的 US3 直接冲突。
- 一起发：契约在该 tag 首次生效时就能保护代码修复本身（`compatibility.yaml` 声明新 API `zmk_endpoint_get_selected` 作为 `zmk_endpoints_selected` 的 fallback、代码 `#ifdef` 配套开关），形成闭环。

**Alternatives considered**:
- 两个 tag 分发（v1.1.4 契约 + v1.1.5 代码修复）：被上面的反例否决。
- 大版本号跳到 v1.2.0：拒绝，对消费者是 MINOR 信号，但本 release 对消费者无新 wire 特性、无新 Kconfig 选项（escape hatch 默认 n = 旧行为），应 semver PATCH。CHANGELOG 显式写明"patch per semver: no wire change, no new default behaviour"。
- 维持 v1.1.3 并出 hotfix 分支：拒绝，v1.1.3 已发不改。

**Risk**: 单 tag 内容增大，review 难度上升。缓解：实现分三个 PR（compat-infra / code-forward-compat / docs-and-ci），顺序合入 main 后集中打 tag。

---

## D6. 代码路径的渐进 forward-compat 策略

**Decision**: **CMake 探测阶段派生编译宏** + **C 代码 `#if defined(ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT)` 分叉**。宏由 `check_zmk_compat.py` 根据探测结果输出到 CMake，再通过 `target_compile_definitions` 注入。

**具体落点**: `../zmk-keybeacon/keybeacon.c:243` 是**唯一**需要分叉的点：

```c
/* 当前（v1.1.3）：配旧 ZMK (<6e7e0de2) 过、配新 ZMK (≥6e7e0de2) 挂 */
struct zmk_endpoint_instance ep = zmk_endpoints_selected();

/* v1.1.4 目标：探测器根据 app/include/zmk/endpoints.h 里哪个符号存在，emit 对应宏 */
#if defined(ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT)
    struct zmk_endpoint_instance ep = zmk_endpoints_selected();
#else
    struct zmk_endpoint_instance ep = zmk_endpoint_get_selected();
#endif
```

**Rationale**:
- `#ifdef` 是 Zephyr/C 生态最常见的 forward-compat 手法，review 友好、调试符号可见、无运行时开销。
- 探测结果与宏定义同一来源（`compatibility.yaml` 的 `required_symbols[i].fallback` 哪一项命中）——避免宏在 C 里手动维护与 Python 探测器脱钩。
- 新/旧 API 返回类型一致（`struct zmk_endpoint_instance`，commit `860e53b3` 2024-03-27 由 `enum` 升级为 `struct` 后保持稳定至今），因此调用点下游代码（`ep.transport` 的 switch）两条分支一致，`#ifdef` 仅封装调用名称本身，噪音最小。
- 单元测试侧：`check_zmk_compat.py` 的测试断言"fake tree X 应派生宏集合 Y"，与 C 代码 `#ifdef` 分支一一对应。

**Alternatives considered**:
- 运行时函数指针解析：Zephyr/嵌入式无 dlsym，不可行。
- 内联函数 wrapper + 弱符号：Zephyr 的链接脚本对弱符号支持有限，且维护者认知负担高于 `#ifdef`。
- 用 `generated_header.h`（Python 生成的 C 头文件）替代 CMake 宏：拒绝，多一跳生成步骤，`add_compile_definitions` 已足够干净。
- 直接 drop 旧 API 支持、强制 ZMK ≥ `6e7e0de2`：拒绝，模块应比上游至少 pin 一个 LTS 回退点；且 `compatibility.yaml` 的 `fallback` 机制本身就是本 feature 的核心价值，不能跳过示范。

**Risk**: 宏爆炸（每新增一个 API 漂移点 += 一个宏）。缓解：当宏数量超过 5 时，考虑统一前缀 `ZMK_KEYBEACON_API_V{N}_*` 并在 header 里一次性收口。

---

## D7. CI 矩阵的覆盖范围

**Decision**: 初始矩阵 **{`main`, `zmk@4dd95d7` (renamed-era 冻结 pin), `zmk@e844eca2` (legacy-era 冻结 pin)} × {`xiao_ble + totem_left`}** = 3 组，`fail-fast: false`，MCU 板子 `xiao_ble` 与用户现网 CI (`ykiewang/zmk-config-totem`) 完全一致。

**Rationale**:
- `main` 变红是预警（上游 API 继续漂移、新 breaking change 到来）。
- `4dd95d7` 是我们在复盘时实证的 renamed-era commit（CI 真实日志证据，参考 spec Clarifications）；pin 住它作为"新 API 路径"的冻结回归点，防止我们改坏新路径。
- `e844eca2` 是本仓附近本地 clone 的 HEAD、legacy-era 代表 commit；pin 住它作为"旧 API 路径"（`#ifdef` 的 `ZMK_KEYBEACON_HAS_LEGACY_ENDPOINT` 分支）的冻结回归点，防止我们改坏旧路径。
- 两条冻结 pin 分别覆盖 `#ifdef` 两个分支，是本 feature **自证**的最小矩阵。
- `totem_left`（而非 `corne_left`）：用户的 002 feature 实际 CI 跑的是 `xiao_ble + totem_left` + `xiao_ble + totem_right`（见 Clarifications 的 run 38043117244），形成端到端的实证闭环；`corne_left` 作为社区事实标准，可以在 v1.1.5 作为扩张组加入。
- `fail-fast: false`：防止 `main`-build 快速 fail 导致两条 stable 组被取消，掩盖"我们改坏了"的信号。

**Alternatives considered**:
- 单一 ZMK ref：拒绝，无法 pin 住两条分支。
- 两条 ref（仅 `main` + legacy）：拒绝，renamed-era 冻结 pin 一旦漂移会立刻看不到 `main` 变红是因为"又有新 breaking"还是"renamed 分支的 API 又变了"。
- 增加 `corne_left`：延后到 v1.1.5。
- 加入"escape hatch 开启"测试：延后到 v1.1.5——先验证主路径稳定。

**Risk**:
- `4dd95d7` 实际是用户 CI run 当日的瞬时 HEAD，不是 ZMK 官方 release tag。缓解：在 `compatibility.yaml` 的注释里显式标注"this pin is a snapshot for regression, replace with first ZMK release containing commit 6e7e0de2 when available"；并在 CHANGELOG v1.1.4 条目里引用这个决策。
- docker image 偶发失败导致 issue 噪音。缓解：workflow 里加 `jobs.build.strategy.max-parallel: 2` + GitHub 自带的 retry on-fail（手动触发）。

---

## D8. Escape Hatch Kconfig 的命名与行为

**Decision**: Kconfig 符号 `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK`，默认 `n`。开启后：探测仍跑、仍输出 banner，但降级为 `message(WARNING ...)` 而非 `FATAL_ERROR`，构建继续直到 C 编译期自然失败。

**Rationale**:
- 命名显式带 `ZMK_KEYBEACON_` 前缀，避免与 ZMK/Zephyr 自身 Kconfig 冲突。
- `ALLOW_INCOMPATIBLE_ZMK` 比 `SKIP_COMPAT_CHECK` 更能传达"你在放弃一个保护"的语义。
- 默认 `n` 符合 Principle IV（Observable Degradation Over Guessing）：不启用时就是"宁可停下"的保护模式。
- 开启后仍跑探测、仍 warning：留下日志痕迹，便于用户 / 维护者事后追溯"用户是哪一天开始绕过的"。

**Alternatives considered**:
- Env var `ZMK_KEYBEACON_ALLOW_INCOMPATIBLE=1`：拒绝，Zephyr 构建的标准配置渠道是 Kconfig / `-D` CMake arg；env var 在 CI、west build 多层包装下易丢。
- CMake cache var `-DZMK_KEYBEACON_ALLOW_INCOMPATIBLE=ON`：拒绝，消费者的日常配置文件是 `.conf`（Kconfig），用 CMake arg 不符合习惯。
- 直接删掉 escape hatch：拒绝，紧急情况（上游刚挂、维护者没来得及发 patch）必须有逃生门，否则用户会去 fork 模块绕开——比有逃生门更坏。

**Risk**: 用户开启 escape hatch 后忘记关闭，长期在不兼容环境运行。缓解：README 的 Troubleshooting 章节强调"打开 escape hatch 后，升级模块时务必重新测一次关闭的默认路径"。

---

## D9. Compatibility 表的生成策略

**Decision**: 发 tag 前运行 `scripts/update-readme-table.py` 自动根据 git tag 历史 + 每个 tag 对应的 `compatibility.yaml` 快照重新生成 README 的 `<!-- COMPAT:BEGIN -->..<!-- COMPAT:END -->` 块。手动修改该块的改动在 pre-commit hook 中被拒绝。

**Rationale**:
- 杜绝"README 文案与代码漂移"——这是 spec SC-005 的目标（README 兼容性声明必须有 CI 佐证）。
- `git for-each-ref --sort=creatordate 'refs/tags/v*'` + `git show <tag>:compatibility.yaml` 已足够。
- 生成器是构建期工具，不随 release 分发，消费者无感知。

**Alternatives considered**:
- 手写 README：拒绝（易漂移）。
- CI 定期自动生成并 push PR：拒绝（引入写权限 token，复杂度不值）。
- 用 README fragment 文件 + Jinja2：杀鸡用牛刀。

**Risk**: 维护者发 tag 前忘记跑脚本。缓解：`make release` target 把生成器作为前置依赖；CHANGELOG 增量条目也顺便由该脚本校验（可选）。

---

## D10. 本仓 (`keybeacon`) 的职责边界

**Decision**: 本仓**不托管**任何实现代码，只贡献：
1. `specs/003-zmk-revision-pinning/`（spec/plan/research/artifacts）
2. `specs/002-zmk-keybeacon-kbp11/upgrade-notes.md`（新增，双语）
3. 顶层 README.md 的 Roadmap 表可选加一行 `KBP 1.1 → v1.1.4 patch released (compat contract)`

**Rationale**:
- 实现落点是独立模块仓 `../zmk-keybeacon/`，模块仓已有 CHANGELOG / README / CI，本仓不应侵入。
- 本仓 Constitution（Principle V）要求 spec-first；本 feature 的 spec/plan 工件理应留在本仓，便于溯源 002 → 003 的因果链。
- 002 的 upgrade-notes 必须在本仓——因为 002 的用户是本仓文档的读者。

**Alternatives considered**:
- 把 spec 挪到 `../zmk-keybeacon/specs/`：拒绝，模块仓未部署 Spec Kit，且 spec 的触发原因（002 遗留的 `.conf` workaround）就在本仓。
- 复制 spec 到两处：拒绝，违反单一真相源。

**Risk**: 读 `../zmk-keybeacon/` 的新贡献者看不到 spec 来源。缓解：模块仓 `CHANGELOG.md` 的 v1.1.4 条目显式 link 到 `https://github.com/<org>/keybeacon/blob/main/specs/003-zmk-revision-pinning/spec.md`。

---

## 遗留的真·未知项

扫描上述 10 个决策后，**没有**残留 `NEEDS CLARIFICATION`。所有 Phase 0 待定项均已收敛，可以进入 Phase 1 的 Design & Contracts。
