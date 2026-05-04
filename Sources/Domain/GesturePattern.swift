import Foundation

struct GesturePattern: Codable, Hashable {
    let directions: [GestureDirection]

    /// 화살표 문자열 (예: "←↑↓")
    var displayString: String {
        directions.map { $0.arrow }.joined()
    }

    var isMultiSegment: Bool { directions.count >= 2 }
}

/// 제스처가 발사할 액션. 빌트인 BrowserAction이거나 사용자 정의 키보드 단축키.
enum GestureAction: Hashable {
    case builtin(BrowserAction)
    case shortcut(KeyShortcut)

    /// 사용자에게 보여줄 액션 이름. shortcut은 "Custom: ⇧⌘A" 형식.
    var label: String {
        switch self {
        case .builtin(let action):
            return action.label
        case .shortcut(let s):
            return "Custom: \(s.displayString)"
        }
    }

    /// 단축키 표시 문자열만 추출. 빌트인은 자체 단축키, custom은 displayString.
    var shortcutLabel: String? {
        switch self {
        case .builtin(let action):
            return action.shortcutLabel
        case .shortcut(let s):
            return s.displayString
        }
    }

    /// 매핑이 의도적으로 비활성된 상태인지. EventTapController가 컨텍스트 메뉴 분기에 사용.
    var isDisabled: Bool {
        if case .builtin(.disabled) = self { return true }
        return false
    }
}

extension GestureAction: Codable {
    private enum Kind: String, Codable {
        case builtin, shortcut
    }
    private enum CodingKeys: String, CodingKey {
        case kind, builtin, shortcut
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtin(let a):
            try c.encode(Kind.builtin, forKey: .kind)
            try c.encode(a, forKey: .builtin)
        case .shortcut(let s):
            try c.encode(Kind.shortcut, forKey: .kind)
            try c.encode(s, forKey: .shortcut)
        }
    }

    init(from decoder: Decoder) throws {
        // 신 포맷: { "kind": "...", ... }
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let kind = try? c.decode(Kind.self, forKey: .kind) {
            switch kind {
            case .builtin:
                self = .builtin(try c.decode(BrowserAction.self, forKey: .builtin))
            case .shortcut:
                self = .shortcut(try c.decode(KeyShortcut.self, forKey: .shortcut))
            }
            return
        }
        // 구 포맷 호환: BrowserAction.rawValue 단일 String.
        let single = try decoder.singleValueContainer()
        let raw = try single.decode(String.self)
        guard let action = BrowserAction(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Unknown BrowserAction raw value: \(raw)"
            )
        }
        self = .builtin(action)
    }
}

/// 패턴 → 액션 매핑 한 건의 정의 (저장 단위).
struct GestureDefinition: Codable, Hashable {
    let pattern: GesturePattern
    let action: GestureAction
}

// MARK: - Path Analyzer

/// 좌표 path를 GesturePattern(다중 segment)로 변환한다.
/// 인접한 점들 사이의 dominant 방향이 바뀔 때마다 새 segment를 추가한다.
