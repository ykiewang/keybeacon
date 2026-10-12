# Contract: CI Workflow — `zmk-main-compat.yml`

**Phase**: 1 · **Status**: Normative · **Owner**: zmk-keybeacon maintainer · **Last updated**: 2026-10-12

本契约规定 `../zmk-keybeacon/.github/workflows/zmk-main-compat.yml` 的输入、输出、触发条件、失败处理。CI 的目标是 spec [US2](../spec.md)：**维护者在 ZMK main 发生破坏性变更的当天 24 小时内收到自动化信号**。

## 契约总览

| 契约项 | 要求 |
|---|---|
| **触发时机** | 三选一：daily cron（UTC 06:00）；每个 PR 修改契约相关路径时；手动 `workflow_dispatch` |
| **输入** | `compatibility.yaml` 的 `ci` 字段（matrix / schedule / on_failure） |
| **成功判据** | 矩阵全部 cell `west build` 退出码 = 0 |
| **失败通知** | 仅 cron 触发失败时自动开 issue（PR 失败走 PR check，不开 issue） |
| **幂等** | 已有 open issue 带 `compat-break` label 时不新开 |
| **artifact** | 失败时上传 build 日志（zephyr 的 `build.log` + CMake stderr），保留 30 天 |

## Workflow 结构（骨架）

```yaml
# .github/workflows/zmk-main-compat.yml
# ⚠️ 此文件由 scripts/regen_ci.py 从 compatibility.yaml 派生，请勿手改。

name: ZMK compat matrix

on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:
  pull_request:
    paths:
      - 'compatibility.yaml'
      - 'cmake/**'
      - 'src/**'
      - 'scripts/check_zmk_compat.py'
      - 'scripts/validate_compat.py'
      - '.github/workflows/zmk-main-compat.yml'

jobs:
  validate-manifest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - run: pip install pyyaml jsonschema
      - run: python scripts/validate_compat.py

  build:
    needs: validate-manifest
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        zmk_ref: [main, 4dd95d7, e844eca2]   # ⬅ 从 compatibility.yaml 派生（main + renamed-era pin + legacy-era pin）
        shield:  [totem_left]                # ⬅ 从 compatibility.yaml 派生（与用户现网 CI 对齐）
    steps:
      - uses: actions/checkout@v4
        with: { path: zmk-keybeacon }
      - uses: actions/checkout@v4
        with:
          repository: zmkfirmware/zmk
          ref: ${{ matrix.zmk_ref }}
          path: zmk
      - name: Resolve ZMK sha
        id: zmksha
        run: echo "sha=$(git -C zmk rev-parse HEAD)" >> $GITHUB_OUTPUT
      - uses: zmkfirmware/zmk-docker-action@v2
        with:
          board: xiao_ble
          shield: ${{ matrix.shield }}
          zephyr_version: '3.5'
          extra_cmake_args: >
            -DZMK_EXTRA_MODULES=${{ github.workspace }}/zmk-keybeacon
      - name: Upload build log on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: build-log-${{ matrix.zmk_ref }}-${{ matrix.shield }}
          path: |
            build/CMakeFiles/CMakeConfigureLog.yaml
            build/zephyr/.config
          retention-days: 30

  file-issue-on-main-break:
    needs: build
    if: failure() && github.event_name == 'schedule'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            const existing = await github.rest.issues.listForRepo({
              owner: context.repo.owner, repo: context.repo.repo,
              state: 'open', labels: 'compat-break'
            });
            if (existing.data.length > 0) {
              core.info(`Existing compat-break issue #${existing.data[0].number}, skip.`);
              return;
            }
            const run = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
            await github.rest.issues.create({
              owner: context.repo.owner, repo: context.repo.repo,
              title: `[compat] ZMK matrix failed on ${new Date().toISOString().slice(0,10)}`,
              body: [
                `Daily compat workflow failed.`, ``,
                `**Run:** ${run}`, ``,
                `**Likely cause:** ZMK upstream renamed/removed a symbol declared`,
                `in \`compatibility.yaml:required_symbols\`.`, ``,
                `**Action items:**`,
                `- [ ] Open the run above and identify the failing symbol`,
                `- [ ] Add it to the matching \`fallback\` list in compatibility.yaml`,
                `- [ ] If needed, update \`src/*.c\` with \`#ifdef\` forward-compat`,
                `- [ ] Bump \`known_good.upper\` once CI goes green again`,
                `- [ ] Prepare a patch release (vX.Y.Z+1)`,
              ].join('\n'),
              labels: ['compat-break'],
            });
```

## 契约字段

### 输入 1：触发条件

| 事件 | 允许触发 | 必跑的 job |
|---|---|---|
| `schedule`（cron） | ✅ | `validate-manifest` → `build` → `file-issue-on-main-break` |
| `pull_request`（paths match） | ✅ | `validate-manifest` → `build`（**不**跑 issue job） |
| `workflow_dispatch` | ✅ | 同 PR |
| `push` to main | ❌ | 不触发（避免 push 后 double-run） |

### 输入 2：矩阵

- 来源：`compatibility.yaml:ci.matrix.zmk_refs` × `compatibility.yaml:ci.matrix.shields`
- `fail-fast: false` MUST 显式写出（否则 `main` 失败会取消两个冻结 pin，掩盖"是上游漂移还是我们改坏了"的信号差异）
- 单元胞失败不中断其他单元胞

### 输入 3：ZMK 版本

- `uses: actions/checkout@v4` with `repository: zmkfirmware/zmk`：公共仓库，无需 token
- `ref: ${{ matrix.zmk_ref }}`：支持 branch / tag / sha，由 GitHub Actions 原生解析

### 输出 1：PR check status

- 每个 cell 一个 check，命名：`ZMK compat matrix / build (<zmk_ref>, <shield>)`
- Required-check（在 GitHub repo setting 中配置）：至少 `(4dd95d7, totem_left)` 和 `(e844eca2, totem_left)` 两个冻结 pin 必须绿才允许 merge（这两个覆盖 `#ifdef` 的两条分支）
- `(main, totem_left)` 建议 required 但接受灵活配置（允许上游 breaking change 时暂时豁免）

### 输出 2：失败 issue

- 条件：`event = schedule` AND `at least one matrix cell failed` AND `no existing open issue with label=compat-break`
- 标题模板：`[compat] ZMK matrix failed on YYYY-MM-DD`
- 正文模板：见上述 workflow yaml
- Label：`compat-break`（这个 label 必须由维护者提前创建；CI 不自动建）

### 输出 3：Artifact

- 名称：`build-log-<zmk_ref>-<shield>`
- 内容：`build/CMakeFiles/CMakeConfigureLog.yaml`（CMake configure 日志，含 `check_zmk_compat.py` 的 banner）、`build/zephyr/.config`（Kconfig snapshot）
- 保留：30 天（GH Actions 默认）

## 规约边界

### MUST
- `validate-manifest` MUST 在 `build` 之前跑：避免因 YAML 坏导致所有矩阵格误报 CI red。
- `file-issue-on-main-break` MUST 在 `event_name == 'schedule'` 守卫下运行：避免 PR 失败也开 issue 污染列表。
- 失败 artifact MUST 上传——否则日度 CI 变红时，`actions/runs/<id>` 的 web UI 看不到完整 configure 日志（GH 对 docker-action 的日志截断过）。

### SHOULD
- `on_schedule_failure.create_issue: false` 时，workflow SHOULD 退化为"仅 badge 变红"（跳过 issue job）。但本契约默认 `true`。
- `concurrency` 组建议为 `zmk-compat-${{ github.ref }}`，避免同一 PR 多次 push 并发跑；可选加入。

### MUST NOT
- MUST NOT 在 PR 失败时开 issue（会在 PR 来回 force-push 时产生大量 noise）。
- MUST NOT 在 `file-issue-on-main-break` 中添加任何自动关闭老 issue 的逻辑（信号累积比信号去重更重要）。
- MUST NOT 把 `compatibility.yaml` 的内容硬编码到 workflow yaml（必须通过 `scripts/regen_ci.py` 派生并随 PR 一起提交）。

## 签字过的变更路径

**派生流程**：
```
compatibility.yaml  (edit by maintainer)
      │
      │  make regen-ci
      ▼
scripts/regen_ci.py
      │
      ▼
.github/workflows/zmk-main-compat.yml  (regenerated)
      │
      │  git add + commit + PR
      ▼
PR review  (reviewer 对比 yaml diff 和 workflow diff 是否一致)
      │
      ▼
merge
```

Pre-commit hook（可选，但推荐）：若 `compatibility.yaml:ci` 变了但 `workflow.yml` 没跟着变，直接 reject commit。

## 失败模式与缓解

| 失败模式 | 缓解 |
|---|---|
| ZMK repo rate-limit（匿名 clone 60 req/hour） | GitHub Actions 的 token 已 opt-in；若遇限流，workflow 加 `token: ${{ secrets.GITHUB_TOKEN }}` 到 checkout |
| docker-action image 过时 | pin 到 `zmkfirmware/zmk-docker-action@v2`（major），每季度人工 review |
| GitHub Actions outage | 日度 CI 自然延后，无额外处理 |
| `scripts/regen_ci.py` bug 导致生成的 workflow 坏 | PR 的 `validate-manifest` 和 `build` job 自己会红——自监控 |

## 不在本契约内（显式排除）

- GitHub Actions 的 cost 控制策略：留给维护者（私仓用户按需调 `ci.schedule` 频率）。
- 本 workflow 对 keybeacon 主仓（非 zmk-keybeacon 模块仓）的任何引用：无（本契约 strictly scope 到模块仓）。
- 对 PR 的强制 reviewer 规则：GitHub repo setting 层面，不属于 workflow 契约。
