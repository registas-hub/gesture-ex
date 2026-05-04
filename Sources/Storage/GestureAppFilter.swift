import Foundation

/// 마우스 제스처 인식의 적용 대상 앱 스코프.
/// AppFilter와 동일한 mode/patterns 모델을 가지지만, 평가 시점이 다르다 —
/// AppFilter는 rightMouseDown에서 변환 자체를 가를 때, GestureAppFilter는
/// rightMouseUp 직전 패턴 인식 단계에서 평가된다. 두 필터는 AND로 결합된다.
struct GestureAppFilter {
    private static let kMode = "gestureFilter.mode"
    private static let kPatterns = "gestureFilter.patterns"

    static var mode: AppFilterMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: kMode),
               let m = AppFilterMode(rawValue: raw) {
                return m
            }
            return .all
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kMode) }
    }

    static var patternsText: String {
        get { UserDefaults.standard.string(forKey: kPatterns) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kPatterns) }
    }

    static func shouldApply(to bundleID: String?) -> Bool {
        switch mode {
        case .all:       return true
        case .whitelist: return matches(bundleID)
        case .blacklist: return !matches(bundleID)
        }
    }

    private static func matches(_ bundleID: String?) -> Bool {
        guard let id = bundleID, !id.isEmpty else { return false }
        for line in patternsText.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("regex:") {
                let pat = String(trimmed.dropFirst("regex:".count))
                    .trimmingCharacters(in: .whitespaces)
                if let r = try? NSRegularExpression(pattern: pat),
                   r.firstMatch(in: id,
                                range: NSRange(id.startIndex..<id.endIndex, in: id)) != nil {
                    return true
                }
            } else if trimmed == id {
                return true
            }
        }
        return false
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: kMode)
        UserDefaults.standard.removeObject(forKey: kPatterns)
    }
}
