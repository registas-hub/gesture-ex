import AppKit

extension NSBezierPath {
    var asCGPath: CGPath {
        let path = CGMutablePath()
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo:                       path.move(to: pts[0])
            case .lineTo:                       path.addLine(to: pts[0])
            case .curveTo, .cubicCurveTo:       path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo:             path.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath:                    path.closeSubpath()
            @unknown default:                   break
            }
        }
        return path
    }
}

/// 드래그 경로를 그리는 NSView. CAShapeLayer 2개로 외곽 글로우 + 내부 라인.
/// 라이브 액션 라벨(HUD 스타일 floating tag)도 함께 호스팅한다.
/// 색상·배경·투명도는 OverlayPreferences를 매 reset() 시 다시 읽어 즉시 반영한다.
