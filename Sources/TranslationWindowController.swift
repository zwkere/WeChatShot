import Cocoa

// MARK: - Screenshot Translation Result Window (只显示译文)
/// 截图翻译流程：图片 → Vision OCR → （离线/在线）翻译 → 仅展示简体中文译文。
final class TranslationWindowController: NSWindowController {
    static let shared = TranslationWindowController()

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
        window.title = "WeChatShot - 截图翻译（译为简体中文）"
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

        // Middle: translated text (简体中文，只读可复制)
        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 56, width: 528, height: 192))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autoresizingMask = [.width, .height]

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 510, height: 192))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 14.0)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        // Bottom bar: status label + copy button
        statusLabel = NSTextField(labelWithString: "正在识别图中文字...")
        statusLabel.font = NSFont.systemFont(ofSize: 12.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 18, y: 18, width: 360, height: 22)
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        contentView.addSubview(statusLabel)

        copyButton = NSButton(title: "复制译文", target: self, action: #selector(copyTranslation))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.frame = NSRect(x: 444, y: 14, width: 100, height: 30)
        copyButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(copyButton)
    }

    /// 统一入口：任意外部图片（截图 / 贴图 / 主面板最近截图）
    func translate(image: NSImage) {
        imageView.image = image
        textView.string = ""
        statusLabel.stringValue = "正在识别图中文字..."
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        guard let cgImage = OCREngine.cgImage(from: image) else {
            statusLabel.stringValue = "无法读取图像数据"
            return
        }

        OCREngine.recognizeText(in: cgImage) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let ocrText):
                    self?.translate(text: ocrText)
                case .failure(let error):
                    self?.statusLabel.stringValue = "OCR 识别失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func translate(text rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            textView.string = ""
            copyButton.isEnabled = false
            statusLabel.stringValue = "未在所选区域内检测到可翻译的文字"
            return
        }

        statusLabel.stringValue = "正在翻译为简体中文..."
        TranslationService.shared.translate(trimmed) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let translated):
                self.textView.string = translated
                self.copyButton.isEnabled = true
                let engine = TranslationService.shared.lastEngineName
                self.statusLabel.stringValue = "翻译完成（\(engine)引擎）：共 \(translated.count) 字"
            case .failure(let error):
                self.textView.string = ""
                self.copyButton.isEnabled = false
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.statusLabel.stringValue = message
            }
        }
    }

    @objc private func copyTranslation() {
        let text = textView.string
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        statusLabel.stringValue = "✅ 译文已复制到系统剪贴板！（共 \(text.count) 字）"
    }
}
