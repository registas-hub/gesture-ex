import AppKit
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

/// ScreenCaptureKit-backed capture implementation.
/// Uses `SCScreenshotManager.captureImage` (macOS 14+); throws `.unsupportedOS`
/// otherwise. Region selection is delegated to an injected `RegionPicker`.
final class ScreenCaptureKitService: CaptureService, Sendable {

    private let regionPicker: RegionPicker

    init(regionPicker: RegionPicker = RegionSelectionWindow.shared) {
        self.regionPicker = regionPicker
    }

    func capture(_ request: CaptureRequest) async throws -> CaptureResult {
        // Validate up-front so side effects (clipboard, files) never fire on a
        // request that will throw later.
        try validate(request)

        guard #available(macOS 14.0, *) else {
            throw CaptureError.unsupportedOS
        }

        // Resolve region target: either user-supplied rect or interactive pick.
        let resolved: ResolvedTarget
        switch request.target {
        case .fullScreen:    resolved = .fullScreen
        case .activeWindow:  resolved = .activeWindow
        case .frontmostApp:  resolved = .frontmostApp
        case .region(let rectOpt):
            if let rect = rectOpt {
                guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
                        ?? NSScreen.main else {
                    throw CaptureError.targetNotFound
                }
                resolved = .region(rect: rect, screen: screen)
            } else {
                guard let pick = await regionPicker.pickRegion() else {
                    throw CaptureError.userCancelledRegion
                }
                resolved = .region(rect: pick.rect, screen: pick.screen)
            }
        }

        let content = try await fetchShareableContent()

        let cgImage: CGImage
        switch resolved {
        case .fullScreen:
            cgImage = try await captureFullScreen(content: content)
        case .activeWindow:
            cgImage = try await captureActiveWindow(content: content)
        case .frontmostApp:
            cgImage = try await captureFrontmostApp(content: content)
        case .region(let rect, let screen):
            cgImage = try await captureRegion(globalRect: rect, screen: screen, content: content)
        }

        return try writeOutputs(
            cgImage: cgImage,
            destinations: request.destinations,
            customPath: request.customPath,
            format: request.format
        )
    }

    // MARK: - Validation

    private func validate(_ request: CaptureRequest) throws {
        if request.destinations.rawValue == 0 {
            throw CaptureError.invalidRequest("destinations is empty.")
        }
        if request.destinations.contains(.fileCustomPath) {
            let dir = request.customPath ?? CapturePreferences.customPath
            if dir == nil {
                throw CaptureError.invalidRequest("customPath not set for .fileCustomPath.")
            }
        }
    }

    // MARK: - SCK content / errors

    @available(macOS 14.0, *)
    private func fetchShareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false,
                                                                         onScreenWindowsOnly: true)
        } catch {
            throw mapSCKError(error)
        }
    }

    private func mapSCKError(_ error: Error) -> CaptureError {
        let ns = error as NSError
        let msg = ns.localizedDescription.lowercased()
        // TCC denial signals — message-based since SCK domains vary across versions.
        if ns.code == -3801
            || ns.domain.contains("TCC")
            || msg.contains("screen recording")
            || msg.contains("permission")
            || msg.contains("not authorized") {
            return .permissionDenied
        }
        return .sckUnavailable(message: ns.localizedDescription)
    }

    // MARK: - Targets

    private enum ResolvedTarget {
        case fullScreen
        case activeWindow
        case frontmostApp
        case region(rect: CGRect, screen: NSScreen)
    }

    @available(macOS 14.0, *)
    private func captureFullScreen(content: SCShareableContent) async throws -> CGImage {
        guard let display = mainDisplay(in: content) else {
            throw CaptureError.targetNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = makeConfig(width: display.width, height: display.height)
        return try await captureImage(filter: filter, config: config)
    }

    @available(macOS 14.0, *)
    private func captureActiveWindow(content: SCShareableContent) async throws -> CGImage {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            throw CaptureError.targetNotFound
        }
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID == frontPID
                && window.isOnScreen
                && window.frame.width > 1
                && window.frame.height > 1
        }
        guard let window = candidates.first else {
            throw CaptureError.targetNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = makeConfig(width: Int(window.frame.width), height: Int(window.frame.height))
        return try await captureImage(filter: filter, config: config)
    }

    @available(macOS 14.0, *)
    private func captureRegion(globalRect: CGRect,
                                screen: NSScreen,
                                content: SCShareableContent) async throws -> CGImage {
        // Find SCDisplay for the chosen NSScreen via NSScreenNumber.
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.targetNotFound
        }

        // Convert NSScreen global (bottom-left, points) → display-local (top-left, points).
        let local = CGRect(
            x: globalRect.origin.x - screen.frame.origin.x,
            y: screen.frame.height - (globalRect.origin.y - screen.frame.origin.y) - globalRect.size.height,
            width: globalRect.size.width,
            height: globalRect.size.height
        )

        let scale = screen.backingScaleFactor
        let outW = max(Int(local.width * scale), 1)
        let outH = max(Int(local.height * scale), 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = makeConfig(width: outW, height: outH)
        config.sourceRect = local
        return try await captureImage(filter: filter, config: config)
    }

    @available(macOS 14.0, *)
    private func captureFrontmostApp(content: SCShareableContent) async throws -> CGImage {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let app = content.applications.first(where: { $0.processID == frontPID }) else {
            throw CaptureError.targetNotFound
        }
        guard let display = mainDisplay(in: content) else {
            throw CaptureError.targetNotFound
        }
        let filter = SCContentFilter(display: display,
                                      including: [app],
                                      exceptingWindows: [])
        let config = makeConfig(width: display.width, height: display.height)
        return try await captureImage(filter: filter, config: config)
    }

    @available(macOS 14.0, *)
    private func mainDisplay(in content: SCShareableContent) -> SCDisplay? {
        content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first
    }

    // MARK: - SCK call / config

    @available(macOS 14.0, *)
    private func makeConfig(width: Int, height: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(width, 1)
        config.height = max(height, 1)
        config.showsCursor = false
        config.scalesToFit = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // sRGB chosen for clipboard/PNG compatibility — accepted GPU cost on P3 displays.
        config.colorSpaceName = CGColorSpace.sRGB
        return config
    }

    @available(macOS 14.0, *)
    private func captureImage(filter: SCContentFilter,
                               config: SCStreamConfiguration) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: config)
        } catch {
            throw mapSCKError(error)
        }
    }

    // MARK: - Destinations

    private func writeOutputs(cgImage: CGImage,
                              destinations: CaptureDestination,
                              customPath: URL?,
                              format: CaptureImageFormat) throws -> CaptureResult {
        // Encode once in an autoreleasepool so the temporary BGRA bitmap is
        // released promptly even on rapid back-to-back captures.
        let encodedData: Data = try autoreleasepool {
            try encode(cgImage: cgImage, format: format)
        }

        var savedFiles: [URL] = []
        var copiedToClipboard = false

        if destinations.contains(.clipboard) {
            copiedToClipboard = writeToClipboard(data: encodedData, format: format)
        }
        if destinations.contains(.fileDesktop) {
            let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            savedFiles.append(try writeToFile(data: encodedData, in: dir, format: format))
        }
        if destinations.contains(.fileCustomPath) {
            // validate() already guarantees a non-nil dir.
            let dir = customPath ?? CapturePreferences.customPath!
            savedFiles.append(try writeToFile(data: encodedData, in: dir, format: format))
        }

        let returnedImage: NSImage? = destinations.contains(.returnImage)
            ? NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            : nil

        return CaptureResult(image: returnedImage,
                             savedFiles: savedFiles,
                             copiedToClipboard: copiedToClipboard)
    }

    private func writeToClipboard(data: Data, format: CaptureImageFormat) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        let pbType: NSPasteboard.PasteboardType
        switch format {
        case .png:  pbType = .png
        case .jpeg: pbType = NSPasteboard.PasteboardType(rawValue: "public.jpeg")
        }
        pb.setData(data, forType: pbType)
        return true
    }

    private func writeToFile(data: Data,
                              in directory: URL,
                              format: CaptureImageFormat) throws -> URL {
        let url = CaptureFileNamer.uniqueURL(in: directory, format: format)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw CaptureError.writeFailed(url, message: error.localizedDescription)
        }
    }

    private func encode(cgImage: CGImage, format: CaptureImageFormat) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        switch format {
        case .png:
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CaptureError.encodingFailed(format: "png", message: "NSBitmapImageRep returned nil")
            }
            return data
        case .jpeg(let quality):
            guard let data = bitmap.representation(using: .jpeg,
                                                    properties: [.compressionFactor: quality]) else {
                throw CaptureError.encodingFailed(format: "jpeg", message: "NSBitmapImageRep returned nil")
            }
            return data
        }
    }
}
