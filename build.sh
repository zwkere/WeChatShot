#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="1.0.0"
APP_NAME="WeChatShot"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DIST_DIR="$PROJECT_DIR/dist"

echo "🔨 [1/6] 正在清理并创建应用包目录结构..."
rm -rf "$APP_BUNDLE" "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DIST_DIR"

cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "🎨 [2/6] 正在生成应用图标 AppIcon.icns..."
ICONSET_DIR="$PROJECT_DIR/Resources/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift -e '
import Cocoa
let size = NSSize(width: 512, height: 512)
let img = NSImage(size: size)
img.lockFocus()
let rect = NSRect(origin: .zero, size: size).insetBy(dx: 32, dy: 32)
let path = NSBezierPath(roundedRect: rect, xRadius: 100, yRadius: 100)
let grad = NSGradient(colors: [
    NSColor(srgbRed: 0.05, green: 0.82, blue: 0.43, alpha: 1.0),
    NSColor(srgbRed: 0.02, green: 0.68, blue: 0.34, alpha: 1.0)
])
grad?.draw(in: path, angle: -90)

let cfg = NSImage.SymbolConfiguration(pointSize: 220, weight: .bold)
if let sym = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let tinted = sym.copy() as! NSImage
    tinted.lockFocus()
    NSColor.white.set()
    NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let sSize = tinted.size
    tinted.draw(in: NSRect(x: (512 - sSize.width)/2, y: (512 - sSize.height)/2, width: sSize.width, height: sSize.height))
}
img.unlockFocus()
if let tiff = img.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: "'"$ICONSET_DIR"'/icon_512x512.png"))
}
'

for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$ICONSET_DIR/icon_512x512.png" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null
    sz2=$((sz * 2))
    sips -z $sz2 $sz2 "$ICONSET_DIR/icon_512x512.png" --out "$ICONSET_DIR/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
SOURCES=(
    "$PROJECT_DIR/Sources/Models.swift"
    "$PROJECT_DIR/Sources/ScreenCaptureManager.swift"
    "$PROJECT_DIR/Sources/HotKeyManager.swift"
    "$PROJECT_DIR/Sources/ToolbarView.swift"
    "$PROJECT_DIR/Sources/PinWindowController.swift"
    "$PROJECT_DIR/Sources/OCRWindowController.swift"
    "$PROJECT_DIR/Sources/ScreenshotCanvasView.swift"
    "$PROJECT_DIR/Sources/OverlayWindowController.swift"
    "$PROJECT_DIR/Sources/MainWindowController.swift"
    "$PROJECT_DIR/Sources/main.swift"
)
FRAMEWORKS=(
    -framework Cocoa
    -framework Carbon
    -framework CoreImage
    -framework ScreenCaptureKit
    -framework Vision
    -framework ServiceManagement
)

echo "⚡ [3/6] 正在编译 Universal Binary (arm64 + x86_64, 支持 macOS 14.0+)..."
swiftc -O -sdk "$SDK_PATH" -target arm64-apple-macosx14.0 "${FRAMEWORKS[@]}" "${SOURCES[@]}" -o "$MACOS_DIR/${APP_NAME}_arm64"
swiftc -O -sdk "$SDK_PATH" -target x86_64-apple-macosx14.0 "${FRAMEWORKS[@]}" "${SOURCES[@]}" -o "$MACOS_DIR/${APP_NAME}_x86_64"
lipo -create -output "$MACOS_DIR/$APP_NAME" "$MACOS_DIR/${APP_NAME}_arm64" "$MACOS_DIR/${APP_NAME}_x86_64"
rm -f "$MACOS_DIR/${APP_NAME}_arm64" "$MACOS_DIR/${APP_NAME}_x86_64"

echo "🔏 [4/6] 正在为 $APP_NAME.app 签名..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "📦 [5/6] 正在打包发布文件 (.zip 与 .dmg) 至 dist/ 目录..."
ZIP_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

DMG_STAGING="$DIST_DIR/dmg_staging"
DMG_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}-macOS-universal.dmg"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING"

echo "🚀 [6/6] 正在同步安装到 /Applications/$APP_NAME.app..."
if [ -w "/Applications" ]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
fi

echo "✅ 构建完成！"
echo "   • 通用二进制验证: $(lipo -info "$MACOS_DIR/$APP_NAME")"
echo "   • DMG 安装镜像 : $DMG_PATH"
echo "   • ZIP 压缩包   : $ZIP_PATH"
