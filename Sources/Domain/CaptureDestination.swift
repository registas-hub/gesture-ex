import Foundation

/// 캡처 결과의 출력 대상. 다중 선택 가능 (OptionSet).
/// rawValue는 UserDefaults에 정수로 직렬화한다.
struct CaptureDestination: OptionSet, Hashable, Codable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let clipboard      = CaptureDestination(rawValue: 1 << 0)
    static let fileDesktop    = CaptureDestination(rawValue: 1 << 1)
    static let fileCustomPath = CaptureDestination(rawValue: 1 << 2)
    static let returnImage    = CaptureDestination(rawValue: 1 << 3)

    /// 디폴트: 클립보드만.
    static let `default`: CaptureDestination = [.clipboard]

    var labels: [String] {
        var out: [String] = []
        if contains(.clipboard)      { out.append("Clipboard") }
        if contains(.fileDesktop)    { out.append("Desktop") }
        if contains(.fileCustomPath) { out.append("Custom Path") }
        if contains(.returnImage)    { out.append("Return Image") }
        return out
    }
}
