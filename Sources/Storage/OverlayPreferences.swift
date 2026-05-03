import AppKit

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
func textColorOnBackground(_ bg: NSColor) -> NSColor {
    let c = bg.usingColorSpace(.sRGB) ?? bg
    let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    return lum > 0.55 ? NSColor.black : NSColor.white
}

// MARK: - Action Execution

