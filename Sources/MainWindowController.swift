import Cocoa

final class MainWindowController: NSWindowController {
    static let shared = MainWindowController()

    private var permissionBadgeLabel: NSTextField!
    private var permissionActionBtn: NSButton!
    private var previewImageView: NSImageView!
    private var previewPlaceholderLabel: NSTextField!
    private var previewActionsStack: NSStackView!
    private var pinCountLabel: NSTextField!
    private var launchAtLoginCheckbox: NSButton!

    private var lastCapturedImage: NSImage? = nil

    private init() {
        let rect = NSRect(x: 0, y: 0, width: 520, height: 480)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WeChatShot - 仿微信截图工具"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI(in: window)
        refreshPermissionStatus()
        refreshLaunchAtLoginState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(in window: NSWindow) {
        guard let contentView = window.contentView else { return }

        // 1. Header Card
        let headerBox = NSView(frame: NSRect(x: 20, y: 392, width: 480, height: 68))
        headerBox.wantsLayer = true
        headerBox.layer?.backgroundColor = WeChatTheme.green.withAlphaComponent(0.10).cgColor
        headerBox.layer?.cornerRadius = 10
        headerBox.layer?.borderWidth = 1
        headerBox.layer?.borderColor = WeChatTheme.green.withAlphaComponent(0.30).cgColor
        contentView.addSubview(headerBox)

        let iconView = NSImageView(frame: NSRect(x: 16, y: 14, width: 40, height: 40))
        let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        iconView.contentTintColor = WeChatTheme.green
        headerBox.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "WeChatShot 微信风格截图")
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        titleLabel.frame = NSRect(x: 68, y: 34, width: 240, height: 24)
        headerBox.addSubview(titleLabel)

        let subLabel = NSTextField(labelWithString: "全局快捷键：⌥Z (Option + Z)  |  智能窗口吸附 · 标注 · 马赛克 · 贴图 · OCR")
        subLabel.font = NSFont.systemFont(ofSize: 11.5)
        subLabel.textColor = .secondaryLabelColor
        subLabel.frame = NSRect(x: 68, y: 12, width: 400, height: 18)
        headerBox.addSubview(subLabel)

        // 2. Action Buttons Row
        let captureBtn = NSButton(title: "  立即开始截图 (⌥Z)", target: self, action: #selector(handleStartCapture))
        captureBtn.bezelStyle = .regularSquare
        captureBtn.wantsLayer = true
        captureBtn.isBordered = false
        captureBtn.layer?.backgroundColor = WeChatTheme.green.cgColor
        captureBtn.layer?.cornerRadius = 8
        captureBtn.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        captureBtn.contentTintColor = .white
        let attrTitle = NSMutableAttributedString(string: "✂️ 立即开始截图 (Option + Z)", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        captureBtn.attributedTitle = attrTitle
        captureBtn.frame = NSRect(x: 20, y: 334, width: 320, height: 42)
        contentView.addSubview(captureBtn)

        let delayBtn = NSButton(title: "⏱ 延时 3 秒截图", target: self, action: #selector(handleDelayedCapture))
        delayBtn.bezelStyle = .rounded
        delayBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        delayBtn.frame = NSRect(x: 352, y: 335, width: 148, height: 40)
        contentView.addSubview(delayBtn)

        // 3. Permission & Status Row
        let statusBox = NSView(frame: NSRect(x: 20, y: 288, width: 480, height: 34))
        statusBox.wantsLayer = true
        statusBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.5, alpha: 0.08).cgColor
        statusBox.layer?.cornerRadius = 6
        contentView.addSubview(statusBox)

        permissionBadgeLabel = NSTextField(labelWithString: "正在检查录屏权限...")
        permissionBadgeLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        permissionBadgeLabel.frame = NSRect(x: 12, y: 7, width: 330, height: 20)
        statusBox.addSubview(permissionBadgeLabel)

        permissionActionBtn = NSButton(title: "授权录屏权限", target: self, action: #selector(handleRequestPermission))
        permissionActionBtn.bezelStyle = .inline
        permissionActionBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        permissionActionBtn.frame = NSRect(x: 356, y: 6, width: 114, height: 22)
        statusBox.addSubview(permissionActionBtn)

        // 4. Recent Screenshot Preview Area
        let previewContainer = NSView(frame: NSRect(x: 20, y: 92, width: 480, height: 184))
        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.05).cgColor
        previewContainer.layer?.cornerRadius = 8
        previewContainer.layer?.borderWidth = 1
        previewContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        contentView.addSubview(previewContainer)

        previewImageView = NSImageView(frame: NSRect(x: 10, y: 42, width: 460, height: 132))
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewContainer.addSubview(previewImageView)

        previewPlaceholderLabel = NSTextField(labelWithString: "暂无最近截图\n点击上方「立即开始截图」或按 ⌥Z (Option + Z) 即可体验微信同款截图")
        previewPlaceholderLabel.alignment = .center
        previewPlaceholderLabel.font = NSFont.systemFont(ofSize: 12.5)
        previewPlaceholderLabel.textColor = .tertiaryLabelColor
        previewPlaceholderLabel.frame = NSRect(x: 20, y: 72, width: 440, height: 42)
        previewContainer.addSubview(previewPlaceholderLabel)

        let btnCopy = NSButton(title: "复制图片", target: self, action: #selector(copyLastImage))
        let btnSave = NSButton(title: "保存图片", target: self, action: #selector(saveLastImage))
        let btnPin  = NSButton(title: "贴在屏幕 (Pin)", target: self, action: #selector(pinLastImage))
        let btnOCR  = NSButton(title: "提取文字 (OCR)", target: self, action: #selector(ocrLastImage))

        for b in [btnCopy, btnSave, btnPin, btnOCR] {
            b.bezelStyle = .rounded
            b.font = NSFont.systemFont(ofSize: 12)
        }

        previewActionsStack = NSStackView(views: [btnCopy, btnSave, btnPin, btnOCR])
        previewActionsStack.orientation = .horizontal
        previewActionsStack.distribution = .fillEqually
        previewActionsStack.spacing = 10
        previewActionsStack.frame = NSRect(x: 12, y: 8, width: 456, height: 28)
        previewActionsStack.isHidden = true
        previewContainer.addSubview(previewActionsStack)

        // 5. Footer Guide & Settings Row (Launch at Login + Active Pin Count)
        let guideLabel = NSTextField(
            labelWithString: "💡 操作提示：移动鼠标自动高亮窗口（单击即选） • 拖拽框选任意区域 • 双击或按 Enter 完成复制 • 右键或 ESC 取消"
        )
        guideLabel.font = NSFont.systemFont(ofSize: 11)
        guideLabel.textColor = .secondaryLabelColor
        guideLabel.frame = NSRect(x: 20, y: 54, width: 480, height: 28)
        contentView.addSubview(guideLabel)

        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "开机自动启动 WeChatShot",
            target: self,
            action: #selector(handleToggleLaunchAtLogin(_:))
        )
        launchAtLoginCheckbox.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        launchAtLoginCheckbox.frame = NSRect(x: 20, y: 17, width: 190, height: 22)
        contentView.addSubview(launchAtLoginCheckbox)

        pinCountLabel = NSTextField(labelWithString: "当前屏幕贴图：0")
        pinCountLabel.font = NSFont.systemFont(ofSize: 12)
        pinCountLabel.textColor = .secondaryLabelColor
        pinCountLabel.frame = NSRect(x: 240, y: 18, width: 140, height: 20)
        contentView.addSubview(pinCountLabel)

        let closePinsBtn = NSButton(title: "关闭全部贴图", target: self, action: #selector(handleCloseAllPins))
        closePinsBtn.bezelStyle = .rounded
        closePinsBtn.font = NSFont.systemFont(ofSize: 12)
        closePinsBtn.frame = NSRect(x: 390, y: 14, width: 110, height: 28)
        contentView.addSubview(closePinsBtn)
    }

    func refreshPermissionStatus() {
        let granted = ScreenCaptureManager.shared.hasScreenRecordingPermission
        if granted {
            permissionBadgeLabel.stringValue = "✅ 屏幕录制权限已就绪（支持窗口高亮吸附与 Retina 高清截图）"
            permissionBadgeLabel.textColor = WeChatTheme.green
            permissionActionBtn.title = "刷新状态"
        } else {
            permissionBadgeLabel.stringValue = "⚠️ 尚未开启屏幕录制权限（开启后可截取桌面真实窗口内容）"
            permissionBadgeLabel.textColor = .systemOrange
            permissionActionBtn.title = "点击授权权限"
        }
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginCheckbox?.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
    }

    func updateWithCapturedImage(_ image: NSImage) {
        lastCapturedImage = image
        previewImageView.image = image
        previewPlaceholderLabel.isHidden = true
        previewActionsStack.isHidden = false
        refreshPermissionStatus()
    }

    func updatePinCount(_ count: Int) {
        pinCountLabel?.stringValue = "当前屏幕贴图：\(count)"
    }

    // MARK: - Actions
    @objc private func handleToggleLaunchAtLogin(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        LaunchAtLoginManager.shared.setEnabled(enabled)
    }

    @objc private func handleStartCapture() {
        window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            ScreenshotCoordinator.shared.startScreenshot()
        }
    }

    @objc private func handleDelayedCapture() {
        window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            ScreenshotCoordinator.shared.startScreenshot()
        }
    }

    @objc private func handleRequestPermission() {
        if !ScreenCaptureManager.shared.hasScreenRecordingPermission {
            let ok = ScreenCaptureManager.shared.requestPermission()
            if !ok {
                ScreenCaptureManager.shared.openScreenRecordingSettings()
            }
        }
        refreshPermissionStatus()
    }

    @objc private func copyLastImage() {
        guard let img = lastCapturedImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }

    @objc private func saveLastImage() {
        guard let img = lastCapturedImage else { return }
        ScreenshotCoordinator.shared.canvasDidRequestSave(img)
    }

    @objc private func pinLastImage() {
        guard let img = lastCapturedImage else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 200, y: 200, width: 600, height: 400)
        let w = min(img.size.width, screenFrame.width * 0.7)
        let h = min(img.size.height, screenFrame.height * 0.7)
        let rect = NSRect(
            x: screenFrame.midX - w / 2.0,
            y: screenFrame.midY - h / 2.0,
            width: w,
            height: h
        )
        PinManager.shared.pin(image: img, screenRect: rect)
    }

    @objc private func ocrLastImage() {
        guard let img = lastCapturedImage else { return }
        OCRWindowController.shared.recognizeAndShow(image: img)
    }

    @objc private func handleCloseAllPins() {
        PinManager.shared.closeAll()
    }
}
