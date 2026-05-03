import Foundation

struct GestureMappings {
    private static func key(_ d: GestureDirection) -> String {
        return "gesture.mapping.\(d.name.lowercased())"
    }

    static let defaults: [GestureDirection: BrowserAction] = [
        .left:  .back,
        .right: .forward,
        .up:    .scrollTop,
        .down:  .scrollBottom,
    ]

    static func action(for direction: GestureDirection) -> BrowserAction {
        if let raw = UserDefaults.standard.string(forKey: key(direction)),
           let action = BrowserAction(rawValue: raw) {
            return action
        }
        return defaults[direction] ?? .disabled
    }

    static func setAction(_ action: BrowserAction, for direction: GestureDirection) {
        UserDefaults.standard.set(action.rawValue, forKey: key(direction))
    }

    /// 모든 매핑을 기본값으로 복원
    static func resetToDefaults() {
        for direction in GestureDirection.allCases {
            UserDefaults.standard.removeObject(forKey: key(direction))
        }
    }
}

// MARK: - Live Overlay Preferences

/// 라이브 트레일/라벨 오버레이의 시각 설정을 UserDefaults에 영속화한다.
/// 변경은 다음 우클릭 드래그부터 즉시 반영된다.
