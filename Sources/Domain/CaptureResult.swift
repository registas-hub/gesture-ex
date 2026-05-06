import AppKit

/// 캡처 처리 결과.
/// - image: `.returnImage` 포함 시 채워진다. 그 외엔 nil
/// - savedFiles: 디스크에 저장된 모든 파일 경로 (Desktop / customPath)
/// - copiedToClipboard: `.clipboard` 처리가 성공했는지
struct CaptureResult {
    let image: NSImage?
    let savedFiles: [URL]
    let copiedToClipboard: Bool

    static let empty = CaptureResult(image: nil, savedFiles: [], copiedToClipboard: false)
}
