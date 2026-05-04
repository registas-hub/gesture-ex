import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// HotkeyPreferences가 변할 때 발사. AppDelegate가 hotkey를 재등록하고 메뉴를 갱신한다.
    static let toggleHotkeyChanged = Notification.Name("toggleHotkeyChanged")

    /// hotkey 등록 결과 알림 (userInfo["ok"] = Bool).
    /// 다른 앱이 같은 hotkey를 점유 중이면 ok=false — SettingsWindow가 이걸 받아 충돌을 사용자에게 알린다.
    static let toggleHotkeyRegistrationResult = Notification.Name("toggleHotkeyRegistrationResult")
}

/// "right-click on mouse-up" 토글용 글로벌 hotkey 설정 저장소.
///
/// 단축키 모델은 `KeyShortcut`(Domain/KeyShortcut.swift)을 그대로 재사용한다 —
/// 같은 keyCode/flags/displayKey 세트를 두 타입으로 가지면 한쪽 진화 시 정합성이 깨지기 쉽다.
/// Carbon API용 modifier 변환은 `KeyShortcut.carbonModifiers` extension에 둔다.
struct HotkeyPreferences {
    private static let kBinding = "hotkey.toggle.binding.v1"
    private static let kEnabled = "hotkey.toggle.enabled"

    static let defaultBinding = KeyShortcut(
        keyCode: UInt16(kVK_ANSI_G),
        cgFlags: [.maskCommand, .maskAlternate],
        displayKey: "G"
    )

    static var binding: KeyShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: kBinding),
                  let decoded = try? JSONDecoder().decode(KeyShortcut.self, from: data) else {
                return defaultBinding
            }
            return decoded
        }
        set {
            // encode 실패 시엔 옛 값이 디스크에 남는데 알림만 발사하면 옵저버가
            // "변경 안 된 변경"을 처리한다. 가드: 같은 값이면 일찍 종료, 인코딩 실패 시 종료.
            guard newValue != binding else { return }
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: kBinding)
            NotificationCenter.default.post(name: .toggleHotkeyChanged, object: nil)
        }
    }

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: kEnabled) == nil { return true }
            return UserDefaults.standard.bool(forKey: kEnabled)
        }
        set {
            guard newValue != isEnabled else { return }
            UserDefaults.standard.set(newValue, forKey: kEnabled)
            NotificationCenter.default.post(name: .toggleHotkeyChanged, object: nil)
        }
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: kBinding)
        UserDefaults.standard.removeObject(forKey: kEnabled)
        NotificationCenter.default.post(name: .toggleHotkeyChanged, object: nil)
    }
}
