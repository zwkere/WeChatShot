import Cocoa

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ScreenshotCoordinator: ScreenshotCanvasDelegate {
    static let shared = ScreenshotCoordinator()

    private var activeWindow: OverlayPanel?
    private(set) var isCapturing: Bool = false

    var onScreenshotCompleted: ((NSImage) -> Void)?

    private init() {}

    func startScreenshot() {
        guard !isCapturing else { return }
        isCapturing = true

        // Determine the screen where the mouse cursor is currently located
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen = targetScreen else {
            isCapturing = false
            return
        }

        // Detect all visible system windows BEFORE showing our overlay window
        let detectedWindows = ScreenCaptureManager.shared.detectOnScreenWindows(for: screen)

        // Capture full screen image
        ScreenCaptureManager.shared.captureScreen(screen) { [weak self] nsImage, cgImage in
            guard let self = self, let nsImage = nsImage else {
                self?.isCapturing = false
                return
            }

            let mosaicImg: NSImage?
            if let cgImage = cgImage {
                mosaicImg = ScreenCaptureManager.shared.createMosaicImage(
                    from: cgImage,
                    screenSize: screen.frame.size,
                    pixelScale: 18.0 * screen.backingScaleFactor
                )
            } else {
                mosaicImg = nil
            }

            self.presentOverlayWindow(
                on: screen,
                screenImage: nsImage,
                screenCGImage: cgImage,
                mosaicImage: mosaicImg,
                detectedWindows: detectedWindows
            )
        }
    }

    private func presentOverlayWindow(
        on screen: NSScreen,
        screenImage: NSImage,
        screenCGImage: CGImage?,
        mosaicImage: NSImage?,
        detectedWindows: [DetectedWindow]
    ) {
        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = true
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let canvasFrame = NSRect(origin: .zero, size: screen.frame.size)
        let canvasView = ScreenshotCanvasView(
            frame: canvasFrame,
            screenImage: screenImage,
            screenCGImage: screenCGImage,
            mosaicImage: mosaicImage,
            detectedWindows: detectedWindows
        )
        canvasView.delegate = self
        panel.contentView = canvasView

        self.activeWindow = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(canvasView)
        NSCursor.crosshair.set()
    }

    func closeOverlay() {
        NSCursor.arrow.set()
        activeWindow?.orderOut(nil)
        activeWindow?.close()
        activeWindow = nil
        isCapturing = false
    }

    // MARK: - ScreenshotCanvasDelegate
    func canvasDidCancel() {
        closeOverlay()
    }

    func canvasDidFinishWithImage(_ image: NSImage, selectionRectInScreen: NSRect) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        NSSound(named: "Tink")?.play()
        closeOverlay()
        onScreenshotCompleted?(image)
    }

    func canvasDidRequestSave(_ image: NSImage) {
        closeOverlay()

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        savePanel.nameFieldStringValue = "WeChatShot_\(formatter.string(from: Date())).png"
        savePanel.level = .floating

        NSApp.activate(ignoringOtherApps: true)
        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
        onScreenshotCompleted?(image)
    }

    func canvasDidRequestPin(_ image: NSImage, selectionRectInScreen: NSRect) {
        closeOverlay()
        PinManager.shared.pin(image: image, screenRect: selectionRectInScreen)
        onScreenshotCompleted?(image)
    }

    func canvasDidRequestOCR(_ image: NSImage) {
        closeOverlay()
        OCRWindowController.shared.recognizeAndShow(image: image)
        onScreenshotCompleted?(image)
    }
}
