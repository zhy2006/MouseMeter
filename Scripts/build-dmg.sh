#!/usr/bin/env bash
# 将已构建的 App 打包成带 Applications 快捷方式的拖拽安装镜像。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MouseMeter.app"
if [[ ! -d "$APP" ]]; then
    echo "请先执行 make app" >&2
    exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/MouseMeter-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
# ditto 保留 bundle 的权限、符号链接和签名资源。
ditto "$APP" "$STAGING/MouseMeter.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "MouseMeter" -srcfolder "$STAGING" \
    -format UDZO -ov "$DMG"
SIGN_IDENTITY="${SIGN_IDENTITY:-Flick Self-Signed Code Signing}"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"
codesign --verify --strict "$DMG"
hdiutil verify "$DMG"
echo "✅ 已生成 $DMG"
