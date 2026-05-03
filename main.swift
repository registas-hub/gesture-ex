import Cocoa
import CoreGraphics
import ServiceManagement
import Carbon.HIToolbox

// MARK: - Gesture Domain Types

enum GestureDirection: Int, CaseIterable, Codable {
    case left = 0, right, up, down

    var arrow: String {
        switch self {
        case .left:  return "←"
        case .right: return "→"
        case .up:    return "↑"
        case .down:  return "↓"
        }
    }

    var name: String {
        switch self {
        case .left:  return "Left"
        case .right: return "Right"
        case .up:    return "Up"
        case .down:  return "Down"
        }
    }
}

enum BrowserAction: String, CaseIterable, Codable {
    case disabled
    case back
    case forward
    case reload
    case hardReload
    case stop
    case newTab
    case closeTab
    case reopenTab
    case nextTab
    case prevTab
    case newWindow
    case scrollTop
    case scrollBottom
    case findInPage
    case zoomIn
    case zoomOut
    case resetZoom

    /// 발사할 가상 키코드. nil이면 액션 비활성(disabled).
    var keyCode: CGKeyCode? {
        switch self {
        case .disabled:     return nil
        case .back:         return 0x21  // [
        case .forward:      return 0x1E  // ]
        case .reload:       return 0x0F  // R
        case .hardReload:   return 0x0F  // Shift+R
        case .stop:         return 0x2F  // . (period)
        case .newTab:       return 0x11  // T
        case .closeTab:     return 0x0D  // W
        case .reopenTab:    return 0x11  // Shift+T
        case .nextTab:      return 0x7C  // Right (Cmd+Option+Right)
        case .prevTab:      return 0x7B  // Left  (Cmd+Option+Left)
        case .newWindow:    return 0x2D  // N
        case .scrollTop:    return 0x73  // Home
        case .scrollBottom: return 0x77  // End
        case .findInPage:   return 0x03  // F
        case .zoomIn:       return 0x18  // = (Cmd++)
        case .zoomOut:      return 0x1B  // - (Cmd+-)
        case .resetZoom:    return 0x1D  // 0
        }
    }

    var flags: CGEventFlags {
        switch self {
        case .disabled:
            return []
        case .back, .forward, .reload, .stop, .newTab, .closeTab, .newWindow,
             .findInPage, .zoomIn, .zoomOut, .resetZoom:
            return .maskCommand
        case .hardReload, .reopenTab:
            return [.maskCommand, .maskShift]
        case .nextTab, .prevTab:
            return [.maskCommand, .maskAlternate]
        case .scrollTop, .scrollBottom:
            return []  // Home/End — 보조 키 없이도 페이지 이동
        }
    }

    var label: String {
        switch self {
        case .disabled:     return "— (Disabled)"
        case .back:         return "Back"
        case .forward:      return "Forward"
        case .reload:       return "Reload"
        case .hardReload:   return "Hard Reload"
        case .stop:         return "Stop Loading"
        case .newTab:       return "New Tab"
        case .closeTab:     return "Close Tab"
        case .reopenTab:    return "Reopen Closed Tab"
        case .nextTab:      return "Next Tab"
        case .prevTab:      return "Previous Tab"
        case .newWindow:    return "New Window"
        case .scrollTop:    return "Scroll to Top"
        case .scrollBottom: return "Scroll to Bottom"
        case .findInPage:   return "Find in Page"
        case .zoomIn:       return "Zoom In"
        case .zoomOut:      return "Zoom Out"
        case .resetZoom:    return "Reset Zoom"
        }
    }
}

/// 의도적 드래그였으나 제스처 실행으로 이어지지 못한 사유.
/// AppDelegate가 이를 받아 사용자에게 토스트로 표시한다.
enum GestureSkipReason {
    case notChromium(bundleID: String?, appName: String?)
    case ambiguousDirection(distance: CGFloat)
}

// MARK: - Browser Detection

/// 활성 앱이 우리가 제스처를 지원하는 웹 브라우저인지 판정한다.
/// 키보드 단축키 Cmd+[/]/T/W/R 등은 Chromium·WebKit 양쪽 엔진 모두 동일하게 동작하므로
/// 두 엔진을 함께 처리한다.
struct BrowserDetector {
    /// 알려진 Chromium 기반 브라우저 bundle ID.
    static let chromiumBundles: Set<String> = [
        // Chromium 공식 오픈소스 빌드
        "org.chromium.Chromium",
        // Google Chrome (모든 채널)
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        // Microsoft Edge (모든 채널)
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary",
        "com.microsoft.edgemac.Dev",
        // Brave
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        // The Browser Company
        "company.thebrowser.Browser",  // Arc
        "company.thebrowser.dia",      // Dia
        // Naver Whale
        "com.naver.Whale",
        // Vivaldi
        "com.vivaldi.Vivaldi",
        // Opera (모든 변형)
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.operasoftware.OperaNext",
        // 기타 Chromium 기반
        "com.coccoc.coccoc",
        "ru.yandex.desktop.yandex-browser",
    ]

    /// WebKit 기반(Safari 엔진 계열) 브라우저 bundle ID.
    static let webkitBundles: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.kagi.kagimacOS",       // Orion (Kagi)
        "io.kagi.orion",            // Orion (alternate ID)
        "com.kagi.orion",
    ]

    static let bundles: Set<String> = chromiumBundles.union(webkitBundles)

    static var isFrontmost: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return bundles.contains(bundleID)
    }

    /// 현재 활성 브라우저의 엔진을 식별 (메뉴 표시·디버깅용)
    static var frontmostEngine: String? {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }
        if chromiumBundles.contains(bundleID) { return "Chromium" }
        if webkitBundles.contains(bundleID) { return "WebKit" }
        return nil
    }
}

// MARK: - Gesture Recognition

struct GestureRecognizer {
    /// 의도적 제스처로 인정할 최소 변위(포인트). 이 미만은 제스처 아님.
    static let minDistance: CGFloat = 20.0
    /// 우세 축 판정 비율 — 한 축이 다른 축의 1.5배 이상이어야 인정.
    /// 애매한 대각선(예: ↗︎)은 nil을 반환해 사용자에게 일반 클릭 처리로 폴백한다.
    static let dominanceRatio: CGFloat = 1.5

    /// CGEvent 좌표계(top-left origin, y가 아래로 증가) 기준의 두 점에서 방향을 인식한다.
    /// NSEvent.mouseLocation(bottom-left origin)을 넘길 때는 호출자가 y를 뒤집어야 한다 —
    /// `nsPointToCG(_:)`를 사용한다.
    static func recognize(from start: CGPoint, to end: CGPoint) -> GestureDirection? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let absDx = abs(dx)
        let absDy = abs(dy)

        if max(absDx, absDy) < minDistance { return nil }

        if absDx > absDy * dominanceRatio {
            return dx < 0 ? .left : .right
        } else if absDy > absDx * dominanceRatio {
            // CGEvent 좌표계: y가 증가할수록 화면 아래
            return dy < 0 ? .up : .down
        }
        return nil
    }

    /// NSEvent.mouseLocation(글로벌, bottom-left origin)을 CGEvent 좌표계로 변환한다.
    /// 메뉴바가 있는 primary screen의 높이만큼 y를 뒤집는다 — 멀티 모니터에서도 동일 공식 유효.
    static func nsPointToCG(_ p: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}

// MARK: - Multi-segment Gesture Pattern

/// 다중 segment 제스처 패턴. 길이 1은 단일 방향(←/→/↑/↓)과 동일.
struct GesturePattern: Codable, Hashable {
    let directions: [GestureDirection]

    /// 화살표 문자열 (예: "←↑↓")
    var displayString: String {
        directions.map { $0.arrow }.joined()
    }

    var isMultiSegment: Bool { directions.count >= 2 }
}

/// 패턴 → 액션 매핑 한 건의 정의 (저장 단위).
struct GestureDefinition: Codable, Hashable {
    let pattern: GesturePattern
    let action: BrowserAction
}

// MARK: - Path Analyzer

/// 좌표 path를 GesturePattern(다중 segment)로 변환한다.
/// 인접한 점들 사이의 dominant 방향이 바뀔 때마다 새 segment를 추가한다.
struct PathAnalyzer {
    /// 새 segment로 인정할 최소 거리(포인트). 작은 떨림은 무시.
    static let minSegmentDistance: CGFloat = 30.0

    /// CGEvent 좌표계 path를 받아 패턴을 추출한다. 좌표가 NSEvent라면 호출자가 변환할 것.
    static func analyze(path: [CGPoint]) -> GesturePattern? {
        guard path.count >= 2 else { return nil }

        var segments: [GestureDirection] = []
        var segmentStart = path[0]

        for i in 1..<path.count {
            let pt = path[i]
            let dx = pt.x - segmentStart.x
            let dy = pt.y - segmentStart.y
            let absDx = abs(dx)
            let absDy = abs(dy)
            let dist = (dx * dx + dy * dy).squareRoot()

            guard dist >= minSegmentDistance else { continue }

            let newDir: GestureDirection?
            if absDx > absDy * GestureRecognizer.dominanceRatio {
                newDir = dx < 0 ? .left : .right
            } else if absDy > absDx * GestureRecognizer.dominanceRatio {
                newDir = dy < 0 ? .up : .down
            } else {
                newDir = nil  // 사선 — 더 끌도록 대기
            }

            if let d = newDir {
                if segments.last != d {
                    segments.append(d)
                }
                // 측정 기준점을 갱신 → 다음 segment는 여기서부터의 변위로 측정
                segmentStart = pt
            }
        }

        return segments.isEmpty ? nil : GesturePattern(directions: segments)
    }
}

// MARK: - Custom Gesture Storage

/// 사용자가 추가한 다중 segment 제스처 정의들을 UserDefaults에 JSON으로 영속화한다.
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

    static func match(_ pattern: GesturePattern) -> BrowserAction? {
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
struct OverlayPreferences {
    private static let kTrailColor      = "overlay.trailColor"
    private static let kBackgroundColor = "overlay.backgroundColor"
    private static let kBackgroundOpacity = "overlay.backgroundOpacity"
    private static let kShowActionLabel  = "overlay.showActionLabel"
    private static let kLingerDuration   = "overlay.lingerDuration"

    /// 트레일 라인(주 라인) 색상 — 외곽 글로우는 alpha 0.35로 자동 파생
    static var trailColor: NSColor {
        get { loadColor(kTrailColor) ?? .systemBlue }
        set { saveColor(newValue, key: kTrailColor) }
    }

    /// 액션 라벨의 배경 색상 (RGB; alpha는 backgroundOpacity로 별도 관리)
    static var backgroundColor: NSColor {
        get { loadColor(kBackgroundColor) ?? NSColor(white: 0.08, alpha: 1.0) }
        set { saveColor(newValue, key: kBackgroundColor) }
    }

    /// 라벨 배경의 투명도 (0.0 ~ 1.0)
    static var backgroundOpacity: Double {
        get {
            if UserDefaults.standard.object(forKey: kBackgroundOpacity) == nil { return 0.85 }
            return UserDefaults.standard.double(forKey: kBackgroundOpacity)
        }
        set { UserDefaults.standard.set(newValue, forKey: kBackgroundOpacity) }
    }

    /// 액션 라벨 자체의 표시 여부 (트레일 라인은 별개로 항상 표시)
    static var showActionLabel: Bool {
        get {
            if UserDefaults.standard.object(forKey: kShowActionLabel) == nil { return true }
            return UserDefaults.standard.bool(forKey: kShowActionLabel)
        }
        set { UserDefaults.standard.set(newValue, forKey: kShowActionLabel) }
    }

    /// 마우스 떼는 시점부터 트레일+라벨이 fade-out 되기까지의 시간(초).
    /// 짧으면 즉시 사라짐, 길면 액션 인식 결과를 더 오래 확인 가능.
    static var lingerDuration: Double {
        get {
            if UserDefaults.standard.object(forKey: kLingerDuration) == nil { return 0.22 }
            return UserDefaults.standard.double(forKey: kLingerDuration)
        }
        set { UserDefaults.standard.set(newValue, forKey: kLingerDuration) }
    }

    static func resetToDefaults() {
        for key in [kTrailColor, kBackgroundColor, kBackgroundOpacity, kShowActionLabel, kLingerDuration] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: Color persistence (NSKeyedArchiver)

    private static func loadColor(_ key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
            return nil
        }
        return color
    }

    private static func saveColor(_ color: NSColor, key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// 사람 눈 luminance 가중평균으로 배경 대비 가독성 좋은 텍스트 색을 결정.
fileprivate func textColorOnBackground(_ bg: NSColor) -> NSColor {
    let c = bg.usingColorSpace(.sRGB) ?? bg
    let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    return lum > 0.55 ? NSColor.black : NSColor.white
}

// MARK: - Action Execution

struct ActionExecutor {
    /// 키보드 단축키를 합성해서 활성 앱에 전달한다.
    /// HID tap 위치에 post → 모든 input 처리 레이어를 정상적으로 통과한다.
    /// disabled 액션은 noop.
    static func execute(_ action: BrowserAction) {
        guard let keyCode = action.keyCode else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source,
                                  virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                                virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = action.flags
        up.flags = action.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

// MARK: - Event Tap Controller

/// HID 레벨 CGEventTap을 관리한다.
/// 1) Chromium 활성 + 드래그 ≥ minDistance + 인식 가능한 방향 → 제스처 액션 실행, 우버튼 이벤트 일체 폐기
/// 2) 그 외 → 원본 down을 up 위치로 옮겨 재발사 (메뉴를 떼는 위치에 띄움)
final class EventTapController {

    static let shared = EventTapController()

    private static let SYNTHETIC_TAG: Int64 = 0x4332_4F55_5055_5000  // "C2OUPUP\0"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingDown: CGEvent?

    private(set) var isRunning: Bool = false

    /// 제스처 실행 직후 호출되는 콜백 (UI 스레드에서 호출됨).
    /// 단일 방향이면 `pattern.directions.count == 1`, 다중 segment는 그 이상.
    var onGestureExecuted: ((GesturePattern, BrowserAction) -> Void)?

    /// 의도적 드래그(>= 10px)였으나 제스처가 실행되지 못했을 때 호출 (UI 스레드).
    /// 사용자에게 "왜 안 됐는지"를 즉시 알려주는 진단 채널.
    var onGestureSkipped: ((GestureSkipReason) -> Void)?

    /// 우클릭 누른 순간 호출 (UI 스레드). AppDelegate가 트레일 오버레이를 띄운다.
    var onRightDown: (() -> Void)?

    /// 우클릭 뗀 순간 호출 (UI 스레드). 트레일 오버레이를 페이드아웃.
    var onRightUp: (() -> Void)?

    /// 제스처 시도로 간주할 최소 드래그 거리. 이 미만은 단순 클릭으로 분류해
    /// 실패 토스트를 띄우지 않는다(불필요한 노이즈 방지).
    private static let GESTURE_ATTEMPT_THRESHOLD: CGFloat = 10.0

    /// 우클릭 → mouse-up 변환 활성화 여부. 메뉴 토글의 주 상태값.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "rightClickOnUp.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "rightClickOnUp.enabled") }
    }

    /// Chromium 엔진 브라우저(Chrome/Edge/Brave/Arc/...)에서 제스처 활성화 여부 (기본 ON).
    var chromiumGesturesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "gestures.chromium.enabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "gestures.chromium.enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "gestures.chromium.enabled") }
    }

    /// WebKit 엔진 브라우저(Safari/Safari TP/Orion)에서 제스처 활성화 여부 (기본 ON).
    var webkitGesturesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "gestures.webkit.enabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "gestures.webkit.enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "gestures.webkit.enabled") }
    }

    /// 현재 frontmost 앱의 엔진을 기준으로 제스처가 활성인지 통합 판정.
    var gesturesEnabledForFrontmost: Bool {
        switch BrowserDetector.frontmostEngine {
        case "Chromium": return chromiumGesturesEnabled
        case "WebKit":   return webkitGesturesEnabled
        default:         return false
        }
    }

    /// EventTapController가 mouse-up 시점에 호출해 다중 segment 패턴 분석에 사용할 path 공급자.
    /// AppDelegate에서 GestureTrailWindow와 연결한다.
    var pathProvider: (() -> [CGPoint])?

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        self.tap = newTap
        self.runLoopSource = source
        self.isRunning = true
        return true
    }

    func stop() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        self.tap = nil
        self.runLoopSource = nil
        self.pendingDown = nil
        self.isRunning = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // 합성 이벤트는 그대로 통과 (재진입 방지)
        if event.getIntegerValueField(.eventSourceUserData) == Self.SYNTHETIC_TAG {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .rightMouseDown:
            if let copy = event.copy() {
                copy.setIntegerValueField(.eventSourceUserData, value: Self.SYNTHETIC_TAG)
                pendingDown = copy
            }
            // 트레일 오버레이 띄우기
            let downCb = onRightDown
            DispatchQueue.main.async { downCb?() }
            return nil  // 원본 down은 삼킴

        case .rightMouseUp:
            // 어떤 분기로 가든 트레일은 마무리한다
            let upCb = onRightUp
            DispatchQueue.main.async { upCb?() }

            guard let down = pendingDown else {
                return Unmanaged.passUnretained(event)
            }
            defer { pendingDown = nil }

            let downLoc = down.location
            let upLoc = event.location
            let dx = upLoc.x - downLoc.x
            let dy = upLoc.y - downLoc.y
            let distance = (dx * dx + dy * dy).squareRoot()

            // 짧은 클릭(< 10px): 제스처 분기 없이 바로 메뉴 띄움
            guard distance >= Self.GESTURE_ATTEMPT_THRESHOLD else {
                down.location = upLoc
                down.post(tap: .cghidEventTap)
                return Unmanaged.passUnretained(event)
            }

            // 의도적 드래그였음 — 엔진별 토글 + 활성 앱이 지원 브라우저인지 확인
            guard gesturesEnabledForFrontmost else {
                let app = NSWorkspace.shared.frontmostApplication
                let cb = onGestureSkipped
                DispatchQueue.main.async {
                    cb?(.notChromium(bundleID: app?.bundleIdentifier, appName: app?.localizedName))
                }
                down.location = upLoc
                down.post(tap: .cghidEventTap)
                return Unmanaged.passUnretained(event)
            }

            // ▶ 패턴 인식: 다중 segment 우선, 단일 방향은 fallback
            let path = pathProvider?() ?? [downLoc, upLoc]
            let pattern = PathAnalyzer.analyze(path: path)
                ?? GestureRecognizer.recognize(from: downLoc, to: upLoc)
                    .map { GesturePattern(directions: [$0]) }

            guard let recognizedPattern = pattern else {
                // 의도적 드래그 + 인식 실패 — 사용자는 메뉴를 띄울 의도가 아니었으므로
                // 컨텍스트 메뉴를 띄우지 않고 silent cancel.
                let cb = onGestureSkipped
                DispatchQueue.main.async {
                    cb?(.ambiguousDirection(distance: distance))
                }
                return nil  // 원본 up도 삼킴 → 메뉴 안 뜸
            }

            // ▶ 매칭: custom 다중 segment 우선 → 단일 방향은 GestureMappings
            let matchedAction: BrowserAction?
            if let custom = CustomGestureMappings.match(recognizedPattern) {
                matchedAction = custom
            } else if recognizedPattern.directions.count == 1 {
                matchedAction = GestureMappings.action(for: recognizedPattern.directions[0])
            } else {
                matchedAction = nil  // 다중 segment지만 등록 없음
            }

            // 매핑이 아예 없는 경우 (다중 segment 인식했지만 등록 X) → silent cancel
            guard let action = matchedAction else {
                let cb = onGestureSkipped
                DispatchQueue.main.async {
                    cb?(.ambiguousDirection(distance: distance))
                }
                return nil
            }

            // 매핑이 명시적으로 Disabled인 경우 → 사용자 의도가 "이 방향은 메뉴 띄움"
            // 이 케이스만 의도적으로 컨텍스트 메뉴를 띄운다.
            if action == .disabled {
                down.location = upLoc
                down.post(tap: .cghidEventTap)
                return Unmanaged.passUnretained(event)
            }

            ActionExecutor.execute(action)
            let cb = onGestureExecuted
            DispatchQueue.main.async {
                cb?(recognizedPattern, action)
            }
            return nil  // 원본 up도 삼킴 → 컨텍스트 메뉴 안 뜸

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

// MARK: - Gesture Trail Overlay (드래그 경로 시각화)

/// NSBezierPath → CGPath 변환 (macOS 14 미만 호환).
private extension NSBezierPath {
    var asCGPath: CGPath {
        let path = CGMutablePath()
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo:                       path.move(to: pts[0])
            case .lineTo:                       path.addLine(to: pts[0])
            case .curveTo, .cubicCurveTo:       path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo:             path.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath:                    path.closeSubpath()
            @unknown default:                   break
            }
        }
        return path
    }
}

/// 드래그 경로를 그리는 NSView. CAShapeLayer 2개로 외곽 글로우 + 내부 라인.
/// 라이브 액션 라벨(HUD 스타일 floating tag)도 함께 호스팅한다.
/// 색상·배경·투명도는 OverlayPreferences를 매 reset() 시 다시 읽어 즉시 반영한다.
private final class TrailView: NSView {
    private let glowLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let bezier = NSBezierPath()
    private var lastPoint: NSPoint?

    private let labelBackground: NSView
    private let labelText: NSTextField

    /// 마우스 우하단으로의 라벨 오프셋 (마우스 커서 가리지 않도록)
    private static let labelOffset = NSPoint(x: 18, y: -56)
    private static let labelSize = NSSize(width: 170, height: 40)

    override init(frame: NSRect) {
        // 라벨 배경 (단순 NSView + cornerRadius — prefs 색상/투명도 반영 가능)
        labelBackground = NSView(frame: NSRect(origin: .zero, size: Self.labelSize))
        labelBackground.wantsLayer = true
        labelBackground.layer?.cornerRadius = 10
        labelBackground.layer?.masksToBounds = true
        labelBackground.isHidden = true

        // 라벨 텍스트 (색상은 reset() 시 배경 대비로 자동 결정)
        labelText = NSTextField(labelWithString: "")
        labelText.font = .systemFont(ofSize: 16, weight: .semibold)
        labelText.alignment = .center
        labelText.backgroundColor = .clear
        labelText.frame = NSRect(x: 8, y: 8, width: Self.labelSize.width - 16, height: 24)
        labelBackground.addSubview(labelText)

        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(lineLayer)
        addSubview(labelBackground)  // 라벨이 path 위에 그려지도록 마지막에 추가

        glowLayer.fillColor = nil
        glowLayer.lineWidth = 14
        glowLayer.lineCap = .round
        glowLayer.lineJoin = .round

        lineLayer.fillColor = nil
        lineLayer.lineWidth = 5
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round

        applyPreferences()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// OverlayPreferences를 읽어 색상·투명도를 layer/뷰에 적용한다.
    private func applyPreferences() {
        let trailColor = OverlayPreferences.trailColor
        glowLayer.strokeColor = trailColor.withAlphaComponent(0.35).cgColor
        lineLayer.strokeColor = trailColor.cgColor

        let bgColor = OverlayPreferences.backgroundColor
        let opacity = OverlayPreferences.backgroundOpacity
        labelBackground.layer?.backgroundColor = bgColor.withAlphaComponent(CGFloat(opacity)).cgColor
        labelText.textColor = textColorOnBackground(bgColor)
    }

    func reset(start: NSPoint) {
        applyPreferences()  // 매 드래그 시작 시 최신 prefs 반영
        bezier.removeAllPoints()
        bezier.move(to: start)
        lastPoint = start
        applyPath()
        labelBackground.isHidden = true
    }

    func extend(to point: NSPoint) {
        // 너무 가까운 점은 무시 (smoothing + 성능)
        if let last = lastPoint {
            let dx = point.x - last.x
            let dy = point.y - last.y
            if dx * dx + dy * dy < 4.0 { return }
        }
        bezier.line(to: point)
        lastPoint = point
        applyPath()
    }

    /// 라이브 액션 라벨을 갱신한다.
    /// - Parameters:
    ///   - mouseLocal: 윈도우 로컬 좌표계의 현재 마우스 위치
    ///   - text: 표시할 텍스트. nil이면 라벨 숨김.
    func updateLiveLabel(at mouseLocal: NSPoint, text: String?) {
        // CATransaction으로 위치 변경 시 implicit animation 비활성화 (부드러운 추적)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let text = text else {
            labelBackground.isHidden = true
            return
        }

        labelText.stringValue = text

        // 마우스 위치 + 오프셋. 화면 가장자리에서는 자동 flip.
        var origin = NSPoint(
            x: mouseLocal.x + Self.labelOffset.x,
            y: mouseLocal.y + Self.labelOffset.y
        )
        // 우측이 잘리면 마우스 왼쪽으로
        if origin.x + Self.labelSize.width > bounds.maxX {
            origin.x = mouseLocal.x - Self.labelSize.width - Self.labelOffset.x
        }
        // 하단이 잘리면 마우스 위쪽으로
        if origin.y < bounds.minY {
            origin.y = mouseLocal.y + 24
        }
        labelBackground.setFrameOrigin(origin)
        labelBackground.isHidden = false
    }

    private func applyPath() {
        // CAShapeLayer 갱신 시 implicit animation을 끄면 잔상 없이 즉시 반영
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cg = bezier.asCGPath
        glowLayer.path = cg
        lineLayer.path = cg
        CATransaction.commit()
    }
}

/// 풀스크린 투명 오버레이 윈도우 + 60Hz 마우스 위치 폴링으로 path를 그린다.
/// 입력은 일체 가로채지 않으며(ignoresMouseEvents=true), 단일 인스턴스를 재사용한다.
final class GestureTrailWindow {
    static let shared = GestureTrailWindow()

    private var panel: NSPanel?
    private var trailView: TrailView?
    private var pollTimer: Timer?
    private var totalLength: CGFloat = 0
    private var lastSampledPoint: NSPoint = .zero
    /// 글로벌 좌표(bottom-left)로 보관하는 드래그 시작점 — 라이브 인식의 기준점
    private var startGlobal: NSPoint = .zero
    /// 드래그 중 캡처되는 모든 점들 (CGEvent 좌표, top-left). PathAnalyzer 입력으로 사용.
    private(set) var capturedCGPath: [CGPoint] = []

    /// EventTapController가 mouse-up 시점에 path를 가져갈 수 있는 진입점.
    func currentCGPath() -> [CGPoint] { capturedCGPath }

    /// 거리 누적이 이 값 이상일 때 비로소 화면에 표시 (단순 클릭에서 깜빡임 방지)
    private static let visibilityThreshold: CGFloat = 8.0

    func begin() {
        DispatchQueue.main.async { [weak self] in
            self?.beginInternal()
        }
    }

    func end() {
        DispatchQueue.main.async { [weak self] in
            self?.endInternal()
        }
    }

    private func beginInternal() {
        // 직전 트레일이 살아있으면 즉시 정리
        pollTimer?.invalidate()
        panel?.orderOut(nil)

        // 다중 모니터 합집합 영역 (negative origin 가능)
        let frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver       // 거의 모든 윈도우 위
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true  // 입력은 일체 가로채지 않음
        panel.alphaValue = 0             // 거리 누적 후 fade-in

        // 윈도우 좌표는 panel.frame 기준 (bottom-left). NSEvent.mouseLocation도 동일 좌표계.
        // panel.frame의 origin이 (예) (-1440, 0)인 경우, 마우스 글로벌 좌표를 윈도우 로컬로 변환 필요.
        let view = TrailView(frame: NSRect(origin: .zero, size: frame.size))
        panel.contentView = view

        let start = NSEvent.mouseLocation
        let local = NSPoint(x: start.x - frame.origin.x, y: start.y - frame.origin.y)
        view.reset(start: local)

        panel.orderFrontRegardless()

        self.panel = panel
        self.trailView = view
        self.totalLength = 0
        self.lastSampledPoint = start
        self.startGlobal = start
        self.capturedCGPath = [GestureRecognizer.nsPointToCG(start)]

        // 60Hz 폴링
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let panel = panel, let view = trailView else { return }
        let global = NSEvent.mouseLocation
        let frame = panel.frame
        let local = NSPoint(x: global.x - frame.origin.x, y: global.y - frame.origin.y)

        let dx = global.x - lastSampledPoint.x
        let dy = global.y - lastSampledPoint.y
        let step = (dx * dx + dy * dy).squareRoot()
        if step >= 1.0 {
            totalLength += step
            lastSampledPoint = global
            view.extend(to: local)
            // 패턴 인식용으로 CGEvent 좌표계 path에 누적
            capturedCGPath.append(GestureRecognizer.nsPointToCG(global))

            // 일정 거리 누적되면 점진적 fade-in
            if panel.alphaValue < 1.0 && totalLength >= Self.visibilityThreshold {
                let alpha = min(1.0, (totalLength - Self.visibilityThreshold) / 12.0 + 0.4)
                panel.alphaValue = alpha
            }
        }

        // ▶ 라이브 액션 라벨: start→current 방향을 매 프레임 재인식
        // 사용자 prefs로 라벨 자체를 끈 경우엔 항상 hidden
        let labelText = OverlayPreferences.showActionLabel
            ? computeLiveLabel(currentGlobal: global)
            : nil
        view.updateLiveLabel(at: local, text: labelText)
    }

    /// 모든 제스처 상태를 라이브 오버레이 라벨로 표현한다 (사용자가 토스트 대신 오버레이만 사용 요청).
    /// - 짧은 드래그 (< 20px) → nil (메시지 노이즈 방지)
    /// - 비-브라우저 / 엔진 토글 OFF → "✗ Not browser: <앱명>"
    /// - 패턴 인식 실패 (사선 등) → "✗ Ambiguous"
    /// - 패턴 인식 + 매핑 없음 → "<패턴>  (no mapping)"
    /// - 패턴 인식 + 매핑 disabled → "<패턴>  (disabled)"
    /// - 정상 인식 → "<패턴>  <액션>"
    private func computeLiveLabel(currentGlobal: NSPoint) -> String? {
        // 거리 계산 (CGEvent 좌표계로 변환 후)
        let startCG = GestureRecognizer.nsPointToCG(startGlobal)
        let currentCG = GestureRecognizer.nsPointToCG(currentGlobal)
        let dx = currentCG.x - startCG.x
        let dy = currentCG.y - startCG.y
        let distance = (dx * dx + dy * dy).squareRoot()

        // 짧은 클릭/드래그 — 라벨 노이즈 방지
        if distance < 20 { return nil }

        // 비-브라우저 또는 엔진 토글 OFF
        if !EventTapController.shared.gesturesEnabledForFrontmost {
            let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "app"
            return "✗ Not browser: \(name)"
        }

        // 패턴 분석 — 실패 시 (사선·모호) 라벨로 사유 표시
        guard let pattern = PathAnalyzer.analyze(path: capturedCGPath) else {
            return "✗ Ambiguous"
        }

        // 매핑 조회 — custom 다중 segment 우선, 단일 방향은 기본 매핑
        let matched: BrowserAction?
        if let custom = CustomGestureMappings.match(pattern) {
            matched = custom
        } else if pattern.directions.count == 1 {
            matched = GestureMappings.action(for: pattern.directions[0])
        } else {
            matched = nil
        }

        guard let action = matched else {
            return "\(pattern.displayString)  (no mapping)"
        }
        if action == .disabled {
            return "\(pattern.displayString)  (disabled)"
        }
        return "\(pattern.displayString)  \(action.label)"
    }

    private func endInternal() {
        pollTimer?.invalidate()
        pollTimer = nil

        guard let panel = panel else { return }

        // 표시될 만큼 그리지도 못한 짧은 클릭은 즉시 숨김
        if panel.alphaValue == 0 {
            panel.orderOut(nil)
            self.panel = nil
            self.trailView = nil
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            // 사용자 설정의 lingering duration: 0.22 ~ 2.0초
            ctx.duration = OverlayPreferences.lingerDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            if self?.panel === panel {
                self?.panel = nil
                self?.trailView = nil
            }
        })
    }
}

// MARK: - Global Hotkey (Carbon RegisterEventHotKey)

/// macOS 글로벌 hotkey를 Carbon API로 등록한다.
/// NSEvent.addGlobalMonitorForEvents와 달리 키 입력을 **가로채서** 다른 앱으로 전파되지 않게 한다.
/// 우리는 ⌥⌘G로 메인 토글(우클릭→mouse-up 변환)을 ON/OFF 한다.
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
final class GestureToast {
    static let shared = GestureToast()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.display(message)
        }
    }

    private func display(_ message: String) {
        // 직전 Toast가 살아있으면 정리
        hideTimer?.invalidate()
        panel?.orderOut(nil)

        let width: CGFloat = 240
        let height: CGFloat = 56

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true  // 입력 가로채지 않도록

        // 시스템 HUD 스타일 배경 (블러 + 라운드)
        let visualEffect = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: width, height: height)
        )
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.backgroundColor = .clear
        label.frame = NSRect(x: 10, y: 14, width: width - 20, height: 28)
        visualEffect.addSubview(label)

        panel.contentView = visualEffect

        // 화면 상단 중앙에 배치
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: v.midX - width / 2,
                y: v.maxY - height - 100
            ))
        }

        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        })

        self.panel = panel
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            guard let self = self, let p = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.orderOut(nil)
                if self.panel === p { self.panel = nil }
            })
        }
    }
}

// MARK: - Settings Window (제스처 매핑 커스터마이즈)

/// 4방향 각각에 어떤 BrowserAction을 매핑할지 GUI로 설정한다.
/// 변경은 PopUpButton에서 즉시 UserDefaults에 반영되어 다음 제스처부터 적용된다.
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var popups: [GestureDirection: NSPopUpButton] = [:]

    // Live Overlay 컨트롤 — reset 시 갱신을 위해 보유
    private weak var trailColorWell: NSColorWell?
    private weak var backgroundColorWell: NSColorWell?
    private weak var opacitySlider: NSSlider?
    private weak var opacityLabel: NSTextField?
    private weak var showLabelCheckbox: NSButton?
    private weak var lingerPopup: NSPopUpButton?

    /// Custom gesture 리스트 컨테이너 — 추가/삭제 시 동적으로 갱신.
    private weak var customListStack: NSStackView?

    /// Linger duration 드롭다운에 표시할 옵션
    private static let lingerOptions: [(label: String, value: Double)] = [
        ("Instant (0.2s)",   0.22),
        ("Short (0.5s)",     0.5),
        ("Medium (1.0s)",    1.0),
        ("Long (1.5s)",      1.5),
        ("Very long (2.0s)", 2.0),
    ]

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        buildAndShow()
    }

    private func buildAndShow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Customize Mouse Gestures"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = buildContent()
        w.center()
        self.window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false

        // Header
        let title = NSTextField(labelWithString: "Mouse Gesture Mappings")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)

        let desc = NSTextField(labelWithString:
            "Drag with right-button held in a supported browser (Chromium / WebKit), then release.")
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        root.addArrangedSubview(desc)

        // 방향별 행 (NSGridView로 정렬: 화살표 / 라벨 / 드롭다운)
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false

        for direction in GestureDirection.allCases {
            let arrowLabel = NSTextField(labelWithString: direction.arrow)
            arrowLabel.font = .systemFont(ofSize: 22, weight: .medium)
            arrowLabel.alignment = .center

            let nameLabel = NSTextField(labelWithString: direction.name)
            nameLabel.font = .systemFont(ofSize: 13)
            nameLabel.textColor = .labelColor

            let popup = makePopup(for: direction)
            popups[direction] = popup

            grid.addRow(with: [arrowLabel, nameLabel, popup])
        }

        // 컬럼 폭 가이드
        if grid.numberOfColumns > 0 {
            grid.column(at: 0).width = 36
            grid.column(at: 1).width = 80
        }

        root.addArrangedSubview(grid)

        // ── Live Overlay 섹션 ──
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true

        let overlayTitle = NSTextField(labelWithString: "Live Overlay")
        overlayTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(overlayTitle)

        let overlayDesc = NSTextField(labelWithString:
            "Customize the trail and action label that appear during the drag.")
        overlayDesc.font = .systemFont(ofSize: 11)
        overlayDesc.textColor = .secondaryLabelColor
        root.addArrangedSubview(overlayDesc)

        root.addArrangedSubview(buildOverlayGrid())

        // ── Custom Gestures 섹션 ──
        let separator2 = NSBox()
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(separator2)
        separator2.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true

        let customTitle = NSTextField(labelWithString: "Custom Gestures")
        customTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(customTitle)

        let customDesc = NSTextField(labelWithString:
            "Multi-segment patterns drawn by you (e.g. ←↑, ↓→). Single directions use the table above.")
        customDesc.font = .systemFont(ofSize: 11)
        customDesc.textColor = .secondaryLabelColor
        root.addArrangedSubview(customDesc)

        let addButton = NSButton(
            title: "+ Add Custom Gesture…",
            target: self,
            action: #selector(showAddGesture)
        )
        root.addArrangedSubview(addButton)

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.spacing = 4
        listStack.alignment = .leading
        listStack.translatesAutoresizingMaskIntoConstraints = false
        self.customListStack = listStack
        root.addArrangedSubview(listStack)

        refreshCustomList()

        // Custom gesture 변경 알림 구독 — Add 모달이 저장하면 즉시 리스트 갱신
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshCustomList),
            name: .customGesturesChanged,
            object: nil
        )

        // Footer (Reset / Close)
        let footerSpacer = NSView()
        footerSpacer.translatesAutoresizingMaskIntoConstraints = false
        footerSpacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        root.addArrangedSubview(footerSpacer)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.alignment = .centerY

        let resetButton = NSButton(
            title: "Reset to Defaults",
            target: self,
            action: #selector(resetToDefaults)
        )
        footer.addArrangedSubview(resetButton)

        let flexible = NSView()
        flexible.translatesAutoresizingMaskIntoConstraints = false
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(flexible)

        let closeButton = NSButton(
            title: "Close",
            target: self,
            action: #selector(closeWindow)
        )
        closeButton.keyEquivalent = "\r"
        footer.addArrangedSubview(closeButton)

        // footer 너비 제약 — root 폭에 맞춰 늘어나게
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(footer)

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 0),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: 0),
        ])
        return container
    }

    private func makePopup(for direction: GestureDirection) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        for action in BrowserAction.allCases {
            popup.addItem(withTitle: action.label)
            // separator 흉내: disabled 항목 다음에 구분선 한 줄
            if action == .disabled {
                popup.menu?.addItem(NSMenuItem.separator())
            }
        }
        let current = GestureMappings.action(for: direction)
        popup.selectItem(withTitle: current.label)
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        popup.tag = direction.rawValue
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return popup
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let direction = GestureDirection(rawValue: sender.tag),
              let title = sender.titleOfSelectedItem,
              let action = BrowserAction.allCases.first(where: { $0.label == title }) else {
            return
        }
        GestureMappings.setAction(action, for: direction)
    }

    // MARK: Live Overlay UI

    /// 4행 NSGridView: Trail color / Background color+opacity / Show label / Linger duration
    private func buildOverlayGrid() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false

        // 1) Trail color
        let trailCW = NSColorWell()
        trailCW.color = OverlayPreferences.trailColor
        trailCW.target = self
        trailCW.action = #selector(trailColorChanged(_:))
        trailCW.translatesAutoresizingMaskIntoConstraints = false
        trailCW.widthAnchor.constraint(equalToConstant: 60).isActive = true
        trailCW.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.trailColorWell = trailCW
        grid.addRow(with: [makeFieldLabel("Trail color"), trailCW])

        // 2) Background color
        let bgCW = NSColorWell()
        bgCW.color = OverlayPreferences.backgroundColor
        bgCW.target = self
        bgCW.action = #selector(backgroundColorChanged(_:))
        bgCW.translatesAutoresizingMaskIntoConstraints = false
        bgCW.widthAnchor.constraint(equalToConstant: 60).isActive = true
        bgCW.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.backgroundColorWell = bgCW
        grid.addRow(with: [makeFieldLabel("Background color"), bgCW])

        // 3) Background opacity
        let opacityHStack = NSStackView()
        opacityHStack.orientation = .horizontal
        opacityHStack.spacing = 10
        opacityHStack.alignment = .centerY

        let slider = NSSlider(
            value: OverlayPreferences.backgroundOpacity * 100,
            minValue: 0,
            maxValue: 100,
            target: self,
            action: #selector(opacityChanged(_:))
        )
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        self.opacitySlider = slider

        let opacityValueLabel = NSTextField(labelWithString:
            "\(Int(OverlayPreferences.backgroundOpacity * 100))%")
        opacityValueLabel.font = .systemFont(ofSize: 12)
        opacityValueLabel.textColor = .secondaryLabelColor
        opacityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        opacityValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        self.opacityLabel = opacityValueLabel

        opacityHStack.addArrangedSubview(slider)
        opacityHStack.addArrangedSubview(opacityValueLabel)
        grid.addRow(with: [makeFieldLabel("Background opacity"), opacityHStack])

        // 4) Show action label
        let checkbox = NSButton(
            checkboxWithTitle: "Show action label while dragging",
            target: self,
            action: #selector(showLabelChanged(_:))
        )
        checkbox.state = OverlayPreferences.showActionLabel ? .on : .off
        self.showLabelCheckbox = checkbox
        grid.addRow(with: [makeFieldLabel("Action label"), checkbox])

        // 5) Linger duration
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        for option in Self.lingerOptions {
            popup.addItem(withTitle: option.label)
        }
        if let idx = Self.lingerOptions.firstIndex(where: {
            abs($0.value - OverlayPreferences.lingerDuration) < 0.01
        }) {
            popup.selectItem(at: idx)
        }
        popup.target = self
        popup.action = #selector(lingerChanged(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        self.lingerPopup = popup
        grid.addRow(with: [makeFieldLabel("Linger duration"), popup])

        if grid.numberOfColumns > 0 {
            grid.column(at: 0).width = 156
        }
        // 라벨 컬럼 우측 정렬
        for row in 0..<grid.numberOfRows {
            grid.cell(atColumnIndex: 0, rowIndex: row).xPlacement = .trailing
        }

        return grid
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text + ":")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.alignment = .right
        return label
    }

    @objc private func trailColorChanged(_ sender: NSColorWell) {
        OverlayPreferences.trailColor = sender.color
    }

    @objc private func backgroundColorChanged(_ sender: NSColorWell) {
        OverlayPreferences.backgroundColor = sender.color
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let value = sender.doubleValue / 100.0
        OverlayPreferences.backgroundOpacity = value
        opacityLabel?.stringValue = "\(Int(value * 100))%"
    }

    @objc private func showLabelChanged(_ sender: NSButton) {
        OverlayPreferences.showActionLabel = (sender.state == .on)
    }

    @objc private func lingerChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < Self.lingerOptions.count else { return }
        OverlayPreferences.lingerDuration = Self.lingerOptions[idx].value
    }

    // MARK: Custom Gestures UI

    /// CustomGestureMappings.all을 읽어 리스트를 다시 그린다.
    @objc private func refreshCustomList() {
        guard let stack = customListStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let all = CustomGestureMappings.all
        if all.isEmpty {
            let empty = NSTextField(labelWithString: "(no custom gestures yet)")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(empty)
            return
        }

        for (idx, def) in all.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 12
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false

            let patternLabel = NSTextField(labelWithString: def.pattern.displayString)
            patternLabel.font = .systemFont(ofSize: 18, weight: .medium)
            patternLabel.translatesAutoresizingMaskIntoConstraints = false
            patternLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
            row.addArrangedSubview(patternLabel)

            let arrow = NSTextField(labelWithString: "→")
            arrow.font = .systemFont(ofSize: 13)
            arrow.textColor = .tertiaryLabelColor
            row.addArrangedSubview(arrow)

            let actionLabel = NSTextField(labelWithString: def.action.label)
            actionLabel.font = .systemFont(ofSize: 13)
            actionLabel.translatesAutoresizingMaskIntoConstraints = false
            actionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
            row.addArrangedSubview(actionLabel)

            let removeButton = NSButton(
                title: "Remove",
                target: self,
                action: #selector(removeCustomGesture(_:))
            )
            removeButton.bezelStyle = .roundRect
            removeButton.controlSize = .small
            removeButton.tag = idx
            row.addArrangedSubview(removeButton)

            stack.addArrangedSubview(row)
        }
    }

    @objc private func showAddGesture() {
        AddGestureController.shared.show()
    }

    @objc private func removeCustomGesture(_ sender: NSButton) {
        let all = CustomGestureMappings.all
        let idx = sender.tag
        guard idx >= 0, idx < all.count else { return }
        CustomGestureMappings.remove(pattern: all[idx].pattern)
        refreshCustomList()
    }

    // MARK: Reset

    @objc private func resetToDefaults() {
        GestureMappings.resetToDefaults()
        OverlayPreferences.resetToDefaults()
        CustomGestureMappings.resetAll()
        // 매핑 popup 갱신
        for (direction, popup) in popups {
            let current = GestureMappings.action(for: direction)
            popup.selectItem(withTitle: current.label)
        }
        // 오버레이 컨트롤 갱신
        trailColorWell?.color = OverlayPreferences.trailColor
        backgroundColorWell?.color = OverlayPreferences.backgroundColor
        let opacity = OverlayPreferences.backgroundOpacity
        opacitySlider?.doubleValue = opacity * 100
        opacityLabel?.stringValue = "\(Int(opacity * 100))%"
        showLabelCheckbox?.state = OverlayPreferences.showActionLabel ? .on : .off
        if let idx = Self.lingerOptions.firstIndex(where: {
            abs($0.value - OverlayPreferences.lingerDuration) < 0.01
        }) {
            lingerPopup?.selectItem(at: idx)
        }
        refreshCustomList()
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // 메뉴바 앱이라 .accessory 활성 정책 그대로 유지
    }
}

// MARK: - Add Custom Gesture (drawing modal)

/// 사용자가 빈 영역에서 드래그해서 패턴을 직접 입력하고 액션을 선택해 등록하는 모달.
/// 패턴은 PathAnalyzer로 즉시 추출해 표시되며, 저장 시 CustomGestureMappings에 영속화한다.
final class AddGestureController: NSObject, NSWindowDelegate {
    static let shared = AddGestureController()

    private var window: NSWindow?
    private var captureView: GestureCaptureView?
    private weak var patternLabel: NSTextField?
    private weak var actionPopup: NSPopUpButton?
    private weak var saveButton: NSButton?

    private var capturedPattern: GesturePattern?

    /// disabled 제외한 액션 목록 — 사용자가 disabled를 등록하는 건 의미 없음
    private let actionChoices: [BrowserAction] = BrowserAction.allCases.filter { $0 != .disabled }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        buildAndShow()
    }

    private func buildAndShow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Add Custom Gesture"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = buildContent()
        w.center()
        self.window = w
        clearCapture()

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Draw your gesture")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)

        let desc = NSTextField(labelWithString:
            "Click and drag in the area below. Direction changes are recognized as new segments.")
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        root.addArrangedSubview(desc)

        // Drawing area
        let capture = GestureCaptureView(frame: NSRect(x: 0, y: 0, width: 380, height: 240))
        capture.translatesAutoresizingMaskIntoConstraints = false
        capture.widthAnchor.constraint(equalToConstant: 380).isActive = true
        capture.heightAnchor.constraint(equalToConstant: 240).isActive = true
        capture.onCapture = { [weak self] pattern in
            self?.handleCapture(pattern)
        }
        self.captureView = capture
        root.addArrangedSubview(capture)

        // Pattern preview
        let patternRow = NSStackView()
        patternRow.orientation = .horizontal
        patternRow.spacing = 10
        patternRow.alignment = .centerY

        let patternHead = NSTextField(labelWithString: "Pattern:")
        patternHead.font = .systemFont(ofSize: 13)
        patternHead.textColor = .secondaryLabelColor
        patternRow.addArrangedSubview(patternHead)

        let pLabel = NSTextField(labelWithString: "(draw to capture)")
        pLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        self.patternLabel = pLabel
        patternRow.addArrangedSubview(pLabel)
        root.addArrangedSubview(patternRow)

        // Action popup
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.alignment = .centerY

        let actionHead = NSTextField(labelWithString: "Action:")
        actionHead.font = .systemFont(ofSize: 13)
        actionHead.textColor = .secondaryLabelColor
        actionRow.addArrangedSubview(actionHead)

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        for action in actionChoices {
            popup.addItem(withTitle: action.label)
        }
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        self.actionPopup = popup
        actionRow.addArrangedSubview(popup)
        root.addArrangedSubview(actionRow)

        // Footer (Clear / Cancel / Save)
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearTapped))
        footer.addArrangedSubview(clearButton)

        let flex = NSView()
        flex.translatesAutoresizingMaskIntoConstraints = false
        flex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(flex)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"  // ESC
        footer.addArrangedSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"  // Return
        saveButton.bezelStyle = .rounded
        saveButton.isEnabled = false
        self.saveButton = saveButton
        footer.addArrangedSubview(saveButton)

        root.addArrangedSubview(footer)

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        return container
    }

    private func handleCapture(_ pattern: GesturePattern?) {
        capturedPattern = pattern
        if let p = pattern {
            patternLabel?.stringValue = p.displayString
            saveButton?.isEnabled = true
        } else {
            patternLabel?.stringValue = "(too short or ambiguous — try again)"
            saveButton?.isEnabled = false
        }
    }

    private func clearCapture() {
        capturedPattern = nil
        captureView?.clear()
        patternLabel?.stringValue = "(draw to capture)"
        saveButton?.isEnabled = false
    }

    @objc private func clearTapped() {
        clearCapture()
    }

    @objc private func cancelTapped() {
        window?.performClose(nil)
    }

    @objc private func saveTapped() {
        guard let pattern = capturedPattern,
              let popup = actionPopup,
              popup.indexOfSelectedItem >= 0,
              popup.indexOfSelectedItem < actionChoices.count else { return }
        let action = actionChoices[popup.indexOfSelectedItem]
        let def = GestureDefinition(pattern: pattern, action: action)
        CustomGestureMappings.upsert(def)
        NotificationCenter.default.post(name: .customGesturesChanged, object: nil)
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        clearCapture()
    }
}

/// 사용자가 자유 드래그로 path를 그리는 NSView. 좌클릭 사용.
/// path는 view-local(bottom-left) 좌표로 캡처되며 mouseUp 시 CGEvent 좌표(top-left)로 변환해 PathAnalyzer에 전달.
private final class GestureCaptureView: NSView {
    var onCapture: ((GesturePattern?) -> Void)?

    private var localPath: [NSPoint] = []
    private let lineLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let placeholder = NSTextField(labelWithString: "Click and drag to draw")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        glowLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.35).cgColor
        glowLayer.fillColor = nil
        glowLayer.lineWidth = 12
        glowLayer.lineCap = .round
        glowLayer.lineJoin = .round
        layer?.addSublayer(glowLayer)

        lineLayer.strokeColor = NSColor.systemBlue.cgColor
        lineLayer.fillColor = nil
        lineLayer.lineWidth = 4
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        layer?.addSublayer(lineLayer)

        placeholder.font = .systemFont(ofSize: 13)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        localPath = [p]
        placeholder.isHidden = true
        redraw()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        localPath.append(p)
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        // view-local (bottom-left) → CGEvent 스타일(top-left)로 y 뒤집기
        let h = bounds.height
        let cgPath = localPath.map { CGPoint(x: $0.x, y: h - $0.y) }
        let pattern = PathAnalyzer.analyze(path: cgPath)
        onCapture?(pattern)
    }

    func clear() {
        localPath = []
        placeholder.isHidden = false
        redraw()
    }

    private func redraw() {
        let bezier = NSBezierPath()
        if let first = localPath.first {
            bezier.move(to: first)
            for pt in localPath.dropFirst() {
                bezier.line(to: pt)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cg = bezier.asCGPath
        lineLayer.path = cg
        glowLayer.path = cg
        CATransaction.commit()
    }
}

// MARK: - App Delegate (Menu Bar UI)

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var statusLabelItem: NSMenuItem!
    private var activeAppItem: NSMenuItem!
    private var chromiumGesturesItem: NSMenuItem!
    private var webkitGesturesItem: NSMenuItem!
    private var customizeItem: NSMenuItem!
    private var gesturesSectionHeader: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupAppIcon()

        if UserDefaults.standard.object(forKey: "rightClickOnUp.enabled") == nil {
            EventTapController.shared.isEnabled = true
        }

        // 후행 토스트는 모두 제거 — 모든 메시지(성공/실패/사유)는 라이브 오버레이에 표시한다.
        // GestureToast 클래스는 향후 다른 용도로 쓸 수 있어 보존.

        // 글로벌 hotkey ⌥⌘G — 어디서나 mouse-up 변환 토글
        HotkeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak self] in
            self?.toggleEnabled()
        }

        // 우클릭 down/up 시점에 화면 트레일 오버레이 표시 / 숨김
        EventTapController.shared.onRightDown = {
            GestureTrailWindow.shared.begin()
        }
        EventTapController.shared.onRightUp = {
            GestureTrailWindow.shared.end()
        }

        // 패턴 인식용 path 공급자 — GestureTrailWindow가 polling으로 캡처한 path를 제공
        EventTapController.shared.pathProvider = {
            GestureTrailWindow.shared.currentCGPath()
        }

        buildStatusItem()
        applyState(showAlertOnFailure: false)
    }

    // MARK: - NSMenuDelegate

    /// 메뉴가 열리기 직전에 frontmost 앱 정보를 갱신한다.
    /// status bar 메뉴는 표시 시점에 우리 앱을 frontmost로 활성화하지 않으므로,
    /// 여기서 본 frontmost는 사용자가 마지막으로 작업하던 앱(예: Chrome)이다.
    func menuWillOpen(_ menu: NSMenu) {
        let app = NSWorkspace.shared.frontmostApplication
        let name = app?.localizedName ?? "(unknown)"
        let bid = app?.bundleIdentifier ?? "(unknown)"
        let mark: String
        if let engine = BrowserDetector.frontmostEngine {
            mark = "\(engine) ✓"
        } else {
            mark = "Not in list ✗"
        }
        activeAppItem.title = "Active: \(name) — \(mark)"
        activeAppItem.toolTip = "Bundle ID: \(bid)"
        updateMenuStateUI()
    }

    private func setupAppIcon() {
        guard let symbol = NSImage(
            systemSymbolName: "cursorarrow.click.2",
            accessibilityDescription: "right-click on up"
        ) else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 128, weight: .regular)
        let icon = symbol.withSymbolConfiguration(config) ?? symbol
        icon.isTemplate = false
        NSApp.applicationIconImage = icon
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self  // menuWillOpen 호출되도록

        statusLabelItem = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)

        activeAppItem = NSMenuItem(title: "Active: …", action: nil, keyEquivalent: "")
        activeAppItem.isEnabled = false
        menu.addItem(activeAppItem)

        menu.addItem(NSMenuItem.separator())

        // 메인 토글 — 모든 기능의 전제 조건. 글로벌 hotkey ⌥⌘G로도 토글 가능.
        toggleItem = NSMenuItem(
            title: "Enable right-click on mouse-up",
            action: #selector(toggleEnabled),
            keyEquivalent: "g"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .option]
        toggleItem.target = self
        menu.addItem(toggleItem)

        // 제스처 섹션 (mouse-up 의존) — 시각적으로 분리·indent로 위계 표현
        gesturesSectionHeader = NSMenuItem(title: "Browser Gestures",
                                            action: nil, keyEquivalent: "")
        gesturesSectionHeader.isEnabled = false
        menu.addItem(gesturesSectionHeader)

        chromiumGesturesItem = NSMenuItem(
            title: "Chromium (Chrome / Edge / Brave / Arc / …)",
            action: #selector(toggleChromiumGestures),
            keyEquivalent: ""
        )
        chromiumGesturesItem.target = self
        chromiumGesturesItem.indentationLevel = 1
        menu.addItem(chromiumGesturesItem)

        webkitGesturesItem = NSMenuItem(
            title: "WebKit (Safari / Safari TP / Orion)",
            action: #selector(toggleWebkitGestures),
            keyEquivalent: ""
        )
        webkitGesturesItem.target = self
        webkitGesturesItem.indentationLevel = 1
        menu.addItem(webkitGesturesItem)

        customizeItem = NSMenuItem(
            title: "Customize Gestures…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        customizeItem.keyEquivalentModifierMask = [.command, .shift]
        customizeItem.target = self
        customizeItem.indentationLevel = 1
        menu.addItem(customizeItem)

        menu.addItem(NSMenuItem.separator())

        launchAtLoginItem = NSMenuItem(
            title: "Launch at login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let openSettingsItem = NSMenuItem(
            title: "Open Privacy Settings…",
            action: #selector(openPrivacySettings),
            keyEquivalent: ""
        )
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu

        updateMenuStateUI()
    }

    private func updateMenuStateUI() {
        let enabled = EventTapController.shared.isEnabled
        let running = EventTapController.shared.isRunning

        toggleItem.state = enabled ? .on : .off
        chromiumGesturesItem.state = EventTapController.shared.chromiumGesturesEnabled ? .on : .off
        webkitGesturesItem.state = EventTapController.shared.webkitGesturesEnabled ? .on : .off

        // 제스처 설정은 mouse-up 변환이 ON일 때만 의미가 있다 (기능 의존성).
        // OFF면 위계상 하위인 제스처 항목들을 비활성화해 사용자 혼란 방지.
        let gesturesAvailable = enabled && running
        chromiumGesturesItem.isEnabled = gesturesAvailable
        webkitGesturesItem.isEnabled = gesturesAvailable
        customizeItem.isEnabled = gesturesAvailable

        // 섹션 헤더 — 의존성 상태에 따라 라벨에 hint 부착
        if !enabled {
            gesturesSectionHeader.title = "Browser Gestures (enable above first)"
        } else if !running {
            gesturesSectionHeader.title = "Browser Gestures (no permission)"
        } else {
            gesturesSectionHeader.title = "Browser Gestures"
        }

        let statusText: String
        if !enabled {
            statusText = "Status: OFF"
        } else if running {
            statusText = "Status: ON ✓"
        } else {
            statusText = "Status: ON (no permission)"
        }
        statusLabelItem.title = statusText

        if let button = statusItem.button {
            let symbolName = (enabled && running) ? "cursorarrow.click.2" : "cursorarrow.click"
            if let img = NSImage(systemSymbolName: symbolName,
                                  accessibilityDescription: "right-click on up") {
                img.isTemplate = true
                button.image = img
                button.title = ""
            } else {
                button.image = nil
                button.title = (enabled && running) ? "●" : "○"
            }
        }

        if #available(macOS 13.0, *) {
            launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            launchAtLoginItem.isEnabled = true
        } else {
            launchAtLoginItem.isEnabled = false
            launchAtLoginItem.title = "Launch at login (requires macOS 13+)"
        }
    }

    private func applyState(showAlertOnFailure: Bool) {
        if EventTapController.shared.isEnabled {
            let ok = EventTapController.shared.start()
            if !ok && showAlertOnFailure {
                showPermissionAlert()
            }
        } else {
            EventTapController.shared.stop()
        }
        updateMenuStateUI()
    }

    @objc private func toggleEnabled() {
        EventTapController.shared.isEnabled.toggle()
        applyState(showAlertOnFailure: true)
    }

    @objc private func toggleChromiumGestures() {
        EventTapController.shared.chromiumGesturesEnabled.toggle()
        updateMenuStateUI()
    }

    @objc private func toggleWebkitGestures() {
        EventTapController.shared.webkitGesturesEnabled.toggle()
        updateMenuStateUI()
    }

    @objc private func showSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at login 설정 실패"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateMenuStateUI()
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "gesture-ex"
        alert.informativeText = """
        macOS 우클릭을 마우스 떼는 시점(mouse-up)에 발사하도록 변환합니다.

        Chromium 계열(Chrome / Edge / Brave / Arc / Whale / Vivaldi / Opera 등) 및
        WebKit 계열(Safari / Safari TP / Orion) 브라우저에서 4방향 + 사용자 정의 다중 segment
        마우스 제스처를 지원합니다. 매핑은 Customize Gestures…(⇧⌘,)에서 변경 가능.

        Global hotkey: ⌥⌘G — anywhere to toggle on/off
        HID 이벤트 탭 사용. 필요 권한: Accessibility + Input Monitoring.
        """
        alert.runModal()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "권한이 필요합니다"
        alert.informativeText = """
        다음 두 권한을 모두 부여해주세요:

        • System Settings → Privacy & Security → Accessibility
        • System Settings → Privacy & Security → Input Monitoring

        부여 후 메뉴에서 토글을 다시 켜면 적용됩니다.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openPrivacySettings()
        }
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
