import AppKit

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

