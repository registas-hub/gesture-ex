import AppKit

struct GestureRecognizer {
    /// 의도적 제스처로 인정할 최소 변위(포인트). 이 미만은 제스처 아님.
    static let minDistance: CGFloat = 20.0
    /// 우세 축 판정 비율 — 한 축이 다른 축의 1.5배 이상이어야 인정.
    /// 애매한 대각선(예: ↗︎)은 nil을 반환해 사용자에게 일반 클릭 처리로 폴백한다.
    static let dominanceRatio: CGFloat = 1.5

    /// CGEvent 좌표계(top-left origin, y가 아래로 증가) 기준의 두 점에서 방향을 인식한다.
    /// NSEvent.mouseLocation(bottom-left origin)을 넘길 때는 호출자가 y를 뒤집어야 한다 —
    /// `nsPointToCG(_:)`를 사용한다.
    static func recognize(from start: CGPoint, to end: CGPoint) -> GestureDirection? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let absDx = abs(dx)
        let absDy = abs(dy)

        if max(absDx, absDy) < minDistance { return nil }

        if absDx > absDy * dominanceRatio {
            return dx < 0 ? .left : .right
        } else if absDy > absDx * dominanceRatio {
            // CGEvent 좌표계: y가 증가할수록 화면 아래
            return dy < 0 ? .up : .down
        }
        return nil
    }

    /// NSEvent.mouseLocation(글로벌, bottom-left origin)을 CGEvent 좌표계로 변환한다.
    /// 메뉴바가 있는 primary screen의 높이만큼 y를 뒤집는다 — 멀티 모니터에서도 동일 공식 유효.
    static func nsPointToCG(_ p: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}

// MARK: - Multi-segment Gesture Pattern

/// 다중 segment 제스처 패턴. 길이 1은 단일 방향(←/→/↑/↓)과 동일.
