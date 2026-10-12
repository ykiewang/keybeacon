# Feature Specification: zmk-keybeacon 模块的 ZMK revision 版本契约

**Feature Directory**: `specs/003-zmk-revision-pinning/`

**Target repository**: `../zmk-keybeacon/`（独立 Zephyr 模块仓库；本 spec 的改动落到该仓库而非 `keybeacon` 主仓）

**Created**: 2026-10-12

**Status**: Draft

## Clarifications

### Session 2026-10-12 — 事实复盘（证据链）

本次复盘回答一个关键问题："`v1.1.3` 在当前 ZMK main 上编译失败的真实根因是什么？" 之前对此有两次推理，第二次是错的；本节钉死事实链，供 `/speckit-plan` 阶段作为输入。

**决定性证据**：

1. **ZMK upstream 的重命名事件（真实发生）**：zmk commit `6e7e0de2 feat(endpoints): add "no endpoint" value (#3140)`，日期 `2026-02-12`，把 `zmk_endpoints_selected()` 重命名为 `zmk_endpoint_get_selected()`，同时引入 `ZMK_TRANSPORT_NONE` 枚举值。该 commit 存在于 `zmkfirmware/zmk` 的 main 分支。
2. **CI 实证**：`ykiewang/zmk-config-totem` 的 Actions run `38043117244` 中 `totem_left` 构建失败，日志行 319 `--- zmk: fetching, need revision main` → `HEAD is now at 4dd95d7`（在 `6e7e0de2` 之后）；日志行 882 编译器输出 `keybeacon.c:243:39: warning: implicit declaration of function 'zmk_endpoints_selected'; did you mean 'zmk_endpoint_get_selected'?` + 884 行 `error: invalid initializer`。编译器自己给出了后继符号名的提示。
3. **本地 ZMK clone 不足以作为真相**：本仓附近的 `/Users/wangyuting19/kbd/zmk` 当前 HEAD 为 `e844eca2`，detached @ `ykie/feat/pointers-move-scroll-keyball41`（用户自己 fork 的历史分支），**不是** `zmkfirmware/zmk` 的 main。因此只在本地 clone 的 HEAD 做 symbol grep 会看到 `zmk_endpoints_selected` 存在而误判"API 未重命名"。正确做法是 `git log --all -S '<后继符号>' -- app/include/zmk/endpoints.h` 做历史穿越。
4. **用户的 `fix/endpoint-get-selected` 分支方向正确**：commit `608a4d2` 把 `keybeacon.c:243` 从 `zmk_endpoints_selected()` 改为 `zmk_endpoint_get_selected()`，这是针对 ZMK ≥ `6e7e0de2` 的正确修复。配旧 ZMK 会反向失败。

**对本 spec 的影响**：

- Input 段（第 11 行）"ZMK main 已被重命名/替换"的描述**成立**。
- US2 Acceptance Scenario 1（原第 50 行）举例的 API 后继名字订正为 `zmk_endpoint_get_selected`（原稿误写为 `zmk_endpoint_instance_active`）。
- FR-002（第 83 行）符号探测清单订正：
  - 删除 `zmk_split_bt_peripherals_connected`——该符号在 ZMK main 不存在（keybeacon.c 实际使用的是模块内部维护的 `peripheral_slots[].connected` 状态表，并非 ZMK 公共 API）。
  - 增加 `zmk_ble_active_profile_is_open`、`zmk_ble_active_profile_is_connected`——这两个是 keybeacon.c 真实依赖的 ZMK 公共 API。
  - `zmk_endpoints_selected` 与 `zmk_endpoint_get_selected` 的探测关系从"任一缺失即 fail"调整为"任一命中即视为兼容"（因为重命名事件保证了永远只有其一存在，而消费者 v1.1.4 的代码需要同时能配旧 ZMK 和新 ZMK）。
- Assumptions 段（第 116 行）关于"`v1.1.4` 可以选择同时支持新旧 API via `#ifdef` 符号探测"的渐进路径**保留**——这正是本 feature 的核心技术形态。

**本次复盘的方法论教训**（供 `.specify/memory/` 备案）：

- 做"某 upstream API 是否重命名"的判断，必须以 `git log --all` 的历史穿越为准，不能以本地 clone 当前 HEAD 的 `grep` 为准。
- 本地 ZMK clone 可能 detached 在任何 fork 的任何分支上，HEAD 的 `grep` 结果只代表"在这个 revision 下该符号的状态"，不代表 upstream main 的最新状态。
- CI 构建日志是实证最高级别证据，优先于任何本地推理。

---

**Input**: User description: 发现 `specs/002-zmk-keybeacon-kbp11/plan.md` 把 `zmk-keybeacon` pin 到已发布的 `v1.1.3`，但 `v1.1.3` 的 CONNECTIVITY 路径调用了 `zmk_endpoints_selected()`，而该函数在当前 ZMK main 分支已被重命名/替换，导致 `v1.1.3` 配 ZMK main 根本编译不过。目前只能靠在 `totem_left.conf` 里手动禁用 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n`（或等价子选项）来绕过。这暴露了 zmk-keybeacon 作为外部模块缺少对 ZMK 内部 API 的版本契约——ZMK main 任意一次重命名都会让所有追踪 main 的消费者 `west update` 后静默编译失败。根治方式是在模块侧（`module.yml` + CI）锁定/测试已知兼容的 ZMK revision，而不是让每个用户在 conf 里逐个禁子系统。

**Related work (read-only context)**:

- 外部模块：`../zmk-keybeacon/`（CHANGELOG v1.1.3；下一个 tag v1.1.4）
- 问题现场：`specs/002-zmk-keybeacon-kbp11/plan.md`（pin v1.1.3 的决策记录）
- 示例配置：`../zmk-config-*/config/totem_left.conf`（临时 workaround 禁用 CONNECTIVITY 落点）
- 符号差异：`v1.1.3` 调用 `zmk_endpoints_selected()`；ZMK main 已重命名该 API（PR #2 跟进中但尚未合并发 tag）
- Zephyr 模块版本声明机制：`zephyr/module.yml`（`depends:` / `name:` / 自定义字段）、west manifest `revision:`

## User Scenarios & Testing *(mandatory)*

### User Story 1 — 消费者 `west update` 后不会静默编译失败 (Priority: P1)

一个按 `002-zmk-keybeacon-kbp11` 文档搭建键盘的用户，`west.yml` 里把 `zmk-keybeacon` pin 到 `v1.1.4`（下一个发布版），同时 `zmk` 可能 pin 到 main 或某个较新 commit。该用户执行 `west update && west build` 时，构建要么**成功**产出 KBP 1.1 固件，要么**在模块侧立刻报出可读错误**明确告知"当前 ZMK revision 与 zmk-keybeacon v1.1.4 不兼容，已知兼容范围为 X–Y，请 pin ZMK 到该范围内"，**绝不能**出现"编译失败在一行调用 `zmk_endpoints_selected()` 的 .c 文件里、报错是未声明符号、用户完全不知道这是上游 API 漂移"的局面。

**Why this priority**：这是外部模块对消费者最低限度的可用性承诺。无此机制，任何追踪 ZMK main 的用户在任意一次 `west update` 后都可能遭遇无声断裂，排查成本极高，且 workaround（conf 里逐个禁子系统）会悄悄降级功能，用户甚至不会发现自己丢了 CONNECTIVITY 卡片。

**Independent Test**：在一个 CI job（或本地脚本）里跑三组矩阵：(A) `zmk-keybeacon@v1.1.4 + zmk@<已知兼容 commit>`、(B) `zmk-keybeacon@v1.1.4 + zmk@<已知破坏性 commit，如 endpoints 重命名之后>`、(C) `zmk-keybeacon@v1.1.4 + zmk@main-HEAD`。矩阵 A 必须 build 通过；矩阵 B 必须在 CMake/Kconfig 阶段 fail-fast 并输出含"ZMK revision incompatible"字样的诊断信息（而非 C 编译期的未定义符号错）；矩阵 C 的结果作为日常可见度信号。整个过程不需要用户动 `.conf`。

**Acceptance Scenarios**:

1. **Given** 用户 `west.yml` 把 `zmk-keybeacon` 设为 `v1.1.4`、`zmk` 设为模块声明的"已知兼容 revision"之一，**When** 执行 `west build -b nice_nano_v2 -- -DSHIELD=totem_left`，**Then** 构建成功，不需要在 `totem_left.conf` 里加任何 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n`。
2. **Given** 用户把 `zmk` pin 到一个已知与 v1.1.4 不兼容的 commit（例如 endpoints 重命名之后、模块尚未适配），**When** 构建开始，**Then** 在 CMake 配置阶段（而非 C 编译阶段）输出清晰的中/英文错误：注明不兼容的 ZMK commit、模块声明的兼容范围、建议动作（降级 ZMK、升级模块、或开启 `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y` 自担风险）。
3. **Given** 模块仓库的 CI 定期（每日 or 每 PR）跑 ZMK main-HEAD 的 compat 矩阵，**When** ZMK main 新增 breaking change，**Then** CI 在 24 小时内在模块仓库开 issue 或红一次状态灯，维护者据此发 patch/新 tag，而不是等用户上报。
4. **Given** 用户阅读 `../zmk-keybeacon/README.md`，**When** 查看"兼容性"章节，**Then** 能看到当前 tag 对应的"已知兼容 ZMK revision 范围"显式列出（如：`zmk@d33f7ca..main 之间的 commit，不含 PR #XXXX 的重命名`），而不是"please use latest ZMK"这种模糊承诺。

---

### User Story 2 — 维护者感知上游漂移 (Priority: P2)

zmk-keybeacon 的维护者希望在 ZMK main 发生破坏性变更的当天就被动通知，而不是等用户在 GitHub Issues 里报"编译不过"。CI 每日跑一次 `zmk@main-HEAD + zmk-keybeacon@main` 的 smoke build，失败即发邮件/开 issue。

**Why this priority**：维护者侧的可观测性。消费者侧的 fail-fast 已经通过 US1 保底，US2 把感知前移到维护者，降低回归到达用户的平均时间。

**Independent Test**：GitHub Actions（或等价 CI）里有一个 `zmk-main-compat.yml` workflow，`schedule: cron '0 6 * * *'` 每日执行；手动触发也可用；成功/失败历史在 Actions 标签页可见。

**Acceptance Scenarios**:

1. **Given** CI 已配置好，**When** ZMK main 合并一个重命名 `zmk_endpoints_selected`→`zmk_endpoint_get_selected` 的 PR（真实事件：commit `6e7e0de2 feat(endpoints): add "no endpoint" value (#3140)`，2026-02-12），**Then** 当日的定时 CI 变红，workflow 产出的日志里含该重命名的符号与出错文件，GitHub 自动在模块仓库开一个 "compat failure: {commit-sha}" 的 issue（或触发 webhook 通知）。
2. **Given** CI 变红持续 >48 小时，**When** 维护者查看 README 的 CI badge，**Then** badge 显示红色且链接直达最近一次失败。

---

### User Story 3 — 废弃 `.conf` workaround，恢复默认开启 CONNECTIVITY (Priority: P2)

现在用户 `totem_left.conf` 里为了绕编译错而写的 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n` 等语句属于"治标"，一旦模块侧版本契约落地，这些禁用项必须可以安全移除并恢复默认 `=y`，CONNECTIVITY 卡片随之自动在 host 侧出现。

**Why this priority**：确保此 feature 真正解决了 002 遗留的用户体验债，而不是叠加一层新机制让旧 workaround 永久存在。

**Independent Test**：对比两份 `totem_left.conf`——一份含 workaround、一份已删除所有 `CONFIG_ZMK_KEYBEACON_CHAR_*=n` 行；两份均配 `zmk-keybeacon@v1.1.4 + zmk@<兼容 revision>` build 通过；运行 `conformance/conformance_tool.py --json` 后，无 workaround 版本的 `characteristics.AA440AA2.present == true`，workaround 版本则为 `false`（因被禁用）。

**Acceptance Scenarios**:

1. **Given** 用户按新模块文档清掉 `.conf` 中的 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n`，**When** 重新 build + flash，**Then** 固件开机后 host 侧 KBP 1.1 "Connectivity & Battery" 卡片在 ≤1s 内出现并显示四个字段。
2. **Given** 模块 README 的"升级到 v1.1.4"章节，**When** 用户阅读，**Then** 显式写明"从 v1.1.3 升级需删除 `.conf` 里的以下 workaround 行：…"。

---

### Edge Cases

- 用户 `west.yml` 的 `zmk` 用 **branch**（例如 `revision: main`）而非 pinned sha：此时每次 `west update` 都在变——模块是否仍能给出稳定判断？约定：模块侧用 Kconfig/CMake 探测关键符号（如 `zmk_endpoints_selected` 是否存在），而不是只对比 revision 字符串，从而覆盖 branch 浮动场景。
- 用户显式打开 `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK=y` 后仍失败：模块不负责保证能过，但构建日志里必须有一条"用户已放弃版本契约"的 warning 便于回溯。
- 维护者尚未来得及更新模块，但 ZMK main 已 breaking：US1 scenario 2 的 fail-fast 文案里必须给出"临时 pin ZMK 到 `<last-known-good sha>`"的具体命令行示例，而不是让用户自己翻 git log。
- 模块侧 CI 探测到 ZMK main breaking 后，是否自动发 patch？约定：**不**自动改代码，只开 issue + 变红 badge，由维护者人工评估。
- `west manifest --resolve` 导出的 lockfile 与模块声明的兼容范围冲突（例如企业用户有自己的 pin 策略）：模块只报 warning 不报 error，尊重上层 manifest 的最终权威。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 模块 MUST 在仓库根 `../zmk-keybeacon/` 的某个权威位置（例如 `module.yml` 自定义字段、`compatibility.yaml`、或 `Kconfig` 顶部注释块）**显式声明**当前 tag 已知兼容的 ZMK revision 范围（起点 commit sha + 终点 commit sha 或 "unbounded until proven otherwise"）。
- **FR-002**: 模块 CMake / Kconfig MUST 在配置阶段检测关键 ZMK 内部符号的存在性（最少包含：`zmk_endpoints_selected` **或**其重命名后继 `zmk_endpoint_get_selected`、`zmk_ble_active_profile_index`、`zmk_ble_active_profile_is_open`、`zmk_ble_active_profile_is_connected`），其中 `zmk_endpoints_selected`/`zmk_endpoint_get_selected` 必须至少命中其一（任一命中即视为兼容，不要求两者同时存在），其他符号任一缺失时 **fail-fast 终止配置**，不进入 C 编译阶段。
- **FR-003**: fail-fast 的错误信息 MUST 为人类可读、中英双语或至少英文清晰，内容包含：缺失符号名、模块当前 tag、已知兼容 ZMK revision 范围、建议动作（降级 ZMK / 升级模块 / 开启 escape hatch）。
- **FR-004**: 模块 MUST 提供一个 Kconfig escape hatch `CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK`，默认 `n`；用户显式 `=y` 后 fail-fast 降级为 warning，构建继续（后果自负）。
- **FR-005**: 模块仓库 MUST 提供一个 CI workflow，每日自动用 `zmk@main-HEAD` + `zmk-keybeacon@main` 执行至少一个代表性 shield（例如 `nice_nano_v2 + corne_left`）的 `west build`。
- **FR-006**: 当 FR-005 的 CI 失败时，仓库 MUST 自动产生可被维护者感知的信号（GitHub issue 自动创建、或 README CI badge 变红、或 webhook 通知任选其一）。
- **FR-007**: 模块 README MUST 新增 "Compatibility" 章节，列出当前最新 tag 对应的已知兼容 ZMK revision 范围，并在每次发 tag 时随 CHANGELOG 一同更新。
- **FR-008**: 新发 tag（即此 spec 要产生的 `v1.1.4`）MUST 从代码路径上修复 002 遗留的 `zmk_endpoints_selected()` 不兼容问题，使得消费者在搭配"已知兼容 ZMK revision"时无需任何 `.conf` workaround 即可开启 CONNECTIVITY。
- **FR-009**: 消费者升级到 `v1.1.4` 的升级指南 MUST 显式列出需要从 `.conf` 中删除的历史 workaround 行（最少涵盖 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n` 等本次解决的子选项）。
- **FR-010**: 模块 CI 的符号探测与运行时逻辑 MUST 使用同一处 "symbol compatibility matrix" 作为真相源（避免 Kconfig 探测与运行时调用的符号列表漂移）。

### Key Entities

- **Symbol Compatibility Matrix**：模块侧维护的一张表（文件形式待实现决定），记录"模块代码路径 → 它调用的 ZMK 内部符号 → 该符号在哪些 ZMK commit 范围内可用"。CMake 探测、运行时调用、CI 测试均从此表派生。
- **Compat CI Workflow**：定时 + PR 触发的 CI job，输入是 `(zmk-rev, zmk-keybeacon-rev)` 二元组，输出是 build pass/fail + 诊断信息。
- **Escape Hatch Kconfig**：`CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK`，用户主动放弃版本契约的开关。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**：按新文档搭建键盘的新用户，从 `west init` 到 `west build` 成功、host 侧看到 CONNECTIVITY 卡片，中间**无需**手动修改任何 `.conf` 禁用项。整个流程端到端耗时 ≤ 15 分钟（不含硬件烧录）。
- **SC-002**：当 ZMK main 发生一次破坏 zmk-keybeacon 构建的 breaking change 时，模块维护者在该 breaking change 合并后 ≤ 24 小时内收到自动化信号（issue / badge / webhook），而非依赖用户上报。
- **SC-003**：当用户的 ZMK revision 与模块当前 tag 不兼容时，100% 的失败案例在 CMake 配置阶段终止、给出含"ZMK revision incompatible"字样的诊断信息；0% 的失败案例以"未定义符号 / 未声明函数"等 C 编译期错误形式呈现给用户。
- **SC-004**：从 `v1.1.3` 升级到 `v1.1.4` 的 002 feature 用户，按升级指南操作后，`conformance/conformance_tool.py --json` 返回 `characteristics.AA440AA2.present == true`、`check_us1 / check_us2_split_link / check_us3_output_endpoint == PASS`。
- **SC-005**：模块 README "Compatibility" 章节的覆盖率：对 README 中声明的每一个"支持的 ZMK revision 范围"，均能在 CI 历史中找到至少一条 ≤ 30 天内的 green run 作为佐证。

## Assumptions

- 模块仓库 `../zmk-keybeacon/` 使用 GitHub Actions（或等价支持 cron / 定时触发的 CI 平台），且维护者有权限新建 workflow、创建 issue。
- 消费者端的 west manifest 对 `zmk` 和 `zmk-keybeacon` 的 pin 粒度足够细（支持 `revision: <sha>` 或 tag，而非仅支持 branch 名）——这是 ZMK 社区事实标准。
- ZMK 内部关键符号（如 `zmk_endpoints_selected` 的后继）在源码层面可通过文件存在性 / symbol grep 探测，无需运行时 reflection。
- "已知兼容 ZMK revision 范围" 可以用 commit sha 对 (lower, upper) 表示；upper 为空代表 "unbounded until next CI red"。
- 本 spec 不触及 ZMK 上游代码，仅在 `../zmk-keybeacon/` 模块仓内落地；对 `keybeacon` 主仓的改动仅限于 002 feature 的后续清理（如升级指南交叉引用）。
- `v1.1.4` 的实际代码修复（替换 `zmk_endpoints_selected` 调用）与版本契约机制同一个 tag 一起发布；若 ZMK main 的后继 API 尚未稳定，`v1.1.4` 可以选择"同时支持新旧 API via `#ifdef` 符号探测"的渐进路径。
- 关于兼容性声明文件的具体格式（放在 `module.yml` 自定义字段 vs 独立 `compatibility.yaml` vs Kconfig 注释）、CI 失败后的通知渠道（auto issue vs webhook vs 仅 badge）——这些实现细节留给 `/speckit-plan` 阶段决策，本 spec 不预设。
