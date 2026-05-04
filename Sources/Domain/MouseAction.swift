import Foundation

enum MouseScrollDirection: String, Codable, CaseIterable {
    case up, down, left, right

    var label: String {
        switch self {
        case .up:    return "Scroll Up"
        case .down:  return "Scroll Down"
        case .left:  return "Scroll Left"
        case .right: return "Scroll Right"
        }
    }

    /// 가로 스크롤(wheel2) 여부.
    var isHorizontal: Bool {
        self == .left || self == .right
    }
}

/// 제스처가 발사할 마우스 동작.
/// - scroll: 세로(wheel1) / 가로(wheel2) 휠 이벤트를 N 라인 단위로 합성
/// - middleClick: 현재 커서 위치에서 휠 버튼 클릭 (otherMouseDown/Up, button=center)
enum MouseAction: Hashable {
    case scroll(direction: MouseScrollDirection, lines: Int)
    case middleClick

    var label: String {
        switch self {
        case .scroll(let dir, let lines):
            return "\(dir.label) ×\(lines)"
        case .middleClick:
            return "Middle Click"
        }
    }
}

extension MouseAction: Codable {
    private enum Kind: String, Codable { case scroll, middleClick }
    private enum CodingKeys: String, CodingKey { case kind, direction, lines }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scroll(let dir, let lines):
            try c.encode(Kind.scroll, forKey: .kind)
            try c.encode(dir, forKey: .direction)
            try c.encode(lines, forKey: .lines)
        case .middleClick:
            try c.encode(Kind.middleClick, forKey: .kind)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .scroll:
            let dir = try c.decode(MouseScrollDirection.self, forKey: .direction)
            let lines = try c.decode(Int.self, forKey: .lines)
            self = .scroll(direction: dir, lines: lines)
        case .middleClick:
            self = .middleClick
        }
    }
}
