import Foundation

struct GesturePattern: Codable, Hashable {
    let directions: [GestureDirection]

    /// 화살표 문자열 (예: "←↑↓")
    var displayString: String {
        directions.map { $0.arrow }.joined()
    }

    var isMultiSegment: Bool { directions.count >= 2 }
}

/// 패턴 → 액션 매핑 한 건의 정의 (저장 단위).
struct GestureDefinition: Codable, Hashable {
    let pattern: GesturePattern
    let action: BrowserAction
}

// MARK: - Path Analyzer

/// 좌표 path를 GesturePattern(다중 segment)로 변환한다.
/// 인접한 점들 사이의 dominant 방향이 바뀔 때마다 새 segment를 추가한다.
