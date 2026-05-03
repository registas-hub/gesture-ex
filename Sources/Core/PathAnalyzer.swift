import CoreGraphics

struct PathAnalyzer {
    /// 새 segment로 인정할 최소 거리(포인트). 작은 떨림은 무시.
    static let minSegmentDistance: CGFloat = 30.0

    /// CGEvent 좌표계 path를 받아 패턴을 추출한다. 좌표가 NSEvent라면 호출자가 변환할 것.
    static func analyze(path: [CGPoint]) -> GesturePattern? {
        guard path.count >= 2 else { return nil }

        var segments: [GestureDirection] = []
        var segmentStart = path[0]

        for i in 1..<path.count {
            let pt = path[i]
            let dx = pt.x - segmentStart.x
            let dy = pt.y - segmentStart.y
            let absDx = abs(dx)
            let absDy = abs(dy)
            let dist = (dx * dx + dy * dy).squareRoot()

            guard dist >= minSegmentDistance else { continue }

            let newDir: GestureDirection?
            if absDx > absDy * GestureRecognizer.dominanceRatio {
                newDir = dx < 0 ? .left : .right
            } else if absDy > absDx * GestureRecognizer.dominanceRatio {
                newDir = dy < 0 ? .up : .down
            } else {
                newDir = nil  // 사선 — 더 끌도록 대기
            }

            if let d = newDir {
                if segments.last != d {
                    segments.append(d)
                }
                // 측정 기준점을 갱신 → 다음 segment는 여기서부터의 변위로 측정
                segmentStart = pt
            }
        }

        return segments.isEmpty ? nil : GesturePattern(directions: segments)
    }
}

// MARK: - Custom Gesture Storage

/// 사용자가 추가한 다중 segment 제스처 정의들을 UserDefaults에 JSON으로 영속화한다.
