import Cocoa
import Vision

final class OCRWindowController: NSWindowController {
    static let shared = OCRWindowController()

    private var imageView: NSImageView!
    private var textView: NSTextView!
    private var statusLabel: NSTextField!
    private var copyButton: NSButton!

    private init() {
        let winRect = NSRect(x: 0, y: 0, width: 560, height: 420)
        let window = NSWindow(
            contentRect: winRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WeChatShot - 提取图中文字 (OCR)"
        window.level = .floating
        window.minSize = NSSize(width: 440, height: 320)
        window.center()

        super.init(window: window)
        setupUI(in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(in window: NSWindow) {
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        // Top image preview container
        imageView = NSImageView(frame: NSRect(x: 16, y: 260, width: 528, height: 140))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.06).cgColor
        imageView.layer?.cornerRadius = 8
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(imageView)

        // Scrollable text view for OCR output
        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 56, width: 528, height: 192))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autoresizingMask = [.width, .height]

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 510, height: 192))
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 14.0)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        // Bottom bar: status label + copy button
        statusLabel = NSTextField(labelWithString: "正在识别文字...")
        statusLabel.font = NSFont.systemFont(ofSize: 12.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 18, y: 18, width: 360, height: 22)
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        contentView.addSubview(statusLabel)

        copyButton = NSButton(title: "复制全文", target: self, action: #selector(copyAllText))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.frame = NSRect(x: 444, y: 14, width: 100, height: 30)
        copyButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(copyButton)
    }

    func recognizeAndShow(image: NSImage) {
        imageView.image = image
        textView.string = ""
        statusLabel.stringValue = "正在使用 macOS Vision 引擎识别中英文..."
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            statusLabel.stringValue = "无法读取图像数据"
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let request = VNRecognizeTextRequest { [weak self] req, err in
                guard let self = self else { return }
                if let err = err {
                    DispatchQueue.main.async {
                        self.statusLabel.stringValue = "识别出错：\(err.localizedDescription)"
                    }
                    return
                }

                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let lines: [String] = observations.compactMap { $0.topCandidates(1).first?.string }
                let fullText = lines.joined(separator: "\n")

                DispatchQueue.main.async {
                    if fullText.isEmpty {
                        self.textView.string = "（未在所选区域内检测到可识别的文字）"
                        self.statusLabel.stringValue = "识别完成：未检测到文字"
                    } else {
                        self.textView.string = fullText
                        self.statusLabel.stringValue = "识别完成：共 \(lines.count) 行，\(fullText.count) 个字符"
                    }
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = "OCR 执行失败：\(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func copyAllText() {
        let text = textView.string
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        statusLabel.stringValue = "✅ 已复制到系统剪贴板！（共 \(text.count) 个字符）"
    }
}
