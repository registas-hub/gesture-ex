import Foundation

/// Right-click on mouse-up 변환의 적용 대상 앱 필터 모드.
/// All: 모든 앱 (default). Whitelist: 매칭되는 앱만 적용. Blacklist: 매칭 외 모두 적용.
enum AppFilterMode: String, Codable, CaseIterable {
    case all
    case whitelist
    case blacklist

    var label: String {
        switch self {
        case .all:       return "All apps (apply everywhere)"
        case .whitelist: return "Whitelist (only matching apps)"
        case .blacklist: return "Blacklist (skip matching apps)"
        }
    }
}

/// 활성 앱의 bundle ID에 대해 변환을 적용할지 판정한다.
/// 패턴은 `patternsText`에 한 줄에 하나씩. `regex:` prefix면 정규식, 아니면 정확 매칭.
struct AppFilter {
    private static let kMode = "appFilter.mode"
    private static let kPatterns = "appFilter.patterns"

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

    /// 멀티라인 패턴 문자열 (사용자가 텍스트 영역에서 직접 편집).
    /// 비어 있으면 매칭 후보 0 → whitelist면 모두 false, blacklist면 모두 true.
    static var patternsText: String {
        get { UserDefaults.standard.string(forKey: kPatterns) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kPatterns) }
    }

    /// 라인을 파싱해 (정규식 여부, 패턴, 컴파일된 정규식) 튜플로 반환.
    /// 빈 줄과 `#`로 시작하는 주석은 무시.
    private static var compiledRules: [(isRegex: Bool, raw: String, regex: NSRegularExpression?)] {
        let lines = patternsText.split(whereSeparator: \.isNewline)
        var rules: [(Bool, String, NSRegularExpression?)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("regex:") {
                let pat = String(trimmed.dropFirst("regex:".count))
                    .trimmingCharacters(in: .whitespaces)
                let r = try? NSRegularExpression(pattern: pat)
                rules.append((true, pat, r))
            } else {
                rules.append((false, trimmed, nil))
            }
        }
        return rules
    }

    /// EventTapController가 down/up 시점에 호출하는 진입점.
    static func shouldApply(to bundleID: String?) -> Bool {
        switch mode {
        case .all:
            return true
        case .whitelist:
            return matches(bundleID)
        case .blacklist:
            return !matches(bundleID)
        }
    }

    private static func matches(_ bundleID: String?) -> Bool {
        guard let id = bundleID, !id.isEmpty else { return false }
        for rule in compiledRules {
            if rule.isRegex {
                if let r = rule.regex {
                    let range = NSRange(id.startIndex..<id.endIndex, in: id)
                    if r.firstMatch(in: id, range: range) != nil {
                        return true
                    }
                }
            } else {
                if rule.raw == id { return true }
            }
        }
        return false
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: kMode)
        UserDefaults.standard.removeObject(forKey: kPatterns)
    }
}
