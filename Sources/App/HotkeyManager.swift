import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let signature: OSType = OSType(0x67657820)  // "gex "
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    /// keyCode/modifiers는 Carbon의 kVK_ANSI_*, cmdKey/optionKey 등.
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        unregister()
        self.handler = action

        // Event handler 한 번만 설치 (재등록해도 재설치 안 함)
        if eventHandlerRef == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind:  UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData -> OSStatus in
                    guard let userData = userData else { return noErr }
                    let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async { mgr.handler?() }
                    return noErr
                },
                1, &spec,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
        }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, id,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr {
            self.hotKeyRef = ref
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

// MARK: - Gesture Toast (시각 피드백)

/// 화면 상단 중앙에 짧게 떴다 사라지는 floating panel.
/// 제스처 인식·실행 여부를 즉시 사용자에게 알려 디버깅·UX 양쪽에 도움이 된다.
