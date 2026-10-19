# 流量喵 Windows 预览版

C++20 / Win32 / Direct2D / DirectWrite，无浏览器界面。支持 Windows 10 22H2 / Windows 11 x64；目前为开发预览，尚未与 macOS 正式版功能对齐。

## 使用

运行 `FlowCat.exe`，允许管理员权限后，应用出现在通知区域。左键打开统计面板，右键暂停、继续或退出。首次运行从零开始，退出进程的已采集记录会保留。应用不会联网上传记录。

- 网络：应用与代理排行、下载/上传、物理网卡总量，今日、昨日、7 天、30 天、累计。
- 磁盘：按进程统计物理磁盘读写，默认按写入排序；可点击表头切换排序，支持搜索。
- 状态：从 NVMe SMART 原始日志按需读取温度、耐久度已用、累计主机读写、通电时间和介质错误。未支持的磁盘或硬盘盒显示“未提供”。
- 历史：使用 Windows 自带 SQLite，保存在 `%LOCALAPPDATA%\FlowCat\history.sqlite`。内存聚合，每分钟事务保存，正常退出时再保存；异常断电可能丢失最近一分钟。CSV 导出保存的是当前时间范围内的每日进程明细。

## 统计口径和预览版边界

网络进程事件来自内核 ETW，覆盖 TCP/UDP 和 IPv4/IPv6，忽略回环。物理网卡总量独立采样，不是进程排行求和；经过代理和 VPN 的进程计数不可相加。当前没有互联网/局域网筛选，网络流量包含局域网。读取 Wi-Fi 名称失败时显示“全部网络”；尚未提供位置权限申请入口或按 SSID 筛选界面。

磁盘使用 ETW Disk I/O 完成事件，并通过发起线程关联进程。缓存读取可能不产生物理 I/O，缓存延迟写入也可能归属于系统；因此与 macOS 的进程 I/O 口径不完全一致，也不等于 SSD 闪存 NAND 实际写入。无法可靠归属的事件显示“系统 / 未归属”，不强行分配给某个应用。不同 PID 的同一可执行路径聚合展示，尚未按父应用合并所有辅助进程。

NVMe 的耐久度已用是磁盘报告值，可以超过 100%，不是剩余寿命预测；“无关键警告”仅表示 SMART 关键警告位为空。当前 SATA/USB SMART 未适配，不使用缺失值推断健康。

首版由单个管理员权限进程采集并显示界面，尚未拆成后台服务。需要用户运行应用后才统计；不自动开机启动，不安装驱动。实时数字在托盘悬停提示和面板内显示，尚未嵌入任务栏。自动更新、代码签名、ARM64 和多显示器/DPI 完整适配仍待完成。请勿替换 macOS 的更新渠道。

## 构建

安装 Visual Studio 2022 Build Tools 的“使用 C++ 的桌面开发”工作负载（含 Windows SDK 和 CMake），然后在 PowerShell 执行：

```powershell
.\windows\build.ps1
```

输出 `windows\build\Release\FlowCat.exe`；使用静态 MSVC 运行库，SQLite 从系统 `winsqlite3.dll` 加载。构建脚本运行核心计数检查和真实 SQLite 持久化检查。

管理员终端可执行隔离实机采集验证：

```powershell
.\windows\tests\verify.ps1
# 可选：局域网 HTTP 服务器提供固定大小文件，验证下载进程归属
.\windows\tests\verify.ps1 -PayloadUrl http://YOUR_LAN_HOST:PORT/payload.bin
```

验证程序在 `windows\build\verify-随机ID` 下保留报告和隔离历史，删除测试数据文件，不改动用户正式历史。不要将报告中的应用名、网络名等个人信息提交仓库。

Windows GitHub Actions 配置模板位于 `ci-preview.yml`；当前尚未启用，需有修改 workflow 权限的凭据将其放入 `.github/workflows/windows.yml` 后生效。
