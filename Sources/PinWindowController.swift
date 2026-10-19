import Cocoa

final class PinManager {
    static let shared = PinManager()
    private(set) var controllers: [PinWindowController] = []

    var onPinCountChanged: ((Int) -> Void)?

    func pin(image: NSImage, screenRect: NSRect) {
        let controller = PinWindowController(image: image, screenRect: screenRect)
        controllers.append(controller)
        controller.showWindow(nil)
        onPinCountChanged?(controllers.count)
    }

    func remove(_ controller: PinWindowController) {
        controllers.removeAll { $0 === controller }
        onPinCountChanged?(controllers.count)
    }

    func closeAll() {
        let copy = controllers
        for c in copy {
            c.closePin()
        }
    }
}

final class PinWindowController: NSWindowController {
    private let sourceImage: NSImage
    private let originalSize: NSSize
    private var zoomScale: CGFloat = 1.0
    private var pinView: PinContentView!

    init(image: NSImage, screenRect: NSRect) {
        self.sourceImage = image
        self.originalSize = screenRect.size

        let panel = PinPanel(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        pinView = PinContentView(frame: NSRect(origin: .zero, size: screenRect.size), image: image, owner: self)
        panel.contentView = pinView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func zoom(by delta: CGFloat) {
        guard let window = self.window else { return }
        let factor: CGFloat = delta > 0 ? 1.08 : 0.92
        let newScale = max(0.25, min(zoomScale * factor, 4.0))
        guard abs(newScale - zoomScale) > 0.001 else { return }
        zoomScale = newScale

        let newW = round(originalSize.width * zoomScale)
        let newH = round(originalSize.height * zoomScale)
        let oldFrame = window.frame
        let newFrame = NSRect(
            x: round(oldFrame.midX - newW / 2.0),
            y: round(oldFrame.midY - newH / 2.0),
            width: newW,
            height: newH
        )
        window.setFrame(newFrame, display: true, animate: false)
        pinView.frame = NSRect(origin: .zero, size: newFrame.size)
        pinView.needsDisplay = true
    }

    func resetZoom() {
        guard let window = self.window else { return }
        zoomScale = 1.0
        let oldFrame = window.frame
        let newFrame = NSRect(
            x: round(oldFrame.midX - originalSize.width / 2.0),
            y: round(oldFrame.midY - originalSize.height / 2.0),
            width: originalSize.width,
            height: originalSize.height
        )
        window.setFrame(newFrame, display: true, animate: true)
        pinView.frame = NSRect(origin: .zero, size: newFrame.size)
        pinView.needsDisplay = true
    }

    func copyImage() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([sourceImage])
    }

    func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        savePanel.nameFieldStringValue = "WeChatShot_Pin_\(formatter.string(from: Date())).png"
        savePanel.level = .modalPanel

        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let tiff = sourceImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }

    func runOCR() {
        OCRWindowController.shared.recognizeAndShow(image: sourceImage)
    }

    func setWindowAlpha(_ alpha: CGFloat) {
        window?.alphaValue = alpha
    }

    func closePin() {
        window?.close()
        PinManager.shared.remove(self)
    }
}

private final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PinContentView: NSView {
    private let image: NSImage
    private weak var owner: PinWindowController?
    private var isHovered: Bool = false
    private let closeButtonSize: CGFloat = 22.0

    init(frame frameRect: NSRect, image: NSImage, owner: PinWindowController) {
        self.image = image
        self.owner = owner
        super.init(frame: frameRect)

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var closeBtnRect: NSRect {
        return NSRect(
            x: bounds.width - closeButtonSize - 6.0,
            y: bounds.height - closeButtonSize - 6.0,
            width: closeButtonSize,
            height: closeButtonSize
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: bounds)

        // Subtle border (WeChat green when hovered, thin white/black frame otherwise)
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 1.0, dy: 1.0))
        if isHovered {
            WeChatTheme.green.setStroke()
            borderPath.lineWidth = 2.0
            borderPath.stroke()

            // Draw close button at top-right
            let cRect = closeBtnRect
            let cPath = NSBezierPath(ovalIn: cRect)
            NSColor(calibratedWhite: 0.12, alpha: 0.85).setFill()
            cPath.fill()
            NSColor(calibratedWhite: 1.0, alpha: 0.25).setStroke()
            cPath.lineWidth = 1.0
            cPath.stroke()

            // Draw X
            let xPath = NSBezierPath()
            let inset: CGFloat = 6.5
            xPath.move(to: NSPoint(x: cRect.minX + inset, y: cRect.minY + inset))
            xPath.line(to: NSPoint(x: cRect.maxX - inset, y: cRect.maxY - inset))
            xPath.move(to: NSPoint(x: cRect.minX + inset, y: cRect.maxY - inset))
            xPath.line(to: NSPoint(x: cRect.maxX - inset, y: cRect.minY + inset))
            NSColor.white.setStroke()
            xPath.lineWidth = 1.6
            xPath.lineCapStyle = .round
            xPath.stroke()
        } else {
            NSColor(calibratedWhite: 1.0, alpha: 0.25).setStroke()
            borderPath.lineWidth = 1.0
            borderPath.stroke()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let pt = convert(event.locationInWindow, from: nil)
        if isHovered && closeBtnRect.contains(pt) {
            owner?.closePin()
            return
        }
        if event.clickCount == 2 {
            owner?.closePin()
            return
        }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0.1 else { return }
        owner?.zoom(by: event.scrollingDeltaY)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            owner?.closePin()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            owner?.copyImage()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
            owner?.saveImage()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
            owner?.closePin()
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "贴图菜单")
        let copyItem = NSMenuItem(title: "复制图片", action: #selector(handleCopy), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: "另存为...", action: #selector(handleSave), keyEquivalent: "s")
        saveItem.target = self
        menu.addItem(saveItem)

        let ocrItem = NSMenuItem(title: "提取文字 (OCR)", action: #selector(handleOCR), keyEquivalent: "")
        ocrItem.target = self
        menu.addItem(ocrItem)

        menu.addItem(.separator())

        let resetSizeItem = NSMenuItem(title: "还原原始尺寸 (100%)", action: #selector(handleResetZoom), keyEquivalent: "0")
        resetSizeItem.target = self
        menu.addItem(resetSizeItem)

        let alphaMenu = NSMenu(title: "透明度")
        for (title, val) in [("100% (不透明)", 1.0), ("80%", 0.8), ("50%", 0.5)] {
            let item = NSMenuItem(title: title, action: #selector(handleAlpha(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = CGFloat(val)
            alphaMenu.addItem(item)
        }
        let alphaParent = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        alphaParent.submenu = alphaMenu
        menu.addItem(alphaParent)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "关闭贴图 (双击 / ESC)", action: #selector(handleClose), keyEquivalent: "w")
        closeItem.target = self
        menu.addItem(closeItem)

        return menu
    }

    @objc private func handleCopy() { owner?.copyImage() }
    @objc private func handleSave() { owner?.saveImage() }
    @objc private func handleOCR() { owner?.runOCR() }
    @objc private func handleResetZoom() { owner?.resetZoom() }
    @objc private func handleAlpha(_ sender: NSMenuItem) {
        if let alpha = sender.representedObject as? CGFloat {
            owner?.setWindowAlpha(alpha)
        }
    }
    @objc private func handleClose() { owner?.closePin() }
}
