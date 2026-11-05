#!/usr/bin/env bash
# 构建 MouseMeter.app 到 build/ 目录
#   Scripts/build-app.sh            # release 构建
#   Scripts/build-app.sh --install  # 构建后复制到 /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MouseMeter.app"
cd "$ROOT"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MouseMeter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MouseMeter"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICON_TMP="$(mktemp -d)"
swift Scripts/make-icon.swift "$ICON_TMP"
iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

# ad-hoc 签名：输入监控授权与登录项都依赖稳定的代码签名
codesign --force --deep --sign - "$APP"

echo "✅ 已生成 $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/MouseMeter.app
    cp -R "$APP" /Applications/
    echo "✅ 已安装到 /Applications/MouseMeter.app"
fi
