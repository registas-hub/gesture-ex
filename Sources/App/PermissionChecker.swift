import AppKit
import ApplicationServices
import IOKit.hid

/// Accessibility / Input Monitoring 두 권한의 부여 상태를 조회한다.
/// EventTapController.start()는 두 권한이 모두 있어야 성공하므로,
/// 사용자에게 어느 쪽이 부족한지 분리해 알리려면 두 값을 따로 검사해야 한다.
enum PermissionChecker {

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var inputMonitoringGranted: Bool {
        // listenEvent 액세스 — HID 이벤트(키/마우스) 청취 권한.
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static var allGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }
}
