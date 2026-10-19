import Cocoa
import Carbon
import ServiceManagement

final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTriggerScreenshot: (() -> Void)?

    private var hotKeyRefOptZ: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func registerDefaultHotKeys() {
        unregisterAll()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
            guard let eventRef = eventRef else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr && hotKeyID.signature == OSType(0x57435354) { // 'WCST'
                DispatchQueue.main.async {
                    HotKeyManager.shared.onTriggerScreenshot?()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        // Option + Z (kVK_ANSI_Z = 0x06)
        let id1 = EventHotKeyID(signature: OSType(0x57435354), id: 1)
        let mods1 = UInt32(optionKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_Z), mods1, id1, GetApplicationEventTarget(), 0, &hotKeyRefOptZ)
    }

    func unregisterAll() {
        if let ref = hotKeyRefOptZ {
            UnregisterEventHotKey(ref)
            hotKeyRefOptZ = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}

// MARK: - Launch At Login Manager (开机自启动管理)
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let label = "com.wechatshot.macos"
    var onStateChanged: ((Bool) -> Void)?

    private var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    var isEnabled: Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) {
        let fm = FileManager.default
        let agentsDir = launchAgentURL.deletingLastPathComponent()
        try? fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        if enabled {
            // Prefer /Applications/WeChatShot.app if installed there, otherwise current bundle executable
            let appExecPath: String
            let appsPath = "/Applications/WeChatShot.app/Contents/MacOS/WeChatShot"
            if fm.fileExists(atPath: appsPath) {
                appExecPath = appsPath
            } else {
                appExecPath = Bundle.main.executablePath ?? appsPath
            }

            let plistDict: [String: Any] = [
                "Label": label,
                "ProgramArguments": [appExecPath],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]

            if let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0) {
                try? data.write(to: launchAgentURL, options: .atomic)
            }
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.register()
            }
        } else {
            try? fm.removeItem(at: launchAgentURL)
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.unregister()
            }
        }
        onStateChanged?(isEnabled)
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}
