# 发布指南

## 首次发布

本机正常终端中已登录 GitHub 后，可直接运行 `bash scripts/publish.sh`。脚本使用当前账号创建公开的 `flowcat` 仓库，更新账号链接、执行检查与打包、启用 Pages 并推送版本标签。远端工作流完成后才有可用的站点和 Release。仓库已有 origin 时脚本会停止，请按下面步骤继续，避免重复创建。

1. `gh auth login -h github.com` 登录目标账号。
2. 核对 README 与 `docs/index.html` 的 GitHub 账号和仓库链接。
3. `bash scripts/test.sh`、`bash scripts/package.sh`。
4. `git init -b main`，提交项目，然后创建公开仓库：

```sh
gh repo create flowcat --public --source . --remote origin --push --description '原生 macOS 菜单栏流量喵：进程排行、按 Wi-Fi 统计、今日/昨日/月流量'
```

5. 通过 GitHub 设置 → Pages → Source 选择 GitHub Actions；也可通过 API：

```sh
gh api --method POST repos/OWNER/flowcat/pages -f build_type=workflow
gh workflow run pages.yml
```

6. 等待主分支 CI 成功，创建并推送版本标签：

```sh
git tag -a v1.3.5 -m 'Release 1.3.5'
git push origin v1.3.5
```

Release workflow 自动检查版本、运行核心检查、构建 arm64 ZIP 并发布附带 SHA-256 的 Release。避免同时使用工作流和手动命令创建同一 Release。

## 后续更新

更新 `Info.plist` 的版本和构建号、更新日志、Release 说明以及介绍页版本。核心逻辑修改运行检查；真实 Mac 验证采集、睡眠和权限。push main 后确认 CI，再推送匹配版本标签。

README 图示是带标注的示例，替换为真实截图时去除个人 SSID、应用和路径。不要提交运行历史或个人配置。

当前构建使用临时签名。Developer ID 签名和 Apple 公证需开发者证书与账号，尚未配置；不要把私钥或证书提交仓库。

## 自动替换更新验证

发布流程在打包后运行 `bash scripts/test-update-helper.sh`，使用打包出的真实可执行文件作为独立更新进程，在隔离目录替换应用。`bash scripts/test.sh` 包含安装包路径、摘要、签名团队及事务回滚检查。维护更新器时必须保留 `--finish-update` 计划格式和 `--update-receipt` 启动确认协议的兼容性，避免旧版更新器无法安装新版本。

更新包必须保持根目录 `流量喵.app/`，Release 资产名为 `FlowCat-版本-arm64.zip`，GitHub API 应提供 `sha256:` 摘要及实际大小；缺失可靠摘要时应用拒绝自动安装。
