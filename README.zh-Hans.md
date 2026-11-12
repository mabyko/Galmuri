# Galmuri · 갈무리

**把多个配置文件的书签集中整理，再应用回浏览器。**

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · 简体中文

Galmuri 是一个用 SwiftUI 编写、处于实验阶段的 **macOS 原生书签编辑器**。它把多个 Chrome 配置文件的书签读入工作副本，让你可以安全地编辑；在任何内容离开应用之前展示全部更改，并把你的编辑与浏览器在此期间的变化合并。

> **状态：实验阶段。** 目前没有可下载的安装包，需要从源码构建。Galmuri 不会写入真实的 Chrome 配置文件。现在要把更改带回 Chrome，可以导出 HTML 再导入，或使用[实验室](#实验室)中可选的扩展方式。

## 能做什么

- **以只读方式连接 Chrome 配置文件。** 选择需要的配置文件后，Galmuri 为每个配置文件单独保存一份副本，不改动原始文件。
- **像文件管理器一样编辑。** 支持嵌套文件夹、搜索、多选移动、拖放、排序、相同地址浏览和撤销。
- **显示更改内容。** “待应用的更改”视图列出所有新增、修改、移动和删除的项目。可以只还原所选项目，也可以全部放弃。
- **合并而不是覆盖。** 刷新会重新读取浏览器的书签，并与你的编辑进行三方合并。冲突会并排显示，由你选择。
- **导出。** 任何浏览器都能导入的 Netscape HTML（整个配置文件或单个文件夹），以及整个工作区的 JSON 备份。
- **支持四种语言。** 英语、韩语、日语和简体中文。

## 目前还不能做什么

- 写入真实的 Chrome 配置文件。直接文件应用只对应用自己创建的合成测试文件有效。
- 读取加密的或仅限账户的书签存储。只支持带有明文 `Bookmarks` 文件的配置文件。
- 同步、云存储或账户。所有数据都只保存在你的 Mac 上。
- 提供已签名并公证的构建。

## 构建与运行

需要 macOS 14 或更高版本、Xcode 命令行工具和 Swift 6。没有第三方依赖。

```sh
swift test
python3 scripts/check-localization.py
scripts/build-local.sh release
open "build/release/Galmuri.app"
```

脚本只生成一个临时签名的本地应用，不会安装任何东西，也不会注册 Apple 团队。Debug 构建、数据位置和一次性冒烟检查请参阅[本地开发](docs/local-development.md)。

首次启动时选择**连接 Chrome**。macOS 可能会询问是否允许访问浏览器的数据文件夹。Galmuri 会说明这一步，并且只读取你选择的配置文件。

## 如何保证更改安全

1. Galmuri 把首次读取的书签保存为 **Base**，你在单独的工作副本（**Ours**）中编辑。
2. 在应用或刷新之前，它会重新读取浏览器当前的书签（**Theirs**）。
3. 三方合并把两边结合起来。两边都改动过的项目会成为冲突，由你明确解决。
4. 在使用之前，你可以检查包括删除项在内的最终结果。

在刷新之前、断开配置文件之前以及导入工作区之前，都会保留一份工作内容的本地副本。

## 实验室

设置 → 实验室中有两个默认关闭的开关：

- **API 连接与编辑器。** 一个小型 Chrome 扩展和应用内的辅助程序，在 Chrome 保持打开的情况下，通过 Chrome 自身的书签 API 读取和编辑书签。每个配置文件通过屏幕上显示的代码配对。普通连接在 Chrome 一侧是只读的，应用更改仅限于专用测试环境。被移除的项目会移到恢复文件夹，而不是删除。请参阅 [API 设置、行为与限制](docs/chrome-api-workspace.md)。
- **直接文件应用。** 对 `Bookmarks` 文件的备份、替换和恢复，仅限 Galmuri 自己拥有的合成测试文件。

扩展只请求 `bookmarks`、`nativeMessaging` 和 `storage` 权限，没有网站权限。详情见[实验室与安装](docs/labs.md)。

## 隐私

Galmuri 没有网络功能、分析统计或账户。书签只在你的 Mac 上读取和保存。请不要在 issue、拉取请求和测试数据中放入真实的书签、浏览器配置文件、备份或私密网址，请使用合成数据。

## 文档

- [文档目录](docs/README.md)
- [发行说明与详细现状](docs/release-notes.md)
- [产品计划](docs/product-plan.md)和[路线图](docs/roadmap.md)
- [技术验证标准](docs/technical-validation.md)和[验证记录](docs/validation.md)
- [架构决策](docs/adr/README.md)和[术语表](GLOSSARY.md)
- [任务列表](TASKS.md)

文档以英语为准，链接的文档均为英文。[HTML 设计原型](design/galmuri-prototype.html)是使用合成数据的设计参考，不是应用本身。

## 贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。

## 许可证

[MIT](LICENSE) · Copyright (c) 2026 Galmuri contributors.
