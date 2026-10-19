import Cocoa
import CoreImage
import ScreenCaptureKit

final class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    /// Check if Screen Recording permission is currently granted
    var hasScreenRecordingPermission: Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission from macOS
    @discardableResult
    func requestPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    /// Open macOS System Settings -> Privacy & Security -> Screen Recording
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Enumerate all visible on-screen windows (excluding desktop elements & our own app)
    /// Converted to target screen local coordinates (bottom-left origin relative to screen.frame)
    func detectOnScreenWindows(for screen: NSScreen) -> [DetectedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // Primary screen height is used by Quartz (CGWindow) for top-left coordinate origin
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let myPID = ProcessInfo.processInfo.processIdentifier
        var results: [DetectedWindow] = []

        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID else { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            // Normal application windows are on layer 0
            if layer != 0 { continue }

            let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 1.0
            if alpha < 0.05 { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let qX = boundsDict["X"],
                  let qY = boundsDict["Y"],
                  let qW = boundsDict["Width"],
                  let qH = boundsDict["Height"],
                  qW >= 24, qH >= 24 else {
                continue
            }

            // Convert from Quartz global coordinates (top-left of primary screen)
            // to AppKit global coordinates (bottom-left of primary screen)
            let appKitGlobalY = primaryScreenHeight - qY - qH
            let globalRect = NSRect(x: qX, y: appKitGlobalY, width: qW, height: qH)

            // Intersect with target screen frame
            let clippedGlobal = globalRect.intersection(screen.frame)
            guard !clippedGlobal.isNull && clippedGlobal.width >= 20 && clippedGlobal.height >= 20 else {
                continue
            }

            // Convert to local coordinates of the overlay window on `screen`
            let localRect = NSRect(
                x: clippedGlobal.origin.x - screen.frame.origin.x,
                y: clippedGlobal.origin.y - screen.frame.origin.y,
                width: clippedGlobal.width,
                height: clippedGlobal.height
            )

            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let title = info[kCGWindowName as String] as? String ?? ""

            results.append(DetectedWindow(
                windowID: windowID,
                ownerName: ownerName,
                title: title,
                frame: localRect
            ))
        }

        // Also add the full screen itself as the last fallback window
        let fullScreenLocal = NSRect(origin: .zero, size: screen.frame.size)
        results.append(DetectedWindow(
            windowID: 0,
            ownerName: "Screen",
            title: "全屏",
            frame: fullScreenLocal
        ))

        return results
    }

    /// Capture full screen image for the specified NSScreen
    func captureScreen(_ screen: NSScreen, completion: @escaping (NSImage?, CGImage?) -> Void) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            completion(nil, nil)
            return
        }

        // Use ScreenCaptureKit first for high-performance Retina capture
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self = self else { return }

            if let content = content,
               let scDisplay = content.displays.first(where: { $0.displayID == displayID }) {
                let currentPID = ProcessInfo.processInfo.processIdentifier
                let excludedApps = content.applications.filter { $0.processID == currentPID }
                let filter = SCContentFilter(display: scDisplay, excludingApplications: excludedApps, exceptingWindows: [])

                let config = SCStreamConfiguration()
                let scaleFactor = screen.backingScaleFactor
                config.width = Int(screen.frame.width * scaleFactor)
                config.height = Int(screen.frame.height * scaleFactor)
                config.showsCursor = false
                config.capturesAudio = false

                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { cgImage, scError in
                    if let cgImage = cgImage {
                        let nsImage = NSImage(cgImage: cgImage, size: screen.frame.size)
                        DispatchQueue.main.async {
                            completion(nsImage, cgImage)
                        }
                    } else {
                        self.captureViaScreencaptureCLI(screen: screen, completion: completion)
                    }
                }
            } else {
                self.captureViaScreencaptureCLI(screen: screen, completion: completion)
            }
        }
    }

    /// Fallback capture using /usr/sbin/screencapture -x (silent)
    private func captureViaScreencaptureCLI(screen: NSScreen, completion: @escaping (NSImage?, CGImage?) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            let tempPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("wechatshot_temp_\(UUID().uuidString).png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -x: no sound, -R: rect
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let qX = Int(screen.frame.origin.x)
            let qY = Int(primaryHeight - screen.frame.origin.y - screen.frame.height)
            let qW = Int(screen.frame.width)
            let qH = Int(screen.frame.height)
            process.arguments = ["-x", "-R\(qX),\(qY),\(qW),\(qH)", tempPath]

            do {
                try process.run()
                process.waitUntilExit()
                if FileManager.default.fileExists(atPath: tempPath),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)),
                   let bitmap = NSBitmapImageRep(data: data),
                   let cgImage = bitmap.cgImage {
                    try? FileManager.default.removeItem(atPath: tempPath)
                    let nsImage = NSImage(cgImage: cgImage, size: screen.frame.size)
                    DispatchQueue.main.async {
                        completion(nsImage, cgImage)
                    }
                    return
                }
            } catch {
                // Ignore and fall through to synthetic canvas fallback
            }
            try? FileManager.default.removeItem(atPath: tempPath)

            // If Screen Recording permission hasn't been granted yet, generate a helpful wallpaper canvas
            let fallback = self.createFallbackCanvasImage(size: screen.frame.size, scale: screen.backingScaleFactor)
            DispatchQueue.main.async {
                completion(fallback.0, fallback.1)
            }
        }
    }

    /// Generate a pixelated mosaic image from the source CGImage for the Mosaic brush tool
    func createMosaicImage(from cgImage: CGImage, screenSize: NSSize, pixelScale: CGFloat = 18.0) -> NSImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(pixelScale, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY), forKey: kCIInputCenterKey)

        guard let output = filter.outputImage?.cropped(to: ciImage.extent),
              let outCG = ciContext.createCGImage(output, from: ciImage.extent) else {
            return nil
        }
        return NSImage(cgImage: outCG, size: screenSize)
    }

    /// Creates a fallback preview canvas if macOS Screen Recording permission is not enabled yet
    private func createFallbackCanvasImage(size: NSSize, scale: CGFloat) -> (NSImage, CGImage?) {
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.14, green: 0.18, blue: 0.24, alpha: 1.0),
            NSColor(srgbRed: 0.09, green: 0.12, blue: 0.16, alpha: 1.0)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -45)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 0.9),
            .paragraphStyle: paragraph
        ]
        let hint = "请在「系统设置 -> 隐私与安全性 -> 录屏与系统录音」中授权 WeChatShot\n授权后即可截取真实屏幕画面（当前为演示画布）"
        let rect = NSRect(x: 0, y: size.height / 2 - 30, width: size.width, height: 60)
        hint.draw(in: rect, withAttributes: attrs)
        image.unlockFocus()

        var proposedRect = NSRect(origin: .zero, size: size)
        let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        return (image, cgImage)
    }
}
