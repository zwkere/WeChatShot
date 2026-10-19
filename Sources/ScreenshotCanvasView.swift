import Cocoa

protocol ScreenshotCanvasDelegate: AnyObject {
    func canvasDidCancel()
    func canvasDidFinishWithImage(_ image: NSImage, selectionRectInScreen: NSRect)
    func canvasDidRequestSave(_ image: NSImage)
    func canvasDidRequestPin(_ image: NSImage, selectionRectInScreen: NSRect)
    func canvasDidRequestOCR(_ image: NSImage)
}

final class ScreenshotCanvasView: NSView, WeChatToolbarDelegate, NSTextFieldDelegate {
    weak var delegate: ScreenshotCanvasDelegate?

    private let screenImage: NSImage
    private let screenCGImage: CGImage?
    private let mosaicImage: NSImage?
    private let detectedWindows: [DetectedWindow]

    // Selection State
    private(set) var isSelectionLocked: Bool = false
    private(set) var selectionRect: NSRect = .zero
    private var hoveredWindow: DetectedWindow? = nil
    private var mouseLocation: NSPoint = .zero

    // Interaction State
    private enum DragMode {
        case none
        case creatingSelection(origin: NSPoint)
        case movingSelection(initialRect: NSRect, mouseOrigin: NSPoint)
        case resizingSelection(handle: ResizeHandle, initialRect: NSRect)
        case drawingAnnotation
    }
    private var dragMode: DragMode = .none

    // Annotations
    private var annotations: [AnnotationItem] = []
    private var currentAnnotation: AnnotationItem? = nil

    // Inline Text Input
    private var activeTextField: NSTextField? = nil
    private var activeTextPosition: NSPoint = .zero

    // Floating Toolbar
    private let toolbarView = WeChatToolbarContainerView(
        frame: NSRect(
            x: 0,
            y: 0,
            width: WeChatToolbarContainerView.totalWidth,
            height: WeChatToolbarContainerView.totalHeight
        )
    )

    init(
        frame: NSRect,
        screenImage: NSImage,
        screenCGImage: CGImage?,
        mosaicImage: NSImage?,
        detectedWindows: [DetectedWindow]
    ) {
        self.screenImage = screenImage
        self.screenCGImage = screenCGImage
        self.mosaicImage = mosaicImage
        self.detectedWindows = detectedWindows
        super.init(frame: frame)

        toolbarView.delegate = self
        toolbarView.isHidden = true
        addSubview(toolbarView)

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

    // MARK: - Coordinate & Hit Helpers
    private var activeDisplayRect: NSRect {
        if isSelectionLocked || isCreatingOrResizing {
            return selectionRect
        } else if let hw = hoveredWindow {
            return hw.frame
        }
        return .zero
    }

    private var isCreatingOrResizing: Bool {
        switch dragMode {
        case .creatingSelection, .resizingSelection:
            return true
        default:
            return false
        }
    }

    private func hitTestResizeHandle(at point: NSPoint) -> ResizeHandle? {
        guard isSelectionLocked, selectionRect.width > 0 else { return nil }
        for handle in ResizeHandle.allCases {
            let hRect = handle.handleRect(in: selectionRect, size: 12.0)
            if hRect.contains(point) {
                return handle
            }
        }
        return nil
    }

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 1. Draw full-screen background screenshot
        screenImage.draw(in: bounds)

        let selRect = activeDisplayRect

        // 2. Draw dark translucent mask outside selection rect
        NSGraphicsContext.saveGraphicsState()
        let maskPath = NSBezierPath(rect: bounds)
        if selRect.width > 1 && selRect.height > 1 {
            maskPath.appendRect(selRect)
            maskPath.windingRule = .evenOdd
        }
        WeChatTheme.maskColor.setFill()
        maskPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 3. Draw Annotations clipped to selectionRect
        if selRect.width > 1 && selRect.height > 1 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selRect).addClip()
            drawAllAnnotations(in: selRect)
            NSGraphicsContext.restoreGraphicsState()

            // 4. Draw Selection Border (WeChat Green #07C160)
            let borderPath = NSBezierPath(rect: selRect.insetBy(dx: -0.5, dy: -0.5))
            WeChatTheme.green.setStroke()
            borderPath.lineWidth = isSelectionLocked ? 1.5 : 2.5
            borderPath.stroke()

            // 5. Draw 8 Resize Handles if locked or creating
            if isSelectionLocked || isCreatingOrResizing {
                drawResizeHandles(for: selRect)
            }

            // 6. Draw Top-Left Dimensions Badge ("W × H")
            drawDimensionsBadge(for: selRect)
        }

        // 7. Draw WeChat Magnifier Loupe when selecting or resizing
        if !isSelectionLocked || isCreatingOrResizing {
            drawMagnifierLoupe(at: mouseLocation)
        }
    }

    private func drawAllAnnotations(in clipRect: NSRect) {
        var allItems = annotations
        if let current = currentAnnotation {
            allItems.append(current)
        }

        for item in allItems {
            drawAnnotationItem(item)
        }
    }

    private func drawAnnotationItem(_ item: AnnotationItem) {
        switch item.tool {
        case .rectangle:
            let r = item.boundingRect
            guard r.width > 1 || r.height > 1 else { return }
            let path = NSBezierPath(rect: r)
            path.lineWidth = item.size.lineWidth
            path.lineJoinStyle = .miter
            item.color.setStroke()
            path.stroke()

        case .ellipse:
            let r = item.boundingRect
            guard r.width > 1 || r.height > 1 else { return }
            let path = NSBezierPath(ovalIn: r)
            path.lineWidth = item.size.lineWidth
            item.color.setStroke()
            path.stroke()

        case .arrow:
            let dist = hypot(item.endPoint.x - item.startPoint.x, item.endPoint.y - item.startPoint.y)
            guard dist > 4.0 else { return }
            let path = createWeChatArrowPath(from: item.startPoint, to: item.endPoint, size: item.size)
            item.color.setFill()
            path.fill()

        case .brush:
            guard item.points.count >= 2 else { return }
            let path = createSmoothBrushPath(points: item.points)
            path.lineWidth = item.size.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            item.color.setStroke()
            path.stroke()

        case .mosaic:
            guard item.points.count >= 2, let mosaicImg = mosaicImage else { return }
            NSGraphicsContext.saveGraphicsState()
            let strokePath = createSmoothBrushPath(points: item.points)
            let cgPath = bezierPathToCGPath(strokePath)
            let strokedCGPath = cgPath.copy(
                strokingWithWidth: item.size.mosaicBrushWidth,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.addPath(strokedCGPath)
                ctx.clip()
                mosaicImg.draw(in: bounds)
            }
            NSGraphicsContext.restoreGraphicsState()

        case .text:
            guard !item.text.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: item.size.fontSize, weight: .medium),
                .foregroundColor: item.color
            ]
            (item.text as NSString).draw(at: item.startPoint, withAttributes: attrs)
        }
    }

    /// Creates WeChat's signature sleek tapered filled arrow polygon
    private func createWeChatArrowPath(from start: NSPoint, to end: NSPoint, size: StrokeSize) -> NSBezierPath {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        let angle = atan2(dy, dx)

        let headLength: CGFloat
        let headHalfWidth: CGFloat
        let neckHalfWidth: CGFloat
        let tailHalfWidth: CGFloat

        switch size {
        case .small:
            headLength = min(14.0, length * 0.45)
            headHalfWidth = 6.5
            neckHalfWidth = 2.2
            tailHalfWidth = 0.8
        case .medium:
            headLength = min(20.0, length * 0.45)
            headHalfWidth = 9.5
            neckHalfWidth = 3.5
            tailHalfWidth = 1.2
        case .large:
            headLength = min(28.0, length * 0.45)
            headHalfWidth = 13.5
            neckHalfWidth = 5.2
            tailHalfWidth = 1.8
        }

        let neckX = length - headLength
        let flareBackX = length - headLength * 1.15

        // Define arrow in local coordinates along +X axis from (0,0) to (length,0)
        let localPoints: [NSPoint] = [
            NSPoint(x: 0, y: tailHalfWidth),
            NSPoint(x: neckX, y: neckHalfWidth),
            NSPoint(x: flareBackX, y: headHalfWidth),
            NSPoint(x: length, y: 0),
            NSPoint(x: flareBackX, y: -headHalfWidth),
            NSPoint(x: neckX, y: -neckHalfWidth),
            NSPoint(x: 0, y: -tailHalfWidth)
        ]

        let cosA = cos(angle)
        let sinA = sin(angle)

        let path = NSBezierPath()
        for (i, pt) in localPoints.enumerated() {
            let rx = start.x + pt.x * cosA - pt.y * sinA
            let ry = start.y + pt.x * sinA + pt.y * cosA
            if i == 0 {
                path.move(to: NSPoint(x: rx, y: ry))
            } else {
                path.line(to: NSPoint(x: rx, y: ry))
            }
        }
        path.close()
        return path
    }

    private func createSmoothBrushPath(points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 2 {
            path.line(to: points[1])
            return path
        }
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let mid = NSPoint(x: (prev.x + curr.x) / 2.0, y: (prev.y + curr.y) / 2.0)
            path.curve(to: mid, controlPoint1: prev, controlPoint2: prev)
        }
        if let last = points.last {
            path.line(to: last)
        }
        return path
    }

    private func bezierPathToCGPath(_ bezierPath: NSBezierPath) -> CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<bezierPath.elementCount {
            let type = bezierPath.element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }

    private func drawResizeHandles(for rect: NSRect) {
        for handle in ResizeHandle.allCases {
            let hRect = handle.handleRect(in: rect, size: 8.0)
            let path = NSBezierPath(ovalIn: hRect)
            NSColor.white.setFill()
            path.fill()
            WeChatTheme.green.setStroke()
            path.lineWidth = 1.8
            path.stroke()
        }
    }

    private func drawDimensionsBadge(for rect: NSRect) {
        let w = Int(round(rect.width))
        let h = Int(round(rect.height))
        var text = "\(w) × \(h)"
        if !isSelectionLocked, let hw = hoveredWindow, !hw.ownerName.isEmpty && hw.ownerName != "Screen" {
            text = "\(hw.ownerName)  \(w) × \(h)"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let strSize = (text as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 8.0
        let padY: CGFloat = 4.0
        let badgeW = strSize.width + padX * 2
        let badgeH = strSize.height + padY * 2

        var badgeX = rect.minX
        var badgeY = rect.maxY + 6.0
        if badgeY + badgeH > bounds.maxY - 6.0 {
            badgeY = rect.maxY - badgeH - 6.0
            badgeX = rect.minX + 6.0
        }
        badgeX = max(4.0, min(badgeX, bounds.maxX - badgeW - 4.0))

        let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4.0, yRadius: 4.0)
        NSColor(calibratedWhite: 0.10, alpha: 0.85).setFill()
        badgePath.fill()

        (text as NSString).draw(
            at: NSPoint(x: badgeRect.minX + padX, y: badgeRect.minY + padY),
            withAttributes: attrs
        )
    }

    private func drawMagnifierLoupe(at pt: NSPoint) {
        guard bounds.contains(pt), let cgImg = screenCGImage else { return }

        let loupeW: CGFloat = 132.0
        let loupeH: CGFloat = 156.0
        let previewH: CGFloat = 96.0
        let infoH: CGFloat = loupeH - previewH

        var lx = pt.x + 18.0
        var ly = pt.y - loupeH - 18.0
        if lx + loupeW > bounds.maxX - 10 {
            lx = pt.x - loupeW - 18.0
        }
        if ly < 10 {
            ly = pt.y + 18.0
        }

        let loupeRect = NSRect(x: lx, y: ly, width: loupeW, height: loupeH)
        let previewRect = NSRect(x: lx, y: ly + infoH, width: loupeW, height: previewH)
        let infoRect = NSRect(x: lx, y: ly, width: loupeW, height: infoH)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 8
        shadow.set()

        let outerPath = NSBezierPath(roundedRect: loupeRect, xRadius: 6.0, yRadius: 6.0)
        NSColor(calibratedWhite: 0.12, alpha: 0.95).setFill()
        outerPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Crop around cursor in CGImage pixel coordinates (top-left origin)
        let scaleX = CGFloat(cgImg.width) / bounds.width
        let scaleY = CGFloat(cgImg.height) / bounds.height
        let pixelX = Int(round(pt.x * scaleX))
        let pixelY = Int(round((bounds.height - pt.y) * scaleY))

        let sampleW = 22
        let sampleH = 16
        let cropRect = CGRect(
            x: pixelX - sampleW / 2,
            y: pixelY - sampleH / 2,
            width: sampleW,
            height: sampleH
        )

        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: loupeRect, xRadius: 6.0, yRadius: 6.0)
        clipPath.addClip()

        if let cropped = cgImg.cropping(to: cropRect) {
            NSGraphicsContext.current?.imageInterpolation = .none
            let nsCropped = NSImage(cgImage: cropped, size: previewRect.size)
            nsCropped.draw(in: previewRect)
        }

        // Crosshair inside preview
        WeChatTheme.green.withAlphaComponent(0.85).setStroke()
        let crossPath = NSBezierPath()
        crossPath.lineWidth = 1.2
        crossPath.move(to: NSPoint(x: previewRect.midX, y: previewRect.minY))
        crossPath.line(to: NSPoint(x: previewRect.midX, y: previewRect.maxY))
        crossPath.move(to: NSPoint(x: previewRect.minX, y: previewRect.midY))
        crossPath.line(to: NSPoint(x: previewRect.maxX, y: previewRect.midY))
        crossPath.stroke()

        // Sample center pixel color for HEX display
        let hexString = sampleHexColor(from: cgImg, x: pixelX, y: pixelY)

        // Info text
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1.0)
        ]
        let coordText = "坐标: (\(Int(pt.x)), \(Int(bounds.height - pt.y)))"
        let colorText = "色值: \(hexString)"
        let hintText  = "点击选窗 / 拖拽框选"

        (coordText as NSString).draw(at: NSPoint(x: infoRect.minX + 8, y: infoRect.minY + 38), withAttributes: attrs)
        (colorText as NSString).draw(at: NSPoint(x: infoRect.minX + 8, y: infoRect.minY + 22), withAttributes: attrs)

        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.0),
            .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1.0)
        ]
        (hintText as NSString).draw(at: NSPoint(x: infoRect.minX + 8, y: infoRect.minY + 6), withAttributes: hintAttrs)

        NSGraphicsContext.restoreGraphicsState()

        // Outer border
        let border = NSBezierPath(roundedRect: loupeRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6.0, yRadius: 6.0)
        NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
        border.lineWidth = 1.0
        border.stroke()
    }

    private func sampleHexColor(from cgImage: CGImage, x: Int, y: Int) -> String {
        let clampedX = max(0, min(x, cgImage.width - 1))
        let clampedY = max(0, min(y, cgImage.height - 1))
        guard let onePixel = cgImage.cropping(to: CGRect(x: clampedX, y: clampedY, width: 1, height: 1)) else {
            return "#000000"
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            ctx.draw(onePixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
        }
        return "#000000"
    }

    // MARK: - Toolbar Positioning
    private func updateToolbarPosition() {
        guard isSelectionLocked, selectionRect.width >= 10, selectionRect.height >= 10 else {
            toolbarView.isHidden = true
            return
        }

        toolbarView.isHidden = false
        toolbarView.canUndo = !annotations.isEmpty

        let tbW = WeChatToolbarContainerView.totalWidth
        let tbH = WeChatToolbarContainerView.totalHeight
        let mainH = WeChatToolbarContainerView.mainBarHeight

        // Default: align right edge with selection right edge, place below selection
        var tx = selectionRect.maxX - tbW
        tx = max(8.0, min(tx, bounds.width - tbW - 8.0))

        let spaceBelow = selectionRect.minY
        let spaceAbove = bounds.height - selectionRect.maxY

        var ty: CGFloat
        if spaceBelow >= tbH + 10.0 {
            // Place below selection
            toolbarView.styleBarAbove = false
            ty = selectionRect.minY - tbH - 6.0
        } else if spaceAbove >= tbH + 10.0 {
            // Place above selection
            toolbarView.styleBarAbove = true
            ty = selectionRect.maxY + 6.0
        } else {
            // Selection fills almost the entire height: place inside bottom-right of selection
            toolbarView.styleBarAbove = true
            ty = max(8.0, selectionRect.minY + 8.0)
            tx = max(8.0, min(selectionRect.maxX - tbW - 8.0, bounds.width - tbW - 8.0))
        }

        // Prevent overlap with top-left dimension badge when placed above
        if toolbarView.styleBarAbove && abs(ty - selectionRect.maxY) < mainH {
            ty = selectionRect.maxY + 6.0
        }

        toolbarView.frame = NSRect(x: round(tx), y: round(ty), width: tbW, height: tbH)
        toolbarView.needsDisplay = true
    }

    // MARK: - Mouse Events
    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        mouseLocation = pt

        if !toolbarView.isHidden && toolbarView.frame.contains(pt) {
            NSCursor.arrow.set()
            return
        }

        if !isSelectionLocked {
            // Detect window under cursor
            hoveredWindow = detectedWindows.first(where: { $0.frame.contains(pt) })
            NSCursor.crosshair.set()
            needsDisplay = true
        } else {
            updateCursorForLockedSelection(at: pt)
        }
    }

    private func updateCursorForLockedSelection(at pt: NSPoint) {
        if hitTestResizeHandle(at: pt) != nil {
            NSCursor.crosshair.set()
        } else if selectionRect.contains(pt) {
            if let tool = toolbarView.selectedTool {
                if tool == .text {
                    NSCursor.iBeam.set()
                } else {
                    NSCursor.crosshair.set()
                }
            } else if annotations.isEmpty {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        commitActiveTextFieldIfNeeded()
        if isSelectionLocked && annotations.isEmpty && toolbarView.selectedTool == nil {
            // Right-click resets selection back to window picking mode (just like WeChat)
            isSelectionLocked = false
            selectionRect = .zero
            toolbarView.isHidden = true
            needsDisplay = true
        } else {
            delegate?.canvasDidCancel()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        mouseLocation = pt

        // Commit any open text field first
        if activeTextField != nil {
            commitActiveTextFieldIfNeeded()
            return
        }

        // Double-click inside locked selection finishes & copies to clipboard!
        if event.clickCount == 2 && isSelectionLocked && selectionRect.contains(pt) && toolbarView.selectedTool == nil {
            toolbarDidClickDone()
            return
        }

        if !isSelectionLocked {
            toolbarView.isHidden = true
            dragMode = .creatingSelection(origin: pt)
        } else {
            // Check 8 resize handles first (when no annotations drawn yet or when adjusting)
            if toolbarView.selectedTool == nil, let handle = hitTestResizeHandle(at: pt) {
                toolbarView.isHidden = true
                dragMode = .resizingSelection(handle: handle, initialRect: selectionRect)
                return
            }

            // Inside selection rect
            if selectionRect.contains(pt) {
                if let tool = toolbarView.selectedTool {
                    if tool == .text {
                        beginInlineTextInput(at: pt)
                    } else {
                        dragMode = .drawingAnnotation
                        currentAnnotation = AnnotationItem(
                            tool: tool,
                            color: toolbarView.selectedColor,
                            size: toolbarView.selectedSize,
                            startPoint: pt,
                            endPoint: pt,
                            points: [pt]
                        )
                    }
                } else if annotations.isEmpty {
                    toolbarView.isHidden = true
                    NSCursor.closedHand.set()
                    dragMode = .movingSelection(initialRect: selectionRect, mouseOrigin: pt)
                }
            } else if annotations.isEmpty && toolbarView.selectedTool == nil {
                // Clicking outside when no annotations exist starts a new selection
                isSelectionLocked = false
                toolbarView.isHidden = true
                dragMode = .creatingSelection(origin: pt)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let clampedPt = NSPoint(
            x: max(0, min(pt.x, bounds.width)),
            y: max(0, min(pt.y, bounds.height))
        )
        mouseLocation = clampedPt

        switch dragMode {
        case .none:
            break

        case .creatingSelection(let origin):
            let minX = min(origin.x, clampedPt.x)
            let minY = min(origin.y, clampedPt.y)
            let maxX = max(origin.x, clampedPt.x)
            let maxY = max(origin.y, clampedPt.y)
            selectionRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            needsDisplay = true

        case .movingSelection(let initialRect, let mouseOrigin):
            let dx = clampedPt.x - mouseOrigin.x
            let dy = clampedPt.y - mouseOrigin.y
            var newX = initialRect.origin.x + dx
            var newY = initialRect.origin.y + dy
            newX = max(0, min(newX, bounds.width - initialRect.width))
            newY = max(0, min(newY, bounds.height - initialRect.height))
            selectionRect = NSRect(x: newX, y: newY, width: initialRect.width, height: initialRect.height)
            needsDisplay = true

        case .resizingSelection(let handle, let initialRect):
            selectionRect = resizedRect(from: initialRect, handle: handle, to: clampedPt)
            needsDisplay = true

        case .drawingAnnotation:
            guard var item = currentAnnotation else { break }
            let clippedToSelection = NSPoint(
                x: max(selectionRect.minX, min(clampedPt.x, selectionRect.maxX)),
                y: max(selectionRect.minY, min(clampedPt.y, selectionRect.maxY))
            )
            switch item.tool {
            case .rectangle, .ellipse, .arrow:
                item.endPoint = clippedToSelection
            case .brush, .mosaic:
                item.points.append(clippedToSelection)
            case .text:
                break
            }
            currentAnnotation = item
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        mouseLocation = pt

        switch dragMode {
        case .creatingSelection(let origin):
            let dist = hypot(pt.x - origin.x, pt.y - origin.y)
            if dist < 5.0 {
                // Single click without dragging -> lock the hovered window!
                if let hw = hoveredWindow {
                    selectionRect = hw.frame
                    isSelectionLocked = true
                }
            } else if selectionRect.width >= 10 && selectionRect.height >= 10 {
                isSelectionLocked = true
            }
            dragMode = .none
            updateToolbarPosition()
            needsDisplay = true

        case .movingSelection, .resizingSelection:
            dragMode = .none
            updateToolbarPosition()
            updateCursorForLockedSelection(at: pt)
            needsDisplay = true

        case .drawingAnnotation:
            if let item = currentAnnotation {
                var shouldCommit = false
                switch item.tool {
                case .rectangle, .ellipse:
                    shouldCommit = item.boundingRect.width > 2 || item.boundingRect.height > 2
                case .arrow:
                    shouldCommit = hypot(item.endPoint.x - item.startPoint.x, item.endPoint.y - item.startPoint.y) > 5
                case .brush, .mosaic:
                    shouldCommit = item.points.count >= 2
                case .text:
                    break
                }
                if shouldCommit {
                    annotations.append(item)
                }
            }
            currentAnnotation = nil
            dragMode = .none
            updateToolbarPosition()
            needsDisplay = true

        case .none:
            break
        }
    }

    private func resizedRect(from rect: NSRect, handle: ResizeHandle, to pt: NSPoint) -> NSRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft:
            minX = pt.x; maxY = pt.y
        case .topCenter:
            maxY = pt.y
        case .topRight:
            maxX = pt.x; maxY = pt.y
        case .middleLeft:
            minX = pt.x
        case .middleRight:
            maxX = pt.x
        case .bottomLeft:
            minX = pt.x; minY = pt.y
        case .bottomCenter:
            minY = pt.y
        case .bottomRight:
            maxX = pt.x; minY = pt.y
        }

        let normMinX = min(minX, maxX)
        let normMaxX = max(minX, maxX)
        let normMinY = min(minY, maxY)
        let normMaxY = max(minY, maxY)

        let w = max(12.0, normMaxX - normMinX)
        let h = max(12.0, normMaxY - normMinY)
        return NSRect(x: normMinX, y: normMinY, width: w, height: h)
    }

    // MARK: - Inline Text Tool
    private func beginInlineTextInput(at pt: NSPoint) {
        commitActiveTextFieldIfNeeded()

        let fontSize = toolbarView.selectedSize.fontSize
        let tfHeight = fontSize + 14.0
        let tfWidth = max(140.0, min(320.0, selectionRect.maxX - pt.x - 6.0))
        let tfOriginY = max(selectionRect.minY, pt.y - tfHeight / 2.0)

        activeTextPosition = NSPoint(x: pt.x + 4.0, y: tfOriginY + 4.0)

        let tf = NSTextField(frame: NSRect(x: pt.x, y: tfOriginY, width: tfWidth, height: tfHeight))
        tf.isBordered = false
        tf.drawsBackground = true
        tf.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.25)
        tf.focusRingType = .none
        tf.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        tf.textColor = toolbarView.selectedColor
        tf.placeholderString = "输入文字..."
        tf.wantsLayer = true
        tf.layer?.borderWidth = 1.2
        tf.layer?.borderColor = WeChatTheme.green.cgColor
        tf.layer?.cornerRadius = 4.0
        tf.delegate = self

        addSubview(tf)
        window?.makeFirstResponder(tf)
        activeTextField = tf
    }

    private func commitActiveTextFieldIfNeeded() {
        guard let tf = activeTextField else { return }
        let str = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.isEmpty {
            let item = AnnotationItem(
                tool: .text,
                color: tf.textColor ?? toolbarView.selectedColor,
                size: toolbarView.selectedSize,
                startPoint: activeTextPosition,
                text: str
            )
            annotations.append(item)
            toolbarView.canUndo = true
        }
        tf.removeFromSuperview()
        activeTextField = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) || commandSelector == #selector(cancelOperation(_:)) {
            commitActiveTextFieldIfNeeded()
            return true
        }
        return false
    }

    // MARK: - Keyboard Shortcuts
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            if activeTextField != nil {
                activeTextField?.stringValue = ""
                commitActiveTextFieldIfNeeded()
                return
            }
            delegate?.canvasDidCancel()
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            commitActiveTextFieldIfNeeded()
            if isSelectionLocked {
                toolbarDidClickDone()
            } else if let hw = hoveredWindow {
                selectionRect = hw.frame
                isSelectionLocked = true
                toolbarDidClickDone()
            }
            return
        }

        if event.modifierFlags.contains(.command) {
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if chars == "z" {
                toolbarDidClickUndo()
                return
            } else if chars == "s" && isSelectionLocked {
                toolbarDidClickSave()
                return
            } else if chars == "c" && isSelectionLocked {
                toolbarDidClickDone()
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Final High-DPI Image Rendering
    func renderSelectedImage() -> NSImage? {
        commitActiveTextFieldIfNeeded()
        let rect = activeDisplayRect
        guard rect.width >= 2 && rect.height >= 2 else { return nil }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelW = Int(round(rect.width * scale))
        let pixelH = Int(round(rect.height * scale))

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmapRep.size = rect.size

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high

            // Translate so selectionRect.origin maps to (0, 0)
            let transform = NSAffineTransform()
            transform.translateX(by: -rect.origin.x, yBy: -rect.origin.y)
            transform.concat()

            screenImage.draw(in: bounds)
            drawAllAnnotations(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()

        let finalImage = NSImage(size: rect.size)
        finalImage.addRepresentation(bitmapRep)
        return finalImage
    }

    // MARK: - WeChatToolbarDelegate
    func toolbarDidSelectTool(_ tool: AnnotationTool?) {
        commitActiveTextFieldIfNeeded()
        needsDisplay = true
    }

    func toolbarDidSelectSize(_ size: StrokeSize) {
        if let tf = activeTextField {
            tf.font = NSFont.systemFont(ofSize: size.fontSize, weight: .medium)
        }
        needsDisplay = true
    }

    func toolbarDidSelectColor(_ color: NSColor) {
        if let tf = activeTextField {
            tf.textColor = color
        }
        needsDisplay = true
    }

    func toolbarDidClickUndo() {
        commitActiveTextFieldIfNeeded()
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        toolbarView.canUndo = !annotations.isEmpty
        needsDisplay = true
    }

    func toolbarDidClickOCR() {
        guard let img = renderSelectedImage() else { return }
        delegate?.canvasDidRequestOCR(img)
    }

    func toolbarDidClickPin() {
        guard let img = renderSelectedImage(), let win = window else { return }
        let screenRect = win.convertToScreen(selectionRect)
        delegate?.canvasDidRequestPin(img, selectionRectInScreen: screenRect)
    }

    func toolbarDidClickSave() {
        guard let img = renderSelectedImage() else { return }
        delegate?.canvasDidRequestSave(img)
    }

    func toolbarDidClickCancel() {
        commitActiveTextFieldIfNeeded()
        delegate?.canvasDidCancel()
    }

    func toolbarDidClickDone() {
        guard let img = renderSelectedImage(), let win = window else { return }
        let screenRect = win.convertToScreen(selectionRect)
        delegate?.canvasDidFinishWithImage(img, selectionRectInScreen: screenRect)
    }
}
