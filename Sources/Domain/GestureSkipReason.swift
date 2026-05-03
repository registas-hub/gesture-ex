import CoreGraphics

enum GestureSkipReason {
    case notChromium(bundleID: String?, appName: String?)
    case ambiguousDirection(distance: CGFloat)
}

// MARK: - Browser Detection

/// 활성 앱이 우리가 제스처를 지원하는 웹 브라우저인지 판정한다.
/// 키보드 단축키 Cmd+[/]/T/W/R 등은 Chromium·WebKit 양쪽 엔진 모두 동일하게 동작하므로
/// 두 엔진을 함께 처리한다.
