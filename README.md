# 🍺 Buum

> A lightweight macOS menu bar app that keeps your Homebrew packages and Mac App Store apps up to date — with a single click.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

## What it does

Buum is the GUI version of this `.zshrc` alias:

```bash
alias buum="brew update; brew upgrade; mas outdated; mas upgrade"
```

Click the menu bar icon and everything updates automatically.

## Features

- 📦 Lives in the macOS menu bar — no Dock icon
- 🔄 Animated icon while updates are running
- 🛠️ Auto-installs `brew` and `mas` if not present
- 🔔 Native macOS notification when done
- ✅ Live status messages in the menu

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel Mac

## Installation

### Homebrew (recommended)

```bash
brew tap emreerinc/buum
brew install --cask buum
```

### Manual

Download `Buum.zip` from [Releases](https://github.com/emreerinc/buum/releases), unzip and move to `/Applications`.

## Build from source

```bash
git clone https://github.com/emreerinc/buum.git
cd buum

# Generate app icon
swiftc generate_icon.swift -sdk $(xcrun --show-sdk-path) \
  -target arm64-apple-macosx13.0 -framework AppKit -o generate_icon
./generate_icon
iconutil -c icns Buum.iconset -o AppIcon.icns

# Build app
swiftc main.swift -sdk $(xcrun --show-sdk-path) \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -parse-as-library -o Buum
```

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
