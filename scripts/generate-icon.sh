#!/bin/bash
# Resources/AppIcon.icns 일회성 생성기.
# squircle 배경 + SF Symbol cursorarrow.click.2를 합성해 .iconset → .icns로 빌드.
# 결과물(Resources/AppIcon.icns)은 리포에 커밋되며, build.sh가 번들로 복사한다.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$DIR/Resources"
ICONSET="$DIR/.icon-build/AppIcon.iconset"
SWIFT_SRC="$DIR/.icon-build/render.swift"
SWIFT_BIN="$DIR/.icon-build/render"

rm -rf "$DIR/.icon-build"
mkdir -p "$ICONSET" "$OUT_DIR"

cat > "$SWIFT_SRC" <<'SWIFT'
import AppKit

// 출력 경로 = argv[1] (icon_<W>x<H>{@2x}.png 파일들이 저장될 디렉토리)
guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: render <iconset-dir>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = CommandLine.arguments[1]

// (point-size, scale) — Apple iconset 표준 10종
let entries: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

func render(pixelSize: CGFloat) -> Data? {
    let size = NSSize(width: pixelSize, height: pixelSize)
    let img = NSImage(size: size, flipped: false) { rect in
        // Big Sur 이후 macOS 앱 아이콘은 안전 영역(약 80%)에만 그린다.
        let inset = pixelSize * 0.10
        let bgRect = rect.insetBy(dx: inset, dy: inset)
        let radius = bgRect.width * 0.225  // Big Sur squircle radius

        // 배경: 진한 인디고→차콜 수직 그라데이션
        let path = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.42, alpha: 1.0),
            NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.20, alpha: 1.0),
        ])!
        gradient.draw(in: path, angle: -90)

        // 미세 광택 — 상단에 흰색 하이라이트 (오버레이)
        let glossPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
        glossPath.addClip()
        let glossRect = NSRect(x: bgRect.minX, y: bgRect.midY,
                                width: bgRect.width, height: bgRect.height / 2)
        NSColor(calibratedWhite: 1.0, alpha: 0.06).setFill()
        glossPath.fill()
        let glossGradient = NSGradient(colors: [
            NSColor(calibratedWhite: 1.0, alpha: 0.18),
            NSColor(calibratedWhite: 1.0, alpha: 0.0),
        ])!
        glossGradient.draw(in: glossRect, angle: -90)

        // 심볼: cursorarrow.click.2 — 흰색, 배경 안전 영역의 ~62%
        guard let symbol = NSImage(
            systemSymbolName: "cursorarrow.click.2",
            accessibilityDescription: nil
        ) else { return true }

        let pointSize = bgRect.width * 0.62
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let configured = symbol.withSymbolConfiguration(cfg) ?? symbol

        // 흰색 틴트 — template으로 그리고 색을 칠한다
        configured.isTemplate = true
        let s = configured.size
        let drawRect = NSRect(
            x: bgRect.midX - s.width / 2,
            y: bgRect.midY - s.height / 2,
            width: s.width,
            height: s.height
        )

        // 부드러운 drop shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -pixelSize * 0.01)
        shadow.shadowBlurRadius = pixelSize * 0.025
        NSGraphicsContext.saveGraphicsState()
        shadow.set()

        // template 이미지에 색 입히기
        if let tinted = configured.copy() as? NSImage {
            tinted.lockFocus()
            NSColor.white.set()
            let imgRect = NSRect(origin: .zero, size: tinted.size)
            imgRect.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: drawRect)
        } else {
            configured.draw(in: drawRect)
        }
        NSGraphicsContext.restoreGraphicsState()
        return true
    }

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = size
    return rep.representation(using: .png, properties: [:])
}

for (point, scale) in entries {
    let pixels = CGFloat(point * scale)
    guard let data = render(pixelSize: pixels) else {
        FileHandle.standardError.write("failed to render \(point)x\(point)@\(scale)\n".data(using: .utf8)!)
        exit(2)
    }
    let suffix = scale == 2 ? "@2x" : ""
    let path = "\(outDir)/icon_\(point)x\(point)\(suffix).png"
    try data.write(to: URL(fileURLWithPath: path))
}

print("✅ rendered \(entries.count) png(s) into \(outDir)")
SWIFT

echo "🔨 Compiling renderer…"
swiftc "$SWIFT_SRC" -o "$SWIFT_BIN" -framework Cocoa -O

echo "🎨 Rendering iconset…"
"$SWIFT_BIN" "$ICONSET"

echo "📦 Building .icns…"
iconutil -c icns "$ICONSET" -o "$OUT_DIR/AppIcon.icns"

rm -rf "$DIR/.icon-build"

echo ""
echo "✅ Generated: $OUT_DIR/AppIcon.icns"
echo "   (commit this file; build.sh will copy it into the bundle.)"
