import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var shotMenuItem: NSMenuItem!
    private var appMenuShotItem: NSMenuItem!
    private var shortcutParentMenuItem: NSMenuItem!
    private var shortcutSubmenuItems: [ShortcutPreset: NSMenuItem] = [:]
    private var pinMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplicationMainMenu()
        setupStatusBarItem()

        HotKeyManager.shared.onTriggerScreenshot = {
            ScreenshotCoordinator.shared.startScreenshot()
        }
        HotKeyManager.shared.onPresetChanged = { [weak self] preset in
            self?.syncShortcutMenuState(with: preset)
            MainWindowController.shared.refreshShortcutSelection()
        }
        HotKeyManager.shared.registerDefaultHotKeys()

        ScreenshotCoordinator.shared.onScreenshotCompleted = { image in
            MainWindowController.shared.updateWithCapturedImage(image)
        }

        PinManager.shared.onPinCountChanged = { [weak self] count in
            MainWindowController.shared.updatePinCount(count)
            self?.pinMenuItem?.title = "关闭全部贴图 (\(count))"
            self?.pinMenuItem?.isEnabled = (count > 0)
        }

        LaunchAtLoginManager.shared.onStateChanged = { [weak self] enabled in
            self?.launchAtLoginMenuItem?.state = enabled ? .on : .off
            MainWindowController.shared.refreshLaunchAtLoginState()
        }

        MainWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindowController.shared.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    private func setupStatusBarItem() {
        let current = HotKeyManager.shared.currentPreset

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let img = NSImage(systemSymbolName: "scissors", accessibilityDescription: "WeChatShot")?.withSymbolConfiguration(config) {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "✂️"
            }
            button.toolTip = "WeChatShot 微信风格截图 (\(current.shortLabel))"
        }

        let menu = NSMenu(title: "WeChatShot")

        shotMenuItem = NSMenuItem(
            title: "开始截图",
            action: #selector(triggerScreenshot),
            keyEquivalent: current.menuKeyEquivalent
        )
        shotMenuItem.keyEquivalentModifierMask = current.menuModifierMask
        shotMenuItem.target = self
        menu.addItem(shotMenuItem)

        let delayItem = NSMenuItem(title: "延时 3 秒截图", action: #selector(triggerDelayedScreenshot), keyEquivalent: "")
        delayItem.target = self
        menu.addItem(delayItem)

        menu.addItem(.separator())

        // Shortcut Presets Submenu
        let shortcutMenu = NSMenu(title: "截图快捷键")
        shortcutSubmenuItems.removeAll()
        for preset in ShortcutPreset.allCases {
            let item = NSMenuItem(title: preset.displayName, action: #selector(handleSelectShortcutFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (preset == current) ? .on : .off
            shortcutMenu.addItem(item)
            shortcutSubmenuItems[preset] = item
        }
        shortcutParentMenuItem = NSMenuItem(title: "快捷键设置 (\(current.shortLabel))", action: nil, keyEquivalent: "")
        shortcutParentMenuItem.submenu = shortcutMenu
        menu.addItem(shortcutParentMenuItem)

        pinMenuItem = NSMenuItem(title: "关闭全部贴图 (0)", action: #selector(closeAllPins), keyEquivalent: "")
        pinMenuItem.target = self
        pinMenuItem.isEnabled = false
        menu.addItem(pinMenuItem)

        launchAtLoginMenuItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        let panelItem = NSMenuItem(title: "打开主控制面板...", action: #selector(openControlPanel), keyEquivalent: "")
        panelItem.target = self
        menu.addItem(panelItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 WeChatShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func syncShortcutMenuState(with preset: ShortcutPreset) {
        statusItem?.button?.toolTip = "WeChatShot 微信风格截图 (\(preset.shortLabel))"
        shotMenuItem?.keyEquivalent = preset.menuKeyEquivalent
        shotMenuItem?.keyEquivalentModifierMask = preset.menuModifierMask
        appMenuShotItem?.keyEquivalent = preset.menuKeyEquivalent
        appMenuShotItem?.keyEquivalentModifierMask = preset.menuModifierMask
        shortcutParentMenuItem?.title = "快捷键设置 (\(preset.shortLabel))"

        for (p, item) in shortcutSubmenuItems {
            item.state = (p == preset) ? .on : .off
        }
    }

    private func setupApplicationMainMenu() {
        let current = HotKeyManager.shared.currentPreset
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 WeChatShot", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenuShotItem = NSMenuItem(
            title: "开始截图",
            action: #selector(triggerScreenshot),
            keyEquivalent: current.menuKeyEquivalent
        )
        appMenuShotItem.keyEquivalentModifierMask = current.menuModifierMask
        appMenuShotItem.target = self
        appMenu.addItem(appMenuShotItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 WeChatShot", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 WeChatShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Edit Menu (enables standard ⌘C / ⌘V / ⌘A / ⌘Z in text fields and OCR view)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func handleSelectShortcutFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = ShortcutPreset(rawValue: raw) else { return }
        HotKeyManager.shared.setPreset(preset)
    }

    @objc private func triggerScreenshot() {
        ScreenshotCoordinator.shared.startScreenshot()
    }

    @objc private func triggerDelayedScreenshot() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            ScreenshotCoordinator.shared.startScreenshot()
        }
    }

    @objc private func closeAllPins() {
        PinManager.shared.closeAll()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginManager.shared.toggle()
    }

    @objc private func openControlPanel() {
        MainWindowController.shared.refreshPermissionStatus()
        MainWindowController.shared.refreshLaunchAtLoginState()
        MainWindowController.shared.refreshShortcutSelection()
        MainWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        MainWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
