import Foundation

extension Notification.Name {
    /// CapturePreferences change notification.
    static let capturePreferencesChanged = Notification.Name("capturePreferencesChanged")
}

/// User preferences for the capture module.
struct CapturePreferences {
    private static let kDestinations  = "capture.destinations.v1"
    private static let kCustomPath    = "capture.customPath"
    private static let kFormat        = "capture.format"
    private static let kJpegQuality   = "capture.jpegQuality"

    /// Persisted format tag — single source of truth for the "png"/"jpeg" string.
    private enum FormatTag: String { case png, jpeg }

    /// Default output destinations. Defaults to clipboard only.
    static var destinations: CaptureDestination {
        get {
            if UserDefaults.standard.object(forKey: kDestinations) == nil {
                return .default
            }
            return CaptureDestination(rawValue: UserDefaults.standard.integer(forKey: kDestinations))
        }
        set {
            guard newValue != destinations else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: kDestinations)
            NotificationCenter.default.post(name: .capturePreferencesChanged, object: nil)
        }
    }

    /// Save directory for `.fileCustomPath` destination. nil if unset.
    /// Setter validates that the path exists, is a directory, and is writable;
    /// invalid input is silently dropped (caller / UI must surface its own validation).
    static var customPath: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: kCustomPath),
                  !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            if let url = newValue {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                guard exists, isDir.boolValue,
                      FileManager.default.isWritableFile(atPath: url.path) else {
                    return
                }
                guard url != customPath else { return }
                UserDefaults.standard.set(url.path, forKey: kCustomPath)
            } else {
                guard customPath != nil else { return }
                UserDefaults.standard.removeObject(forKey: kCustomPath)
            }
            NotificationCenter.default.post(name: .capturePreferencesChanged, object: nil)
        }
    }

    /// Default image format.
    static var format: CaptureImageFormat {
        get {
            let raw = UserDefaults.standard.string(forKey: kFormat).flatMap(FormatTag.init(rawValue:))
            return raw == .jpeg ? .jpeg(quality: jpegQuality) : .png
        }
        set {
            guard newValue != format else { return }
            switch newValue {
            case .png:
                UserDefaults.standard.set(FormatTag.png.rawValue, forKey: kFormat)
            case .jpeg(let q):
                UserDefaults.standard.set(FormatTag.jpeg.rawValue, forKey: kFormat)
                let clamped = min(max(q, 0.1), 1.0)
                UserDefaults.standard.set(clamped, forKey: kJpegQuality)
            }
            NotificationCenter.default.post(name: .capturePreferencesChanged, object: nil)
        }
    }

    /// JPEG quality. Stored even when format is PNG (preserved across format flips).
    static var jpegQuality: Double {
        get {
            if UserDefaults.standard.object(forKey: kJpegQuality) == nil { return 0.85 }
            return UserDefaults.standard.double(forKey: kJpegQuality)
        }
        set {
            let clamped = min(max(newValue, 0.1), 1.0)
            guard clamped != jpegQuality else { return }
            UserDefaults.standard.set(clamped, forKey: kJpegQuality)
            NotificationCenter.default.post(name: .capturePreferencesChanged, object: nil)
        }
    }

    static func resetToDefaults() {
        for key in [kDestinations, kCustomPath, kFormat, kJpegQuality] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .capturePreferencesChanged, object: nil)
    }
}
