import AppKit
import ApplicationServices
import IOKit.hid

/// 사용자 권한 부여 상태를 3-state로 표현한다.
/// `denied`와 `notDetermined`는 사용자가 시스템 설정에서 취해야 할 다음 행동이 다르므로
/// (전자는 토글을 켜기, 후자는 처음 권한 다이얼로그 띄우기) UI에서 구분해 보여준다.
enum PermissionStatus {
    case granted
    case denied
    /// 사용자가 아직 권한 다이얼로그를 본 적이 없는 상태.
    /// `IOHIDCheckAccess`는 이 케이스를 별도로 반환하지만, `AXIsProcessTrusted`는 false 하나로 합치므로
    /// Accessibility 쪽은 이 케이스를 노출하지 않는다.
    case notDetermined

    var isGranted: Bool { self == .granted }

    /// 메뉴/알림에 표시할 1글자 마크.
    var glyph: String {
        switch self {
        case .granted:       return "✓"
        case .denied:        return "✗"
        case .notDetermined: return "?"
        }
    }
}

/// Accessibility / Input Monitoring 두 권한의 부여 상태를 조회한다.
/// EventTapController.start()는 두 권한이 모두 granted여야 성공하므로,
/// 사용자에게 어느 쪽이 부족한지 분리해 알리려면 두 값을 따로 검사해야 한다.
enum PermissionChecker {

    /// `AXIsProcessTrusted()`는 trusted/false 두 값만 반환하므로 notDetermined는 표현 불가능.
    /// 시스템이 단순 미부여 상태도 false로 합쳐서 노출한다.
    static var accessibility: PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// `IOHIDCheckAccess`는 granted / denied / unknown 3-state를 반환한다.
    /// unknown은 "사용자가 아직 권한 다이얼로그를 한 번도 열어본 적 없음" — 이 경우엔
    /// 시스템 설정으로 deep-link해도 항목이 비어 있을 수 있으므로 사용자 안내 텍스트가 달라진다.
    static var inputMonitoring: PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied:  return .denied
        default:                      return .notDetermined
        }
    }

    static var allGranted: Bool {
        accessibility.isGranted && inputMonitoring.isGranted
    }

    // 기존 호출부 호환용 — 이전 Bool 인터페이스를 그대로 유지.
    static var accessibilityGranted: Bool { accessibility.isGranted }
    static var inputMonitoringGranted: Bool { inputMonitoring.isGranted }
}
