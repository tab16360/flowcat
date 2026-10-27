# Contributing

Install the Xcode Command Line Tools, then run `bash scripts/test.sh` and `bash scripts/build.sh`. The project has no third-party runtime dependencies.

When you change sampling, persistence or network attribution, run the core checks and verify on a real Mac: counter resets, wake from sleep, network switches and midnight. For UI changes, check light and dark mode, small screens, long process names, empty states, denied permissions, and both English and Chinese (`--lang-en` / `--lang-zh` with `--render-preview`, or run `bash scripts/screenshots.sh`).

Every user-facing string goes through `tr("English", "中文")` in `Sources/Core.swift`; English is the base language.

When filing an issue, include your macOS version, chip, FlowCat version, steps to reproduce and any message shown. Screenshots, logs, CSV files and ledger.json may contain private Wi-Fi names, apps or paths, so redact them first.

Never commit local history, tokens, certificates or personal configuration.

---

[简体中文](#参与开发)

# 参与开发

安装 Xcode Command Line Tools，运行 `bash scripts/test.sh` 和 `bash scripts/build.sh`。项目无第三方运行依赖。

修改采样、持久化或网络归属时运行核心检查，并在真实 Mac 验证计数器重置、睡眠恢复、网络切换和午夜跨日。UI 修改需实测明暗主题、小屏、长进程名、空状态、权限拒绝，以及中英文两种界面。

所有界面文案通过 `Sources/Core.swift` 中的 `tr("English", "中文")` 提供，英文为基础语言。

提交 Issue 请说明 macOS 版本、芯片类型、应用版本、复现步骤及提示文字。截图、日志、CSV 和 ledger.json 可能包含私人 Wi-Fi 名称、应用或路径信息，分享前请脱敏。

不要将本机历史、令牌、证书或个人配置提交到仓库。
