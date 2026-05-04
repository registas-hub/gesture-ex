import Foundation

struct CustomGestureMappings {
    private static let key = "customGestures"

    static var all: [GestureDefinition] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let defs = try? JSONDecoder().decode([GestureDefinition].self, from: data) else {
                return []
            }
            return defs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    static func upsert(_ def: GestureDefinition) {
        var current = all
        current.removeAll { $0.pattern == def.pattern }
        current.append(def)
        all = current
    }

    static func remove(pattern: GesturePattern) {
        var current = all
        current.removeAll { $0.pattern == pattern }
        all = current
    }

    static func match(_ pattern: GesturePattern) -> GestureAction? {
        return all.first(where: { $0.pattern == pattern })?.action
    }

    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Settings Window가 Custom Gesture 변경을 감지해 list refresh 하기 위한 노티피케이션 이름.
extension Notification.Name {
    static let customGesturesChanged = Notification.Name("customGesturesChanged")
}

// MARK: - Gesture → Action Mapping

/// 방향 → 액션 매핑을 UserDefaults에 영속화한다.
/// SettingsWindow가 setAction으로 갱신하면 즉시 다음 제스처에 반영된다.
