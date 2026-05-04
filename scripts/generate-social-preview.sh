#!/bin/bash
# GitHub 리포 소셜 프리뷰 이미지(1280×640 PNG) 생성기.
# 동일한 squircle 아이콘 + "gesture-ex" 워드마크 + 한 줄 태그라인을 합성한다.
# 결과물(docs/social-preview.png)은 GitHub 리포 Settings → Social preview에 한 번 업로드한다.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$DIR/docs"
SWIFT_SRC="$DIR/.social-build/render.swift"
SWIFT_BIN="$DIR/.social-build/render"

rm -rf "$DIR/.social-build"
mkdir -p "$OUT_DIR" "$DIR/.social-build"

cat > "$SWIFT_SRC" <<'SWIFT'
import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: render <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = CommandLine.arguments[1]

let W: CGFloat = 1280
let H: CGFloat = 640

let img = NSImage(size: NSSize(width: W, height: H), flipped: false) { rect in
    // 배경: AppIcon과 동일한 인디고→차콜 그라데이션 (방향만 대각선)
    let bgGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.42, alpha: 1.0),
        NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.14, alpha: 1.0),
    ])!
    bgGradient.draw(in: rect, angle: -110)

    // 미세 노이즈 대신 잔잔한 vignette
    let vignette = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.0),
        NSColor(calibratedWhite: 0.0, alpha: 0.30),
    ])!
    vignette.draw(in: rect, relativeCenterPosition: NSPoint(x: 0, y: 0.2))

    // 좌측 squircle 아이콘 — 320pt
    let iconSize: CGFloat = 320
    let iconX: CGFloat = 96
    let iconY: CGFloat = (H - iconSize) / 2
    let iconRect = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
    let iconRadius = iconSize * 0.225
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: iconRadius, yRadius: iconRadius)

    NSGraphicsContext.saveGraphicsState()
    let iconShadow = NSShadow()
    iconShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    iconShadow.shadowOffset = NSSize(width: 0, height: -8)
    iconShadow.shadowBlurRadius = 24
    iconShadow.set()

    let iconGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.26, green: 0.30, blue: 0.50, alpha: 1.0),
        NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.26, alpha: 1.0),
    ])!
    iconGradient.draw(in: iconPath, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 광택
    NSGraphicsContext.saveGraphicsState()
    iconPath.addClip()
    let glossRect = NSRect(x: iconRect.minX, y: iconRect.midY,
                           width: iconRect.width, height: iconRect.height / 2)
    let glossGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.18),
        NSColor(calibratedWhite: 1.0, alpha: 0.0),
    ])!
    glossGradient.draw(in: glossRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 심볼 — 흰색
    if let symbol = NSImage(systemSymbolName: "cursorarrow.click.2",
                             accessibilityDescription: nil) {
        let pointSize = iconSize * 0.62
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let configured = symbol.withSymbolConfiguration(cfg) ?? symbol
        configured.isTemplate = true
        let s = configured.size
        let drawRect = NSRect(
            x: iconRect.midX - s.width / 2,
            y: iconRect.midY - s.height / 2,
            width: s.width,
            height: s.height
        )
        if let tinted = configured.copy() as? NSImage {
            tinted.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: drawRect)
        }
    }

    // 우측 텍스트 영역
    let textX: CGFloat = iconX + iconSize + 64
    let textW: CGFloat = W - textX - 96

    let titleFont = NSFont.systemFont(ofSize: 96, weight: .bold)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.white,
        .kern: -2,
    ]
    let title = NSAttributedString(string: "gesture-ex", attributes: titleAttrs)

    let titleSize = title.size()
    let titleY = H / 2 + 12
    title.draw(at: NSPoint(x: textX, y: titleY))

    let taglineFont = NSFont.systemFont(ofSize: 32, weight: .regular)
    let taglineAttrs: [NSAttributedString.Key: Any] = [
        .font: taglineFont,
        .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.70),
    ]
    let tagline = NSAttributedString(
        string: "Right-click on mouse-up · Mouse gestures for macOS",
        attributes: taglineAttrs
    )
    let taglineY = titleY - 56
    tagline.draw(at: NSPoint(x: textX, y: taglineY))

    // 하단 keyword 칩
    let chipFont = NSFont.monospacedSystemFont(ofSize: 22, weight: .medium)
    let chips = ["Chromium", "WebKit", "menu-bar", "MIT"]
    let chipBg = NSColor(calibratedWhite: 1.0, alpha: 0.10)
    let chipFg = NSColor(calibratedWhite: 1.0, alpha: 0.85)
    var chipX = textX
    let chipY: CGFloat = taglineY - 80
    for keyword in chips {
        let chipText = NSAttributedString(string: keyword, attributes: [
            .font: chipFont,
            .foregroundColor: chipFg,
        ])
        let textSize = chipText.size()
        let padH: CGFloat = 18
        let padV: CGFloat = 10
        let chipRect = NSRect(x: chipX, y: chipY,
                              width: textSize.width + padH * 2,
                              height: textSize.height + padV * 2)
        let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: 14, yRadius: 14)
        chipBg.setFill()
        chipPath.fill()
        chipText.draw(at: NSPoint(x: chipX + padH, y: chipY + padV))
        chipX += chipRect.width + 14
    }

    return true
}

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render PNG\n".data(using: .utf8)!)
    exit(2)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("✅ wrote \(outPath)")
SWIFT

echo "🔨 Compiling renderer…"
swiftc "$SWIFT_SRC" -o "$SWIFT_BIN" -framework Cocoa -O

echo "🎨 Rendering social preview…"
"$SWIFT_BIN" "$OUT_DIR/social-preview.png"

rm -rf "$DIR/.social-build"

echo ""
echo "✅ Generated: $OUT_DIR/social-preview.png (1280×640)"
echo ""
echo "Upload to GitHub:"
echo "  Repo Settings → General → Social preview → Edit → Upload an image"
echo "  → choose docs/social-preview.png → Save"
