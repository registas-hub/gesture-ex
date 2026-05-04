import AppKit

enum ConfigIOError: LocalizedError {
    case invalidJSON(underlying: Error)
    case unsupportedSchema(Int)
    case readFailed(underlying: Error)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let e):
            return "The selected file is not a valid configuration JSON: \(e.localizedDescription)"
        case .unsupportedSchema(let v):
            return "This configuration was created with a newer version of the app (schema \(v))."
        case .readFailed(let e):
            return "Failed to read the file: \(e.localizedDescription)"
        case .writeFailed(let e):
            return "Failed to write the file: \(e.localizedDescription)"
        }
    }
}

/// Optional 필드는 import 시 부분 적용 — 누락된 섹션은 기존 값을 유지한다.
struct ConfigSnapshot: Codable {
    /// major bump 시 import 거부, minor는 수용.
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
        var left: BrowserAction?
        var right: BrowserAction?
        var up: BrowserAction?
        var down: BrowserAction?
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
        var mode: AppFilterMode
        var patternsText: String
    }

    struct HotkeyPayload: Codable {
        var binding: KeyShortcut?
        var isEnabled: Bool?
    }

    /// NSColor의 NSKeyedArchiver 포맷은 휴대성이 없어 sRGB 컴포넌트로 변환한다.
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

struct ConfigIO {
    static func captureSnapshot() -> ConfigSnapshot {
        var snap = ConfigSnapshot()
        snap.exportedAt = Date()
        snap.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        snap.gestureMappings = ConfigSnapshot.GestureMappingsPayload(
            left:  GestureMappings.action(for: .left),
            right: GestureMappings.action(for: .right),
            up:    GestureMappings.action(for: .up),
            down:  GestureMappings.action(for: .down)
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
            mode: AppFilter.mode,
            patternsText: AppFilter.patternsText
        )
        snap.gestureAppFilter = ConfigSnapshot.BundleFilterPayload(
            mode: GestureAppFilter.mode,
            patternsText: GestureAppFilter.patternsText
        )

        snap.hotkey = ConfigSnapshot.HotkeyPayload(
            binding: HotkeyPreferences.binding,
            isEnabled: HotkeyPreferences.isEnabled
        )

        return snap
    }

    static func encode(_ snap: ConfigSnapshot) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(snap)
    }

    static func decode(_ data: Data) throws -> ConfigSnapshot {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let snap: ConfigSnapshot
        do {
            snap = try dec.decode(ConfigSnapshot.self, from: data)
        } catch {
            throw ConfigIOError.invalidJSON(underlying: error)
        }
        if snap.schema > ConfigSnapshot.currentSchema {
            throw ConfigIOError.unsupportedSchema(snap.schema)
        }
        return snap
    }

    static func load(from url: URL) throws -> ConfigSnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigIOError.readFailed(underlying: error)
        }
        return try decode(data)
    }

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

    /// 누락된 섹션은 기존 값 보존. 호출자(`SettingsWindow`)가 적용 후 UI를 일괄 refresh 한다.
    static func apply(_ snap: ConfigSnapshot) {
        if let m = snap.gestureMappings {
            if let a = m.left  { GestureMappings.setAction(a, for: .left) }
            if let a = m.right { GestureMappings.setAction(a, for: .right) }
            if let a = m.up    { GestureMappings.setAction(a, for: .up) }
            if let a = m.down  { GestureMappings.setAction(a, for: .down) }
        }

        if let customs = snap.customGestures {
            CustomGestureMappings.all = customs
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
            AppFilter.mode = f.mode
            AppFilter.patternsText = f.patternsText
        }
        if let f = snap.gestureAppFilter {
            GestureAppFilter.mode = f.mode
            GestureAppFilter.patternsText = f.patternsText
        }

        if let h = snap.hotkey {
            // isEnabled를 먼저 적용 — binding 변경 알림 시점에 enabled 상태가 일관되어야 한다.
            if let v = h.isEnabled { HotkeyPreferences.isEnabled = v }
            if let b = h.binding   { HotkeyPreferences.binding = b }
        }
    }
}
