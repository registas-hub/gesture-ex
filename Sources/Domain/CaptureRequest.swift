import Foundation

/// 이미지 출력 포맷.
enum CaptureImageFormat: Hashable {
    case png
    case jpeg(quality: Double)   // 0.0 ~ 1.0

    var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpeg: return "jpg"
        }
    }
}

extension CaptureImageFormat: Codable {
    private enum Kind: String, Codable { case png, jpeg }
    private enum CodingKeys: String, CodingKey { case kind, quality }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .png:
            try c.encode(Kind.png, forKey: .kind)
        case .jpeg(let q):
            try c.encode(Kind.jpeg, forKey: .kind)
            try c.encode(q, forKey: .quality)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .png:  self = .png
        case .jpeg:
            let q = try c.decodeIfPresent(Double.self, forKey: .quality) ?? 0.85
            self = .jpeg(quality: q)
        }
    }
}

/// 캡처 1건 요청.
/// `destinations`가 비어 있으면 호출자 의도가 명확하지 않다 — 구현체가 throw하거나 noop.
struct CaptureRequest: Hashable {
    let target: CaptureTarget
    let destinations: CaptureDestination
    /// `.fileCustomPath` 선택 시 저장할 디렉토리. nil이면 prefs의 기본 경로 사용.
    let customPath: URL?
    let format: CaptureImageFormat

    init(target: CaptureTarget,
         destinations: CaptureDestination = .default,
         customPath: URL? = nil,
         format: CaptureImageFormat = .png) {
        self.target = target
        self.destinations = destinations
        self.customPath = customPath
        self.format = format
    }
}
