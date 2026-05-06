import CoreGraphics

/// 화면 캡처 대상.
/// - fullScreen: 모든 디스플레이 union — 다중 모니터는 디스플레이별 캡처 후 합성
/// - activeWindow: 최상위 앱의 키 윈도우 한 장
/// - region: 사각형 영역. nil이면 사용자 인터랙티브 드래그로 결정
/// - frontmostApp: 최상위 앱의 모든 윈도우 합성
enum CaptureTarget: Hashable {
    case fullScreen
    case activeWindow
    case region(CGRect?)
    case frontmostApp

    var label: String {
        switch self {
        case .fullScreen:    return "Full Screen"
        case .activeWindow:  return "Active Window"
        case .region(let r): return r == nil ? "Region (Select)" : "Region"
        case .frontmostApp:  return "Frontmost App"
        }
    }
}

extension CaptureTarget: Codable {
    private enum Kind: String, Codable {
        case fullScreen, activeWindow, region, frontmostApp
    }
    private enum CodingKeys: String, CodingKey { case kind, rect }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fullScreen:
            try c.encode(Kind.fullScreen, forKey: .kind)
        case .activeWindow:
            try c.encode(Kind.activeWindow, forKey: .kind)
        case .region(let rect):
            try c.encode(Kind.region, forKey: .kind)
            if let rect {
                try c.encode([rect.origin.x, rect.origin.y, rect.size.width, rect.size.height],
                             forKey: .rect)
            }
        case .frontmostApp:
            try c.encode(Kind.frontmostApp, forKey: .kind)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .fullScreen:    self = .fullScreen
        case .activeWindow:  self = .activeWindow
        case .frontmostApp:  self = .frontmostApp
        case .region:
            if let arr = try c.decodeIfPresent([CGFloat].self, forKey: .rect), arr.count == 4 {
                self = .region(CGRect(x: arr[0], y: arr[1], width: arr[2], height: arr[3]))
            } else {
                self = .region(nil)
            }
        }
    }
}
