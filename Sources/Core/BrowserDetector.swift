import AppKit

/// 브라우저 엔진 식별자. 사용자에게 보여주는 라벨 이상의 의미는 없다 —
/// 두 엔진 모두 같은 키 단축키로 동작하므로 분기 자체에 영향은 없음.
enum BrowserEngine: String {
    case chromium = "Chromium"
    case webkit = "WebKit"
}

/// 브라우저 카탈로그 한 항목.
struct BrowserCatalogEntry {
    let displayName: String
    let bundleID: String
    let engine: BrowserEngine
}

struct BrowserDetector {
    /// 정적 카탈로그. UI에 보여줄 displayName과 그룹화를 위해 카테고리 enum까지 함께 보관한다.
    /// 새 브라우저 추가 시 이 배열 한 곳에만 손대면 된다.
    static let catalog: [BrowserCatalogEntry] = [
        // Chromium 공식 오픈소스 빌드
        .init(displayName: "Chromium",          bundleID: "org.chromium.Chromium",        engine: .chromium),
        // Google Chrome (모든 채널)
        .init(displayName: "Chrome",            bundleID: "com.google.Chrome",            engine: .chromium),
        .init(displayName: "Chrome Beta",       bundleID: "com.google.Chrome.beta",       engine: .chromium),
        .init(displayName: "Chrome Canary",     bundleID: "com.google.Chrome.canary",     engine: .chromium),
        .init(displayName: "Chrome Dev",        bundleID: "com.google.Chrome.dev",        engine: .chromium),
        // Microsoft Edge (모든 채널)
        .init(displayName: "Edge",              bundleID: "com.microsoft.edgemac",        engine: .chromium),
        .init(displayName: "Edge Beta",         bundleID: "com.microsoft.edgemac.Beta",   engine: .chromium),
        .init(displayName: "Edge Canary",       bundleID: "com.microsoft.edgemac.Canary", engine: .chromium),
        .init(displayName: "Edge Dev",          bundleID: "com.microsoft.edgemac.Dev",    engine: .chromium),
        // Brave
        .init(displayName: "Brave",             bundleID: "com.brave.Browser",            engine: .chromium),
        .init(displayName: "Brave Beta",        bundleID: "com.brave.Browser.beta",       engine: .chromium),
        .init(displayName: "Brave Nightly",     bundleID: "com.brave.Browser.nightly",    engine: .chromium),
        // The Browser Company
        .init(displayName: "Arc",               bundleID: "company.thebrowser.Browser",   engine: .chromium),
        .init(displayName: "Dia",               bundleID: "company.thebrowser.dia",       engine: .chromium),
        // Naver Whale
        .init(displayName: "Whale",             bundleID: "com.naver.Whale",              engine: .chromium),
        // Vivaldi
        .init(displayName: "Vivaldi",           bundleID: "com.vivaldi.Vivaldi",          engine: .chromium),
        // Opera (모든 변형)
        .init(displayName: "Opera",             bundleID: "com.operasoftware.Opera",      engine: .chromium),
        .init(displayName: "Opera GX",          bundleID: "com.operasoftware.OperaGX",    engine: .chromium),
        .init(displayName: "Opera Next",        bundleID: "com.operasoftware.OperaNext",  engine: .chromium),
        // 기타 Chromium 기반
        .init(displayName: "CocCoc",            bundleID: "com.coccoc.coccoc",            engine: .chromium),
        .init(displayName: "Yandex",            bundleID: "ru.yandex.desktop.yandex-browser", engine: .chromium),

        // WebKit (Safari 엔진 계열)
        .init(displayName: "Safari",            bundleID: "com.apple.Safari",                  engine: .webkit),
        .init(displayName: "Safari Technology Preview", bundleID: "com.apple.SafariTechnologyPreview", engine: .webkit),
        .init(displayName: "Orion (Kagi)",      bundleID: "com.kagi.kagimacOS",           engine: .webkit),
        .init(displayName: "Orion (alt id)",    bundleID: "io.kagi.orion",                engine: .webkit),
        .init(displayName: "Orion",             bundleID: "com.kagi.orion",               engine: .webkit),
    ]

    /// 사용자가 비활성화하지 않은 카탈로그 항목.
    static var enabledCatalog: [BrowserCatalogEntry] {
        let disabled = BrowserPreferences.disabledBundleIDs
        return catalog.filter { !disabled.contains($0.bundleID) }
    }

    /// 활성 Chromium bundle ID 집합 (사용자 비활성 반영).
    static var chromiumBundles: Set<String> {
        Set(enabledCatalog.filter { $0.engine == .chromium }.map(\.bundleID))
    }

    /// 활성 WebKit bundle ID 집합 (사용자 비활성 반영).
    static var webkitBundles: Set<String> {
        Set(enabledCatalog.filter { $0.engine == .webkit }.map(\.bundleID))
    }

    /// 활성 브라우저 bundle ID 합집합.
    static var bundles: Set<String> {
        Set(enabledCatalog.map(\.bundleID))
    }

    static var isFrontmost: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return bundles.contains(bundleID)
    }

    /// 현재 활성 브라우저의 엔진 라벨 (메뉴 표시·디버깅용). 비활성 처리된 브라우저면 nil.
    static var frontmostEngine: String? {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let entry = enabledCatalog.first(where: { $0.bundleID == bundleID }) else {
            return nil
        }
        return entry.engine.rawValue
    }
}

// MARK: - Gesture Recognition

