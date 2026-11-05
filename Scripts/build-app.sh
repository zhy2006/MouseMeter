#!/usr/bin/env bash
# 构建 MouseMeter.app 到 build/ 目录
#   Scripts/build-app.sh            # release 构建
#   Scripts/build-app.sh --install  # 构建后复制到 /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MouseMeter.app"
cd "$ROOT"

VERSION="$(tr -d '\r\n' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION 必须为 major.minor.patch 格式" >&2
    exit 1
fi

# 默认构建通用二进制；CI 可指定单一架构。
case "${ARCH:-universal}" in
    universal) ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
    arm64|x86_64) ARCH_ARGS=(--arch "$ARCH") ;;
    *) echo "不支持的架构: $ARCH" >&2; exit 1 ;;
esac
swift build -c release "${ARCH_ARGS[@]}"
BIN="$(swift build -c release "${ARCH_ARGS[@]}" --show-bin-path)/MouseMeter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MouseMeter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
swift Scripts/make-icon.swift "$ICON_TMP"
iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

# 使用本机 Flick 证书，保持更新前后的签名身份一致。
SIGN_IDENTITY="${SIGN_IDENTITY:-Flick Self-Signed Code Signing}"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "✅ 已生成 $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/MouseMeter.app
    cp -R "$APP" /Applications/
    echo "✅ 已安装到 /Applications/MouseMeter.app"
fi
