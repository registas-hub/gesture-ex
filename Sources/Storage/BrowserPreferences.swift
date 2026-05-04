import Foundation

/// BrowserDetector 카탈로그 항목 중 사용자가 끈 bundle ID 집합을 영속화한다.
/// disabled 셋만 저장하므로 카탈로그가 갱신되어도 새 항목은 자동으로 enabled.
struct BrowserPreferences {
    private static let key = "browserPrefs.disabledBundleIDs"

    static var disabledBundleIDs: Set<String> {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(arr)
        }
        set {
            guard let data = try? JSONEncoder().encode(Array(newValue).sorted()) else { return }
            UserDefaults.standard.set(data, forKey: key)
            NotificationCenter.default.post(name: .browserPrefsChanged, object: nil)
        }
    }

    static func isEnabled(_ bundleID: String) -> Bool {
        !disabledBundleIDs.contains(bundleID)
    }

    static func setEnabled(_ enabled: Bool, for bundleID: String) {
        var current = disabledBundleIDs
        if enabled {
            current.remove(bundleID)
        } else {
            current.insert(bundleID)
        }
        disabledBundleIDs = current
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: .browserPrefsChanged, object: nil)
    }
}

extension Notification.Name {
    static let browserPrefsChanged = Notification.Name("browserPrefsChanged")
}
