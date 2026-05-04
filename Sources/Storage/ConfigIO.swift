import AppKit

/// 설정 import/export 결과를 사용자에게 알리거나 try 컨텍스트에서 던지기 위한 에러 타입.
enum ConfigIOError: LocalizedError {
    case invalidJSON
    case unsupportedSchema(Int)
    case readFailed(underlying: Error)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The selected file is not a valid configuration JSON."
        case .unsupportedSchema(let v):
            return "This configuration was created with a newer version of the app (schema \(v))."
        case .readFailed(let e):
            return "Failed to read the file: \(e.localizedDescription)"
        case .writeFailed(let e):
            return "Failed to write the file: \(e.localizedDescription)"
        }
    }
}

/// 설정 전체를 한 JSON 문서로 묶기 위한 스냅샷.
///
/// 모든 필드는 optional로 두어 import 시 부분 적용을 허용한다 — 누락된 섹션은 기존 값을 유지한다.
/// 각 storage struct가 자체 keying 스킴(GestureMappings는 방향별 키, OverlayPreferences는 NSKeyedArchiver 등)을
/// 가지고 있어, 이를 그대로 직렬화하면 외부 공유에 적합하지 않다. 그래서 휴대용(JSON friendly) 표현을
/// 별도로 가진 스냅샷 레이어를 둔다.
struct ConfigSnapshot: Codable {
    /// 향후 마이그레이션용 — major bump 시 import 거부, minor는 수용.
    static let currentSchema = 1

    var schema: Int = currentSchema
    var exportedAt: Date?
    var appVersion: String?

    var gestureMappings: GestureMappingsPayload?
    var customGestures: [GestureDefinition]?
    var overlay: OverlayPayload?
    var browserPrefs: BrowserPrefsPayload?
    var appFilter: BundleFilterPayload?
    var gestureAppFilter: BundleFilterPayload?
    var hotkey: HotkeyPayload?

    struct GestureMappingsPayload: Codable {
        var left: String?
        var right: String?
        var up: String?
        var down: String?
    }

    struct OverlayPayload: Codable {
        var trailColor: ColorRGBA?
        var backgroundColor: ColorRGBA?
        var backgroundOpacity: Double?
        var showActionLabel: Bool?
        var lingerDuration: Double?
    }

    struct BrowserPrefsPayload: Codable {
        var disabledBundleIDs: [String]
    }

    struct BundleFilterPayload: Codable {
        var mode: String
        var patternsText: String
    }

    struct HotkeyPayload: Codable {
        var binding: KeyShortcut?
        var isEnabled: Bool?
    }

    /// sRGB 컴포넌트 표현. NSColor의 NSKeyedArchiver 포맷은 휴대성이 없어 JSON 친화 표현으로 변환한다.
    struct ColorRGBA: Codable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double

        init(_ color: NSColor) {
            let c = color.usingColorSpace(.sRGB) ?? color
            self.r = Double(c.redComponent)
            self.g = Double(c.greenComponent)
            self.b = Double(c.blueComponent)
            self.a = Double(c.alphaComponent)
        }

        var nsColor: NSColor {
            NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        }
    }
}

/// 현재 UserDefaults 상태 ↔ ConfigSnapshot ↔ JSON 파일 사이의 직렬화/역직렬화.
struct ConfigIO {
    /// 현재 UserDefaults 상태로부터 스냅샷 생성. 한 트랜잭션의 일관성은 UserDefaults가 즉시 반환해 주므로 별도 락 없음.
    static func captureSnapshot() -> ConfigSnapshot {
        var snap = ConfigSnapshot()
        snap.exportedAt = Date()
        snap.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        snap.gestureMappings = ConfigSnapshot.GestureMappingsPayload(
            left:  GestureMappings.action(for: .left).rawValue,
            right: GestureMappings.action(for: .right).rawValue,
            up:    GestureMappings.action(for: .up).rawValue,
            down:  GestureMappings.action(for: .down).rawValue
        )

        snap.customGestures = CustomGestureMappings.all

        snap.overlay = ConfigSnapshot.OverlayPayload(
            trailColor:        .init(OverlayPreferences.trailColor),
            backgroundColor:   .init(OverlayPreferences.backgroundColor),
            backgroundOpacity: OverlayPreferences.backgroundOpacity,
            showActionLabel:   OverlayPreferences.showActionLabel,
            lingerDuration:    OverlayPreferences.lingerDuration
        )

        snap.browserPrefs = ConfigSnapshot.BrowserPrefsPayload(
            disabledBundleIDs: Array(BrowserPreferences.disabledBundleIDs).sorted()
        )

        snap.appFilter = ConfigSnapshot.BundleFilterPayload(
            mode: AppFilter.mode.rawValue,
            patternsText: AppFilter.patternsText
        )
        snap.gestureAppFilter = ConfigSnapshot.BundleFilterPayload(
            mode: GestureAppFilter.mode.rawValue,
            patternsText: GestureAppFilter.patternsText
        )

        snap.hotkey = ConfigSnapshot.HotkeyPayload(
            binding: HotkeyPreferences.binding,
            isEnabled: HotkeyPreferences.isEnabled
        )

        return snap
    }

    /// 스냅샷을 사용자 친화 형태(들여쓰기, 안정 키 순서)의 JSON 데이터로 인코딩.
    static func encode(_ snap: ConfigSnapshot) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(snap)
    }

    /// 파일에서 스냅샷을 역직렬화. 데이터 손상이나 신규 스키마는 ConfigIOError로 매핑.
    static func decode(_ data: Data) throws -> ConfigSnapshot {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let snap: ConfigSnapshot
        do {
            snap = try dec.decode(ConfigSnapshot.self, from: data)
        } catch {
            throw ConfigIOError.invalidJSON
        }
        if snap.schema > ConfigSnapshot.currentSchema {
            throw ConfigIOError.unsupportedSchema(snap.schema)
        }
        return snap
    }

    /// URL → ConfigSnapshot. 실패 사유에 따라 read/decode 에러를 분기.
    static func load(from url: URL) throws -> ConfigSnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigIOError.readFailed(underlying: error)
        }
        return try decode(data)
    }

    /// 현재 상태를 URL에 기록. 디렉토리 미존재 등은 writeFailed로 매핑.
    static func save(to url: URL, snapshot: ConfigSnapshot? = nil) throws {
        let snap = snapshot ?? captureSnapshot()
        let data: Data
        do {
            data = try encode(snap)
        } catch {
            throw ConfigIOError.writeFailed(underlying: error)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ConfigIOError.writeFailed(underlying: error)
        }
    }

    /// 스냅샷을 UserDefaults에 적용한다. 누락된 섹션은 무시 — 기존 값 보존.
    /// 모든 변경 후 적절한 NotificationCenter 알림을 발사해 EventTap/SettingsWindow가 즉시 동기화하게 한다.
    static func apply(_ snap: ConfigSnapshot) {
        if let m = snap.gestureMappings {
            applyGestureMapping(m.left,  for: .left)
            applyGestureMapping(m.right, for: .right)
            applyGestureMapping(m.up,    for: .up)
            applyGestureMapping(m.down,  for: .down)
        }

        if let customs = snap.customGestures {
            CustomGestureMappings.all = customs
            // CustomGestureMappings setter는 알림을 발사하지 않으므로 직접 보낸다 — Settings 리스트가 즉시 갱신된다.
            NotificationCenter.default.post(name: .customGesturesChanged, object: nil)
        }

        if let o = snap.overlay {
            if let c = o.trailColor        { OverlayPreferences.trailColor = c.nsColor }
            if let c = o.backgroundColor   { OverlayPreferences.backgroundColor = c.nsColor }
            if let v = o.backgroundOpacity { OverlayPreferences.backgroundOpacity = v }
            if let v = o.showActionLabel   { OverlayPreferences.showActionLabel = v }
            if let v = o.lingerDuration    { OverlayPreferences.lingerDuration = v }
        }

        if let b = snap.browserPrefs {
            BrowserPreferences.disabledBundleIDs = Set(b.disabledBundleIDs)
        }

        if let f = snap.appFilter {
            if let mode = AppFilterMode(rawValue: f.mode) { AppFilter.mode = mode }
            AppFilter.patternsText = f.patternsText
        }
        if let f = snap.gestureAppFilter {
            if let mode = AppFilterMode(rawValue: f.mode) { GestureAppFilter.mode = mode }
            GestureAppFilter.patternsText = f.patternsText
        }

        if let h = snap.hotkey {
            // isEnabled 먼저 적용해 binding 변경 알림이 한 번에 정합 상태로 발사되게 한다 —
            // setter가 동일값이면 일찍 반환하므로 중복 알림 비용은 크지 않다.
            if let v = h.isEnabled { HotkeyPreferences.isEnabled = v }
            if let b = h.binding   { HotkeyPreferences.binding = b }
        }
    }

    private static func applyGestureMapping(_ raw: String?, for direction: GestureDirection) {
        guard let raw, let action = BrowserAction(rawValue: raw) else { return }
        GestureMappings.setAction(action, for: direction)
    }
}
