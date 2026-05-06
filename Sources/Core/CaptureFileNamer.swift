import Foundation

/// Capture filename helper. Reusable across modules.
/// Format: `gesture-ex-YYYYMMDD-HHmmss.<ext>`
enum CaptureFileNamer {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    static func defaultFilename(format: CaptureImageFormat, at date: Date = Date()) -> String {
        "gesture-ex-\(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// Build a non-colliding URL inside `directory`. On collision, appends `-1`, `-2`, ...
    /// On extreme collision (>9999) falls back to a UUID-prefixed name to avoid overwrite.
    static func uniqueURL(in directory: URL,
                          format: CaptureImageFormat,
                          at date: Date = Date()) -> URL {
        let base = defaultFilename(format: format, at: date)
        let candidate = directory.appendingPathComponent(base)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        let stem = (base as NSString).deletingPathExtension
        let ext = format.fileExtension
        for i in 1...9999 {
            let next = directory.appendingPathComponent("\(stem)-\(i).\(ext)")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        // Extreme fallback — UUID suffix never collides.
        let uuid = UUID().uuidString.prefix(8)
        return directory.appendingPathComponent("\(stem)-\(uuid).\(ext)")
    }
}
