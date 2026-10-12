# 003 真实硬件手工验证日志

本文件由 T039 / T040 / T056 累积真实硬件验证证据。由于本仓 maintainer 无法远程操控 Totem 键盘，这些任务**待用户在真机上执行**后手动填入。

## T039 — US1 Scenario 1（兼容路径 end-to-end）

**预期**：`zmk-keybeacon@v1.1.4` + `zmk@4dd95d7`（renamed-era 冻结 pin，走 `#else` 新 API 分支）组合构建 → 烧录 Totem → macOS KeyBeacon app 显示 Connectivity & Battery 卡片 4 行齐全 → `conformance_tool.py` 退出 0、`AA440AA2.present == true`、US1/US2_split_link/US3_output_endpoint 全 PASS。

| 项 | 状态 | 证据 |
|---|---|---|
| west build 成功 | ⬜ pending |  |
| CMake 日志含 `[zmk-keybeacon 1.1.4] ZMK revision check: 4dd95d7 ∈ [known-good: ...) ✓` | ⬜ pending |  |
| compile line 含 `-DZMK_KEYBEACON_HAS_LEGACY_ENDPOINT=1`（legacy pin）或**不**含（renamed pin） | ⬜ pending | 用 `west build -v` 捕获编译命令验证 |
| 烧录成功 | ⬜ pending |  |
| macOS KeyBeacon app 显示 4 行 | ⬜ pending | 截图 |
| `conformance_tool.py --timeout 15` 退出 0 | ⬜ pending | 终端输出粘贴 |

## T040 — US1 Scenario 2（fail-fast 真实触发）

**预期**：手工构造一个两个符号（`zmk_endpoints_selected` 与 `zmk_endpoint_get_selected`）都不存在的 ZMK fork commit，`west.yml` pin 到该 commit → `west build` 在 CMake configure 阶段 fail-fast，输出的 banner 与 `expected_banner_v1.1.4.txt` 契约逐项对齐（除 "Current ZMK: <sha>" 一行会因真实 sha 不同而不同）。

| 项 | 状态 | 证据 |
|---|---|---|
| 构造破坏 fixture（删除 endpoints.h 中两个符号） | ⬜ pending |  |
| `west build` 退出码 ≠ 0 | ⬜ pending |  |
| CMake 日志含标题框 `is INCOMPATIBLE` | ⬜ pending |  |
| banner 的 "How to fix" 三条建议齐全 | ⬜ pending |  |
| banner 的 "Also" 段落显式劝退 `.conf` workaround | ⬜ pending |  |
| **不**出现 `undefined reference to 'zmk_endpoints_selected'` 等 C 编译期错误 | ⬜ pending | 关键验证点 |

## T056 — US3 对比验证

**预期**：保留 `CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n` 的 `totem_left.conf` → build/flash/测 `conformance_tool.py` → `AA440AA2.present == false`；删除该 workaround → 再 build/flash/测 → `AA440AA2.present == true`。

| 项 | 状态 | 证据 |
|---|---|---|
| 保留 workaround 时 `AA440AA2.present == false` | ⬜ pending | `conformance_tool.py --json` 原始输出 |
| 删除 workaround 时 `AA440AA2.present == true` | ⬜ pending | 同上 |

---

## Feature closeout（T061 时追加）

<!-- 发 v1.1.4 正式 tag 后追加 release URL、tag sha、对 FR/SC 的覆盖确认 -->
