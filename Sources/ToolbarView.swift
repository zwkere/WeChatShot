import Cocoa

protocol WeChatToolbarDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: AnnotationTool?)
    func toolbarDidSelectSize(_ size: StrokeSize)
    func toolbarDidSelectColor(_ color: NSColor)
    func toolbarDidClickUndo()
    func toolbarDidClickOCR()
    func toolbarDidClickPin()
    func toolbarDidClickSave()
    func toolbarDidClickCancel()
    func toolbarDidClickDone()
}

// MARK: - Main Floating WeChat Toolbar + Secondary Style Bar Container
final class WeChatToolbarContainerView: NSView {
    weak var delegate: WeChatToolbarDelegate?

    var selectedTool: AnnotationTool? {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    var selectedSize: StrokeSize = .medium {
        didSet { needsDisplay = true }
    }

    var selectedColor: NSColor = WeChatTheme.palette[0].color {
        didSet { needsDisplay = true }
    }

    var canUndo: Bool = false {
        didSet { needsDisplay = true }
    }

    /// True if the secondary style bar should appear ABOVE the main bar (when near bottom of screen)
    var styleBarAbove: Bool = false {
        didSet { needsDisplay = true }
    }

    private enum ActionButtonID: CaseIterable {
        case tool(AnnotationTool)
        case undo
        case ocr
        case pin
        case save
        case cancel
        case done

        static var allCases: [ActionButtonID] {
            return AnnotationTool.allCases.map { .tool($0) } + [.undo, .ocr, .pin, .save, .cancel, .done]
        }

        var tooltip: String {
            switch self {
            case .tool(let t): return t.title
            case .undo:        return "撤销 (⌘Z)"
            case .ocr:         return "提取图中文字 (OCR)"
            case .pin:         return "在屏幕上贴图 (Pin)"
            case .save:        return "保存截图 (⌘S)"
            case .cancel:      return "退出截图 (ESC)"
            case .done:        return "完成并复制 (Enter)"
            }
        }

        var symbolName: String {
            switch self {
            case .tool(let t): return t.symbolName
            case .undo:        return "arrow.uturn.backward"
            case .ocr:         return "text.viewfinder"
            case .pin:         return "pin"
            case .save:        return "square.and.arrow.down"
            case .cancel:      return "xmark"
            case .done:        return "checkmark"
            }
        }
    }

    private struct ButtonLayout {
        let id: ActionButtonID
        let rect: NSRect
    }

    private var buttonLayouts: [ButtonLayout] = []
    private var dividerXs: [CGFloat] = []
    private var hoveredButtonIndex: Int? = nil

    // Secondary style bar item hit rects
    private var sizeRects: [(size: StrokeSize, rect: NSRect)] = []
    private var colorRects: [(color: NSColor, rect: NSRect)] = []

    static let mainBarHeight: CGFloat = 38.0
    static let styleBarHeight: CGFloat = 36.0
    static let styleBarGap: CGFloat = 8.0
    static let totalHeight: CGFloat = mainBarHeight + styleBarGap + styleBarHeight
    static let totalWidth: CGFloat = 446.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
    }

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    private var mainBarRect: NSRect {
        if styleBarAbove {
            return NSRect(x: 0, y: 0, width: Self.totalWidth, height: Self.mainBarHeight)
        } else {
            return NSRect(
                x: 0,
                y: bounds.height - Self.mainBarHeight,
                width: Self.totalWidth,
                height: Self.mainBarHeight
            )
        }
    }

    private func computeLayouts() {
        buttonLayouts.removeAll()
        dividerXs.removeAll()
        sizeRects.removeAll()
        colorRects.removeAll()

        let barRect = mainBarRect
        var x: CGFloat = 8.0
        let btnW: CGFloat = 32.0
        let btnH: CGFloat = 30.0
        let btnY = barRect.minY + (barRect.height - btnH) / 2.0

        // 1. 6 Annotation Tools
        for tool in AnnotationTool.allCases {
            let r = NSRect(x: x, y: btnY, width: btnW, height: btnH)
            buttonLayouts.append(ButtonLayout(id: .tool(tool), rect: r))
            x += btnW + 2.0
        }

        // Divider 1
        x += 4.0
        dividerXs.append(x)
        x += 5.0

        // 2. Undo
        buttonLayouts.append(ButtonLayout(id: .undo, rect: NSRect(x: x, y: btnY, width: btnW, height: btnH)))
        x += btnW + 2.0

        // Divider 2
        x += 4.0
        dividerXs.append(x)
        x += 5.0

        // 3. OCR, Pin, Save
        for id in [ActionButtonID.ocr, .pin, .save] {
            buttonLayouts.append(ButtonLayout(id: id, rect: NSRect(x: x, y: btnY, width: btnW, height: btnH)))
            x += btnW + 2.0
        }

        // Divider 3
        x += 4.0
        dividerXs.append(x)
        x += 5.0

        // 4. Cancel & Done
        buttonLayouts.append(ButtonLayout(id: .cancel, rect: NSRect(x: x, y: btnY, width: btnW, height: btnH)))
        x += btnW + 4.0
        buttonLayouts.append(ButtonLayout(id: .done, rect: NSRect(x: x, y: btnY, width: 38.0, height: btnH)))

        // Secondary Style Bar Layout (if a tool is active)
        guard let activeTool = selectedTool else { return }

        let styleW: CGFloat = activeTool.supportsColorSelection ? 276.0 : 104.0
        let activeToolRect = buttonLayouts.first(where: {
            if case .tool(let t) = $0.id, t == activeTool { return true }
            return false
        })?.rect ?? .zero

        let idealX = activeToolRect.midX - 36.0
        let styleX = max(0, min(idealX, bounds.width - styleW))
        let styleY: CGFloat = styleBarAbove ? (Self.mainBarHeight + Self.styleBarGap) : 0.0
        let styleRect = NSRect(x: styleX, y: styleY, width: styleW, height: Self.styleBarHeight)

        var sx = styleRect.minX + 10.0
        let sy = styleRect.minY + (styleRect.height - 24.0) / 2.0

        // 3 Stroke Sizes
        for size in StrokeSize.allCases {
            let r = NSRect(x: sx, y: sy, width: 24.0, height: 24.0)
            sizeRects.append((size, r))
            sx += 28.0
        }

        if activeTool.supportsColorSelection {
            sx += 10.0
            for item in WeChatTheme.palette {
                let r = NSRect(x: sx, y: sy + 2.0, width: 20.0, height: 20.0)
                colorRects.append((item.color, r))
                sx += 24.0
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        computeLayouts()

        let barRect = mainBarRect
        drawRoundedDarkPanel(in: barRect)

        // Draw dividers
        NSColor(calibratedWhite: 1.0, alpha: 0.15).setStroke()
        for dx in dividerXs {
            let path = NSBezierPath()
            path.lineWidth = 1.0
            path.move(to: NSPoint(x: dx, y: barRect.minY + 9.0))
            path.line(to: NSPoint(x: dx, y: barRect.maxY - 9.0))
            path.stroke()
        }

        // Draw buttons
        for (index, item) in buttonLayouts.enumerated() {
            let isHovered = (hoveredButtonIndex == index)
            var isSelected = false
            var isEnabled = true

            switch item.id {
            case .tool(let t):
                isSelected = (selectedTool == t)
            case .undo:
                isEnabled = canUndo
            default:
                break
            }

            if isSelected {
                let bg = NSBezierPath(roundedRect: item.rect.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
                NSColor(calibratedWhite: 1.0, alpha: 0.14).setFill()
                bg.fill()
            } else if isHovered && isEnabled {
                let bg = NSBezierPath(roundedRect: item.rect.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
                if case .done = item.id {
                    WeChatTheme.green.withAlphaComponent(0.22).setFill()
                } else {
                    NSColor(calibratedWhite: 1.0, alpha: 0.10).setFill()
                }
                bg.fill()
            }

            // Icon color
            let iconColor: NSColor
            if !isEnabled {
                iconColor = NSColor(calibratedWhite: 1.0, alpha: 0.28)
            } else if isSelected {
                iconColor = WeChatTheme.green
            } else if case .done = item.id {
                iconColor = WeChatTheme.green
            } else if case .cancel = item.id, isHovered {
                iconColor = NSColor(srgbRed: 0.98, green: 0.35, blue: 0.35, alpha: 1.0)
            } else {
                iconColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
            }

            drawSymbol(named: item.id.symbolName, in: item.rect, color: iconColor)
        }

        // Draw Secondary Style Bar if an annotation tool is selected
        if let activeTool = selectedTool {
            drawSecondaryStyleBar(for: activeTool)
        }
    }

    private func drawSecondaryStyleBar(for activeTool: AnnotationTool) {
        let styleW: CGFloat = activeTool.supportsColorSelection ? 276.0 : 104.0
        let activeToolRect = buttonLayouts.first(where: {
            if case .tool(let t) = $0.id, t == activeTool { return true }
            return false
        })?.rect ?? .zero

        let idealX = activeToolRect.midX - 36.0
        let styleX = max(0, min(idealX, bounds.width - styleW))
        let styleY: CGFloat = styleBarAbove ? (Self.mainBarHeight + Self.styleBarGap) : 0.0
        let styleRect = NSRect(x: styleX, y: styleY, width: styleW, height: Self.styleBarHeight)

        // Draw pointer triangle connecting main bar and style bar
        let arrowX = max(styleRect.minX + 14.0, min(activeToolRect.midX, styleRect.maxX - 14.0))
        let triangle = NSBezierPath()
        if styleBarAbove {
            triangle.move(to: NSPoint(x: arrowX - 6, y: styleRect.minY))
            triangle.line(to: NSPoint(x: arrowX + 6, y: styleRect.minY))
            triangle.line(to: NSPoint(x: arrowX, y: styleRect.minY - 6))
        } else {
            triangle.move(to: NSPoint(x: arrowX - 6, y: styleRect.maxY))
            triangle.line(to: NSPoint(x: arrowX + 6, y: styleRect.maxY))
            triangle.line(to: NSPoint(x: arrowX, y: styleRect.maxY + 6))
        }
        triangle.close()
        WeChatTheme.toolbarBg.setFill()
        triangle.fill()

        drawRoundedDarkPanel(in: styleRect)

        // Draw 3 size dots
        for (size, rect) in sizeRects {
            let isCurrent = (selectedSize == size)
            let d = size.dotDiameter
            let dotRect = NSRect(
                x: rect.midX - d / 2.0,
                y: rect.midY - d / 2.0,
                width: d,
                height: d
            )
            let dotPath = NSBezierPath(ovalIn: dotRect)
            if isCurrent {
                WeChatTheme.green.setFill()
            } else {
                NSColor(calibratedWhite: 0.72, alpha: 1.0).setFill()
            }
            dotPath.fill()
        }

        if activeTool.supportsColorSelection {
            // Divider
            if let lastSizeRect = sizeRects.last?.rect {
                let divX = lastSizeRect.maxX + 6.0
                NSColor(calibratedWhite: 1.0, alpha: 0.15).setStroke()
                let path = NSBezierPath()
                path.lineWidth = 1.0
                path.move(to: NSPoint(x: divX, y: styleRect.minY + 8.0))
                path.line(to: NSPoint(x: divX, y: styleRect.maxY - 8.0))
                path.stroke()
            }

            // Draw 7 color swatches
            for (color, rect) in colorRects {
                let isSelected = colorsAreEqual(color, selectedColor)
                let swatchRect = isSelected ? rect.insetBy(dx: 1.0, dy: 1.0) : rect.insetBy(dx: 2.5, dy: 2.5)
                let path = NSBezierPath(roundedRect: swatchRect, xRadius: 3.0, yRadius: 3.0)
                color.setFill()
                path.fill()

                if isSelected {
                    NSColor.white.setStroke()
                    path.lineWidth = 2.0
                    path.stroke()
                } else {
                    NSColor(calibratedWhite: 1.0, alpha: 0.25).setStroke()
                    path.lineWidth = 0.8
                    path.stroke()
                }
            }
        }
    }

    private func drawRoundedDarkPanel(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 6
        shadow.set()

        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 6.0, yRadius: 6.0)
        WeChatTheme.toolbarBg.setFill()
        bgPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6.0, yRadius: 6.0)
        NSColor(calibratedWhite: 1.0, alpha: 0.14).setStroke()
        borderPath.lineWidth = 1.0
        borderPath.stroke()
    }

    private func drawSymbol(named name: String, in rect: NSRect, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)
        if let baseImg = NSImage(systemSymbolName: name, accessibilityDescription: nil),
           let symbolImg = baseImg.withSymbolConfiguration(config) {
            let imgSize = symbolImg.size
            let drawRect = NSRect(
                x: rect.midX - imgSize.width / 2.0,
                y: rect.midY - imgSize.height / 2.0,
                width: imgSize.width,
                height: imgSize.height
            )

            // Tint symbol image
            if let tinted = symbolImg.copy() as? NSImage {
                tinted.lockFocus()
                color.set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: drawRect)
            }
        }
    }

    private func colorsAreEqual(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ca = a.usingColorSpace(.sRGB), let cb = b.usingColorSpace(.sRGB) else {
            return a == b
        }
        return abs(ca.redComponent - cb.redComponent) < 0.02 &&
               abs(ca.greenComponent - cb.greenComponent) < 0.02 &&
               abs(ca.blueComponent - cb.blueComponent) < 0.02
    }

    // MARK: - Mouse Interaction
    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        NSCursor.arrow.set()

        var foundIndex: Int? = nil
        for (idx, item) in buttonLayouts.enumerated() {
            if item.rect.contains(pt) {
                foundIndex = idx
                self.toolTip = item.id.tooltip
                break
            }
        }
        if foundIndex == nil {
            self.toolTip = nil
        }
        if hoveredButtonIndex != foundIndex {
            hoveredButtonIndex = foundIndex
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredButtonIndex != nil {
            hoveredButtonIndex = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        // 1. Check main toolbar buttons
        for item in buttonLayouts {
            if item.rect.contains(pt) {
                handleButtonClick(item.id)
                return
            }
        }

        // 2. Check stroke size dots
        for (size, rect) in sizeRects {
            if rect.contains(pt) {
                selectedSize = size
                delegate?.toolbarDidSelectSize(size)
                return
            }
        }

        // 3. Check color swatches
        for (color, rect) in colorRects {
            if rect.contains(pt) {
                selectedColor = color
                delegate?.toolbarDidSelectColor(color)
                return
            }
        }
    }

    private func handleButtonClick(_ id: ActionButtonID) {
        switch id {
        case .tool(let t):
            if selectedTool == t {
                selectedTool = nil
            } else {
                selectedTool = t
            }
            delegate?.toolbarDidSelectTool(selectedTool)
        case .undo:
            if canUndo {
                delegate?.toolbarDidClickUndo()
            }
        case .ocr:
            delegate?.toolbarDidClickOCR()
        case .pin:
            delegate?.toolbarDidClickPin()
        case .save:
            delegate?.toolbarDidClickSave()
        case .cancel:
            delegate?.toolbarDidClickCancel()
        case .done:
            delegate?.toolbarDidClickDone()
        }
    }
}
