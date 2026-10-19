import Cocoa

// MARK: - WeChat Theme Constants
enum WeChatTheme {
    /// WeChat signature green (#07C160)
    static let green = NSColor(srgbRed: 0x07/255.0, green: 0xC1/255.0, blue: 0x60/255.0, alpha: 1.0)
    /// Toolbar dark background (#262626)
    static let toolbarBg = NSColor(srgbRed: 0x26/255.0, green: 0x26/255.0, blue: 0x26/255.0, alpha: 0.94)
    /// Mask overlay outside selection
    static let maskColor = NSColor(calibratedWhite: 0.0, alpha: 0.45)

    /// Standard WeChat 7 annotation colors
    static let palette: [(name: String, color: NSColor)] = [
        ("红色", NSColor(srgbRed: 0xFA/255.0, green: 0x51/255.0, blue: 0x51/255.0, alpha: 1.0)), // #FA5151
        ("黄色", NSColor(srgbRed: 0xFF/255.0, green: 0xC3/255.0, blue: 0x00/255.0, alpha: 1.0)), // #FFC300
        ("绿色", NSColor(srgbRed: 0x07/255.0, green: 0xC1/255.0, blue: 0x60/255.0, alpha: 1.0)), // #07C160
        ("蓝色", NSColor(srgbRed: 0x10/255.0, green: 0xAE/255.0, blue: 0xFF/255.0, alpha: 1.0)), // #10AEFF
        ("紫色", NSColor(srgbRed: 0x64/255.0, green: 0x67/255.0, blue: 0xF0/255.0, alpha: 1.0)), // #6467F0
        ("白色", NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)),                       // #FFFFFF
        ("黑色", NSColor(srgbRed: 0x19/255.0, green: 0x19/255.0, blue: 0x19/255.0, alpha: 1.0))  // #191919
    ]
}

// MARK: - Annotation Tool Types
enum AnnotationTool: Int, CaseIterable {
    case rectangle = 0
    case ellipse
    case arrow
    case brush
    case mosaic
    case text

    var title: String {
        switch self {
        case .rectangle: return "矩形"
        case .ellipse:   return "椭圆"
        case .arrow:     return "箭头"
        case .brush:     return "画笔"
        case .mosaic:    return "马赛克"
        case .text:      return "文字"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .arrow:     return "arrow.up.right"
        case .brush:     return "scribble"
        case .mosaic:    return "checkerboard.rectangle"
        case .text:      return "textformat"
        }
    }

    var supportsColorSelection: Bool {
        return self != .mosaic
    }
}

// MARK: - Stroke / Font Size Level
enum StrokeSize: Int, CaseIterable {
    case small = 0
    case medium = 1
    case large = 2

    var lineWidth: CGFloat {
        switch self {
        case .small:  return 2.0
        case .medium: return 4.0
        case .large:  return 8.0
        }
    }

    var mosaicBrushWidth: CGFloat {
        switch self {
        case .small:  return 12.0
        case .medium: return 22.0
        case .large:  return 36.0
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small:  return 14.0
        case .medium: return 20.0
        case .large:  return 28.0
        }
    }

    var dotDiameter: CGFloat {
        switch self {
        case .small:  return 6.0
        case .medium: return 10.0
        case .large:  return 14.0
        }
    }
}

// MARK: - Annotation Item Model
struct AnnotationItem {
    let id = UUID()
    var tool: AnnotationTool
    var color: NSColor
    var size: StrokeSize
    /// Start & end points (in view coordinates) for rectangle, ellipse, arrow
    var startPoint: NSPoint
    var endPoint: NSPoint
    /// Points array for freehand brush & mosaic strokes
    var points: [NSPoint]
    /// Text string for text annotations
    var text: String

    init(
        tool: AnnotationTool,
        color: NSColor,
        size: StrokeSize,
        startPoint: NSPoint = .zero,
        endPoint: NSPoint = .zero,
        points: [NSPoint] = [],
        text: String = ""
    ) {
        self.tool = tool
        self.color = color
        self.size = size
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.points = points
        self.text = text
    }

    var boundingRect: NSRect {
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxX = max(startPoint.x, endPoint.x)
        let maxY = max(startPoint.y, endPoint.y)
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - 8 Resize Handles
enum ResizeHandle: CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight

    func point(in rect: NSRect) -> NSPoint {
        switch self {
        case .topLeft:      return NSPoint(x: rect.minX, y: rect.maxY)
        case .topCenter:    return NSPoint(x: rect.midX, y: rect.maxY)
        case .topRight:     return NSPoint(x: rect.maxX, y: rect.maxY)
        case .middleLeft:   return NSPoint(x: rect.minX, y: rect.midY)
        case .middleRight:  return NSPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:   return NSPoint(x: rect.minX, y: rect.minY)
        case .bottomCenter: return NSPoint(x: rect.midX, y: rect.minY)
        case .bottomRight:  return NSPoint(x: rect.maxX, y: rect.minY)
        }
    }

    func handleRect(in rect: NSRect, size: CGFloat = 8.0) -> NSRect {
        let pt = point(in: rect)
        return NSRect(x: pt.x - size / 2.0, y: pt.y - size / 2.0, width: size, height: size)
    }
}

// MARK: - Detected System Window Info
struct DetectedWindow {
    let windowID: CGWindowID
    let ownerName: String
    let title: String
    /// Frame in AppKit screen coordinates (bottom-left origin)
    let frame: NSRect
}
