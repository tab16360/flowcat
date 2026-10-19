# AI 工具越装越多，SSD 谁在写？给流量喵加了磁盘监控

之前做了个 macOS 菜单栏流量工具「流量喵」，这次加上了磁盘监控。

起因是看到 [Codex 用户反馈持续写盘](https://github.com/openai/codex/issues/21007)。自己也同时用着 Codex、Claude Code、Cursor，加上索引、缓存和构建，后台越来越热闹。SSD 写入耐久度有限，想知道：**到底谁在写，一天下来写了多少？**

这次新增：

- **进程读写排行**：按写入、读取或总量排序，支持今日、近 7 天、近 30 天和累计，也能导出 CSV。
- **磁盘状态**：查看系统能提供的 SMART、温度、累计主机写入、通电时间和耐久度已用等信息。
- **菜单栏实时读写**：读取在上、写入在下，开关独立于网速显示。

![磁盘读写排行，图中为示例数据](https://tab16360.github.io/flowcat/assets/disk-io.png)

原来的应用流量排行、按 Wi-Fi 分开统计也都保留。Swift / SwiftUI 原生开发，免费、MIT 开源，数据留在本机，无需账号。

统计从运行后开始；进程 I/O 不等于 SSD 闪存实际写入，健康指标是否可读取决于磁盘、硬盘盒和权限。

[介绍与下载](https://tab16360.github.io/flowcat/) · [GitHub 源码](https://github.com/tab16360/flowcat)

大家会关注 AI 开发工具的累计写盘量吗？
