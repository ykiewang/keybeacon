# 从 v1.1.3 升级到 v1.1.4 — 操作手册 / Upgrade Notes

**English** · [中文](#zh)

本文件为 002 feature 的消费者提供从 `zmk-keybeacon@v1.1.3` 升级到 `v1.1.4` 的完整步骤。

v1.1.4 引入了 **ZMK revision 兼容契约**（see [003 spec][003-spec]）：

- 修复了 `zmk_endpoints_selected()` 在新 ZMK（commit `6e7e0de2` 2026-02-12 之后）上的编译失败
- 消费者不再需要在 `.conf` 里禁用 CONNECTIVITY 子选项作为 workaround
- 不兼容的 ZMK revision 会在 CMake configure 阶段 fail-fast 并给出可执行诊断

[003-spec]: ../../specs/003-zmk-revision-pinning/spec.md
[003-plan]: ../../specs/003-zmk-revision-pinning/plan.md

---

## English — upgrade steps

### 1. Bump `west.yml` to v1.1.4

```yaml
# config/west.yml  (or wherever your zmk-config lives)
manifest:
  projects:
    - name: zmk
      remote: zmkfirmware
      revision: main                    # or any pinned ZMK sha
    - name: zmk-keybeacon
      remote: ykiewang
      revision: v1.1.4                  # was v1.1.3
```

### 2. Remove the `.conf` workaround (if present)

If your shield's `.conf` carries any of the following lines (added during the
v1.1.3 era to work around the ZMK API drift), **delete them all**:

```conf
# config/<shield>.conf — DELETE THESE LINES on v1.1.4+:
CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n
# (plus any other CONFIG_ZMK_KEYBEACON_CHAR_*=n you may have added)
```

With v1.1.4 the compile is fixed at the source, so disabling characteristics
is no longer needed to make the build succeed. Keeping these lines silently
removes host-side features (the macOS KeyBeacon app's Connectivity &
Battery card will stay blank).

### 3. Rebuild and reflash

```sh
cd <your-zmk-config>
west update
west build -p -s zmk/app -b <board> -- -DSHIELD=<shield> \
    -DZMK_EXTRA_MODULES=$PWD/../zmk-keybeacon
# flash as usual
```

### 4. Verify

The macOS KeyBeacon app's "Connectivity & Battery" card should populate
within ≤ 1 second of connecting. Expected rows:

- host-connection state
- profile slot (open/paired flag)
- split-halves on/off
- output endpoint (USB vs BLE)

Running `python3 conformance/conformance_tool.py --timeout 15` from the
main KeyBeacon repo should return exit 0 with `AA440AA2.present == true`.

### If the build fails with a banner

If the CMake configure step prints a banner starting with
`╔══...  zmk-keybeacon 1.1.4 is INCOMPATIBLE with the current ZMK revision`,
your `west.yml`'s ZMK pin is outside the known-good window. Pick one of
the three fixes the banner lists; the simplest is **[1] pin ZMK back to a
known-good revision**:

```yaml
# config/west.yml
projects:
  - name: zmk
    revision: 4dd95d7   # last validated by zmk-keybeacon v1.1.4 CI
```

Then `west update && west build -p` and the build will succeed.

See [`contracts/fail-fast-banner.md`][banner-contract] for the full banner
contract.

[banner-contract]: ../../specs/003-zmk-revision-pinning/contracts/fail-fast-banner.md

---

<a id="zh"></a>

## 中文 — 升级步骤

### 1. 把 `west.yml` 升到 v1.1.4

```yaml
# config/west.yml（或你的 zmk-config 实际路径）
manifest:
  projects:
    - name: zmk
      remote: zmkfirmware
      revision: main                    # 或任意 pin 的 ZMK sha
    - name: zmk-keybeacon
      remote: ykiewang
      revision: v1.1.4                  # 原本是 v1.1.3
```

### 2. 删除 `.conf` 中的历史 workaround（如有）

v1.1.3 时代为绕过 ZMK API 漂移编译错而加的 workaround 行，v1.1.4 开始要**全部删除**：

```conf
# config/<shield>.conf — v1.1.4+ 删除这些行：
CONFIG_ZMK_KEYBEACON_CHAR_CONNECTIVITY=n
# （以及任何其他你曾加过的 CONFIG_ZMK_KEYBEACON_CHAR_*=n 行）
```

v1.1.4 已经在源头修复编译问题，禁用字符特征不再是解决编译错的手段——**保留这些行**会悄悄让 host 侧（macOS KeyBeacon app）的 Connectivity & Battery 卡片变空。

### 3. 重新构建并烧录

```sh
cd <your-zmk-config>
west update
west build -p -s zmk/app -b <board> -- -DSHIELD=<shield> \
    -DZMK_EXTRA_MODULES=$PWD/../zmk-keybeacon
# 按原流程烧录
```

### 4. 验证

macOS KeyBeacon app 的"Connectivity & Battery"卡片应在连接后 ≤ 1 秒内刷出 4 行：

- host 连接状态
- profile 槽位（含 open/paired 标记）
- 分体键盘左右半 online/offline
- 输出端点（USB vs BLE）

在 KeyBeacon 主仓运行 `python3 conformance/conformance_tool.py --timeout 15` 应该返回退出码 0，且 `AA440AA2.present == true`。

### 构建失败并输出 banner 怎么办？

如果 CMake configure 步骤打印了一个以
`╔══...  zmk-keybeacon 1.1.4 is INCOMPATIBLE with the current ZMK revision`
开头的 banner，说明你 `west.yml` 的 ZMK pin 在 known-good 窗口之外。按 banner 列出的三条建议**挑一条执行**，最简单的是 **[1] 把 ZMK pin 回已知兼容 revision**：

```yaml
# config/west.yml
projects:
  - name: zmk
    revision: 4dd95d7   # zmk-keybeacon v1.1.4 CI 验证过的 ZMK commit
```

然后 `west update && west build -p`，构建就能通过。

banner 的完整契约见 [`contracts/fail-fast-banner.md`][banner-contract]。
