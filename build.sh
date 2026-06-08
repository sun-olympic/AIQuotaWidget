#!/bin/bash
# 构建 AIQuotaWidget.app（无需完整 Xcode，仅用 Command Line Tools 的 swiftc）。
# 若你的机器装有完整 Xcode，也可直接用 `swift build` 或在 Xcode 中打开 Package.swift。
set -euo pipefail

APP_NAME="AIQuotaWidget"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/.build/app"
BUNDLE="$BUILD_DIR/$APP_NAME.app"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx13.0"

echo "==> Cleaning"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "==> Collecting sources"
SOURCES=$(find "$ROOT/Sources" -name '*.swift')

echo "==> Compiling ($TARGET)"
xcrun swiftc -O \
    -target "$TARGET" \
    $SOURCES \
    -lsqlite3 \
    -framework AppKit \
    -framework SwiftUI \
    -o "$BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Bundling"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/doraemon.png" "$BUNDLE/Contents/Resources/doraemon.png"

echo "==> Done: $BUNDLE"
echo "Run with: open \"$BUNDLE\"  (或 \"$BUNDLE/Contents/MacOS/$APP_NAME\")"
