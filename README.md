<div align="center">
  <img src="public/icon.png" width="128" height="128" alt="Lingobar Logo">
  <h1>Lingobar</h1>
  <p>macOS 菜单栏翻译工具 — 剪贴板监听 · 低打扰翻译 · 本地统计</p>

  <p>
    <a href="https://github.com/caterpi11ar/lingobar/releases"><img src="https://img.shields.io/github/v/release/caterpi11ar/lingobar?style=flat-square" alt="GitHub release"></a>
    <a href="https://github.com/caterpi11ar/lingobar"><img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue?style=flat-square" alt="Platform"></a>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift" alt="Swift"></a>
    <a href="https://github.com/caterpi11ar/lingobar/stargazers"><img src="https://img.shields.io/github/stars/caterpi11ar/lingobar?style=flat-square" alt="GitHub stars"></a>
    <a href="https://github.com/caterpi11ar/lingobar/issues"><img src="https://img.shields.io/github/issues/caterpi11ar/lingobar?style=flat-square" alt="GitHub issues"></a>
    <a href="https://github.com/caterpi11ar/lingobar/blob/main/LICENSE"><img src="https://img.shields.io/github/license/caterpi11ar/lingobar?style=flat-square" alt="GitHub license"></a>
  </p>
  <p><a href="README_EN.md"><b>English</b></a> | 中文</p>

</div>

## 功能特性

- 菜单栏常驻，随时翻译
- 自动监听剪贴板文本变化并触发翻译
- 菜单栏实时状态反馈与译文预览
- 可选自动回写剪贴板
- 本地翻译统计
- 设置页支持自定义配置，自动保存并即时生效
- 支持自定义翻译服务（OpenAI 兼容接口）
- 支持源语言 / 目标语言选择，默认自动检测

## 效果预览

![gif 效果预览](public/example1.gif)

![菜单栏翻译弹层](public/example2.png)

## 安装

前往 [Releases](https://github.com/caterpi11ar/lingobar/releases) 页面下载最新的 DMG 文件，打开后将 `Lingobar.app` 拖入 `Applications` 文件夹即可。

## 首次打开

应用尚未使用 Apple 开发者证书签名，macOS Gatekeeper 会阻止从网上下载的未签名应用。

**方法一** — 右键点击应用 → 选择"打开" → 在弹窗中点击"打开"（只需一次）。

**方法二** — 前往 **系统设置 → 隐私与安全性**，下滑找到"仍要打开"按钮。

**方法三** — 在终端中移除隔离标记：

```bash
xattr -cr "/Applications/Lingobar.app"
```

以上任一方法操作后，后续即可正常打开。

## 从源码构建

```bash
git clone https://github.com/caterpi11ar/lingobar.git
cd lingobar
open Lingobar.xcodeproj
```

在 Xcode 中选择 `Lingobar` scheme，按 `Cmd+R` 运行。

## 系统要求

- macOS 15+

## 贡献

欢迎提交 Issue 和 Pull Request！

## 致谢

- [read-frog](https://github.com/nicepkg/read-frog) — 翻译服务相关参考
