<div align="center">
  <img src="public/icon.png" width="128" height="128" alt="Lingobar Logo">
  <h1>Lingobar</h1>
  <p>macOS menu bar translation tool — clipboard monitoring · low-distraction translation · local statistics</p>

  [![GitHub release](https://img.shields.io/github/v/release/caterpi11ar/lingobar?style=flat-square)](https://github.com/caterpi11ar/lingobar/releases)
  [![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue?style=flat-square)](https://github.com/caterpi11ar/lingobar)
  [![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift)](https://swift.org)
  [![GitHub stars](https://img.shields.io/github/stars/caterpi11ar/lingobar?style=flat-square)](https://github.com/caterpi11ar/lingobar/stargazers)
  [![GitHub issues](https://img.shields.io/github/issues/caterpi11ar/lingobar?style=flat-square)](https://github.com/caterpi11ar/lingobar/issues)
  [![GitHub license](https://img.shields.io/github/license/caterpi11ar/lingobar?style=flat-square)](https://github.com/caterpi11ar/lingobar/blob/main/LICENSE)

  [中文](README.md) | **English**

</div>

## Features

- Lives in the menu bar, always ready to translate
- Automatically monitors clipboard text changes and triggers translation
- Real-time status feedback and translation preview in the menu bar
- Optional auto-write back to clipboard
- Local translation statistics
- Settings page with customizable configuration, auto-save and instant effect
- Custom translation service support (OpenAI-compatible API)
- Source / target language picker with auto-detect by default

## Preview

![Demo GIF](public/example1.gif)

![Menu bar translation popover](public/example2.png)

## Installation

Go to the [Releases](https://github.com/caterpi11ar/lingobar/releases) page, download the latest DMG file, open it and drag `Lingobar.app` into the `Applications` folder.

## First Launch

The app is not signed with an Apple Developer certificate, so macOS Gatekeeper will block it.

**Option 1** — Right-click the app → select "Open" → click "Open" in the dialog (only needed once).

**Option 2** — Go to **System Settings → Privacy & Security**, scroll down and click "Open Anyway".

**Option 3** — Remove the quarantine attribute in Terminal:

```bash
xattr -cr "/Applications/Lingobar.app"
```

After any of the above, the app will open normally from then on.

## Build from Source

```bash
git clone https://github.com/caterpi11ar/lingobar.git
cd lingobar
open Lingobar.xcodeproj
```

Select the `Lingobar` scheme in Xcode and press `Cmd+R` to run.

## Requirements

- macOS 15+

## Contributing

Issues and Pull Requests are welcome!

## Acknowledgments

- [read-frog](https://github.com/nicepkg/read-frog) — Translation service reference
