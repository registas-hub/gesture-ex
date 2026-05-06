import Foundation

/// Abstract capture service. Permission denial / cancel / write failure are thrown as `CaptureError`.
protocol CaptureService: Sendable {
    func capture(_ request: CaptureRequest) async throws -> CaptureResult
}

enum CaptureServiceFactory {
    static func makeDefault() -> any CaptureService {
        ScreenCaptureKitService()
    }
}
