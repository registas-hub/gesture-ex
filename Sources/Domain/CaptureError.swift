import Foundation

/// Capture failure cause. Mapped to user alert/toast at higher layers.
enum CaptureError: Error, Equatable {
    /// Screen Recording permission missing.
    case permissionDenied
    /// Active window / frontmost app could not be located.
    case targetNotFound
    /// User cancelled region drag (ESC, right-click, etc).
    case userCancelledRegion
    /// Disk write failed.
    case writeFailed(URL, message: String)
    /// ScreenCaptureKit init or capture failed.
    case sckUnavailable(message: String)
    /// PNG/JPEG encoding failed.
    case encodingFailed(format: String, message: String)
    /// Below macOS 14.0 (defensive).
    case unsupportedOS
    /// Empty destinations / missing customPath etc.
    case invalidRequest(String)

    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission required. Allow in System Settings → Privacy & Security → Screen Recording."
        case .targetNotFound:
            return "No window or app available to capture."
        case .userCancelledRegion:
            return "Region selection cancelled."
        case .writeFailed(let url, let msg):
            return "File write failed: \(url.path) — \(msg)"
        case .sckUnavailable(let msg):
            return "ScreenCaptureKit unavailable: \(msg)"
        case .encodingFailed(let format, let msg):
            return "Image encoding failed (\(format)): \(msg)"
        case .unsupportedOS:
            return "Capture requires macOS 14 or later."
        case .invalidRequest(let msg):
            return "Invalid capture request: \(msg)"
        }
    }
}
