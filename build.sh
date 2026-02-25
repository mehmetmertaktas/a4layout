#!/bin/bash
set -e

APP="A4 Layout.app"
BUNDLE="$APP/Contents"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building A4 Layout..."

# Create bundle structure
mkdir -p "$BUNDLE/MacOS" "$BUNDLE/Resources"

# Compile
swiftc -O -o "$BUNDLE/MacOS/A4Layout" "$SCRIPT_DIR/a4layout.swift" \
    -framework AppKit -framework UniformTypeIdentifiers

# Info.plist
cat > "$BUNDLE/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>A4 Layout</string>
    <key>CFBundleDisplayName</key>
    <string>A4 Layout</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.a4layout</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>A4Layout</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

# Generate icon
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"

ICON_SWIFT=$(mktemp).swift
cat > "$ICON_SWIFT" << 'ICONSWIFT'
import AppKit
let dir = CommandLine.arguments[1]
let sizes: [(CGFloat, String)] = [
    (16,"icon_16x16"),(32,"icon_16x16@2x"),(32,"icon_32x32"),(64,"icon_32x32@2x"),
    (128,"icon_128x128"),(256,"icon_128x128@2x"),(256,"icon_256x256"),(512,"icon_256x256@2x"),
    (512,"icon_512x512"),(1024,"icon_512x512@2x"),
]
for (sz, name) in sizes {
    let img = NSImage(size: NSSize(width: sz, height: sz))
    img.lockFocus()
    let r = NSRect(x: 0, y: 0, width: sz, height: sz)
    let rad = sz * 0.18
    let bg = NSBezierPath(roundedRect: r.insetBy(dx: sz*0.02, dy: sz*0.02), xRadius: rad, yRadius: rad)
    NSColor(white: 0.96, alpha: 1).setFill(); bg.fill()
    NSColor(white: 0.82, alpha: 1).setStroke(); bg.lineWidth = sz*0.015; bg.stroke()
    let pw = sz*0.38, ph = pw/595*842, px = (sz-pw)/2, py = (sz-ph)/2 - sz*0.02
    let page = NSRect(x: px, y: py, width: pw, height: ph)
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.2)
    s.shadowOffset = NSSize(width: 0, height: -sz*0.01); s.shadowBlurRadius = sz*0.03; s.set()
    NSColor.white.setFill(); page.fill()
    NSGraphicsContext.restoreGraphicsState()
    let m = sz*0.04, bw = pw-m*2
    NSColor(red:0.35,green:0.55,blue:0.85,alpha:0.7).setFill()
    NSRect(x:px+m, y:py+ph-m-ph*0.28, width:bw, height:ph*0.28).fill()
    NSColor(red:0.90,green:0.45,blue:0.35,alpha:0.6).setFill()
    NSRect(x:px+m, y:py+ph-m*2-ph*0.28-ph*0.22, width:bw*0.55, height:ph*0.22).fill()
    img.unlockFocus()
    guard let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
ICONSWIFT

swiftc -o "${ICON_SWIFT%.swift}" "$ICON_SWIFT" -framework AppKit 2>/dev/null
"${ICON_SWIFT%.swift}" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$BUNDLE/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")" "$ICON_SWIFT" "${ICON_SWIFT%.swift}"

touch "$APP"

echo ""
echo "Done! Built: $APP"
echo "Move it to /Applications or double-click to run."
