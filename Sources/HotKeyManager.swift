import Cocoa
import Carbon
import ServiceManagement

// MARK: - Preset Global Shortcuts
enum ShortcutPreset: String, CaseIterable {
    case optionZ      = "opt_z"       // Default: ⌥Z (Option + Z)
    case optionA      = "opt_a"       // WeChat default: ⌥A (Option + A)
    case ctrlCmdA     = "ctrl_cmd_a"  // Classic: ⌃⌘A (Control + Command + A)
    case shiftCmdA    = "shift_cmd_a" // ⇧⌘A (Shift + Command + A)
    case shiftCmdX    = "shift_cmd_x" // ⇧⌘X (Shift + Command + X)
    case optionS      = "opt_s"       // ⌥S (Option + S)

    var shortLabel: String {
        switch self {
        case .optionZ:   return "⌥Z"
        case .optionA:   return "⌥A"
        case .ctrlCmdA:  return "⌃⌘A"
        case .shiftCmdA: return "⇧⌘A"
        case .shiftCmdX: return "⇧⌘X"
        case .optionS:   return "⌥S"
        }
    }

    var displayName: String {
        switch self {
        case .optionZ:   return "⌥Z (Option + Z) — 默认"
        case .optionA:   return "⌥A (Option + A) — 微信经典"
        case .ctrlCmdA:  return "⌃⌘A (Ctrl + Cmd + A)"
        case .shiftCmdA: return "⇧⌘A (Shift + Cmd + A)"
        case .shiftCmdX: return "⇧⌘X (Shift + Cmd + X)"
        case .optionS:   return "⌥S (Option + S)"
        }
    }

    var carbonKeyCode: UInt32 {
        switch self {
        case .optionZ:                     return UInt32(kVK_ANSI_Z)
        case .optionA, .ctrlCmdA, .shiftCmdA: return UInt32(kVK_ANSI_A)
        case .shiftCmdX:                   return UInt32(kVK_ANSI_X)
        case .optionS:                     return UInt32(kVK_ANSI_S)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionZ, .optionA, .optionS:
            return UInt32(optionKey)
        case .ctrlCmdA:
            return UInt32(controlKey | cmdKey)
        case .shiftCmdA, .shiftCmdX:
            return UInt32(shiftKey | cmdKey)
        }
    }

    var menuKeyEquivalent: String {
        switch self {
        case .optionZ:                     return "z"
        case .optionA, .ctrlCmdA, .shiftCmdA: return "a"
        case .shiftCmdX:                   return "x"
        case .optionS:                     return "s"
        }
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        switch self {
        case .optionZ, .optionA, .optionS:
            return [.option]
        case .ctrlCmdA:
            return [.control, .command]
        case .shiftCmdA, .shiftCmdX:
            return [.shift, .command]
        }
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    private let userDefaultsKey = "WeChatShot.ShortcutPreset"

    var onTriggerScreenshot: (() -> Void)?
    var onPresetChanged: ((ShortcutPreset) -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private(set) var currentPreset: ShortcutPreset

    private init() {
        if let savedRaw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let preset = ShortcutPreset(rawValue: savedRaw) {
            self.currentPreset = preset
        } else {
            self.currentPreset = .optionZ // Default remains Option + Z
        }
    }

    func setPreset(_ preset: ShortcutPreset) {
        currentPreset = preset
        UserDefaults.standard.set(preset.rawValue, forKey: userDefaultsKey)
        registerCurrentHotKey()
        onPresetChanged?(preset)
    }

    func registerDefaultHotKeys() {
        registerCurrentHotKey()
    }

    func registerCurrentHotKey() {
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

        let hotKeyID = EventHotKeyID(signature: OSType(0x57435354), id: 1)
        RegisterEventHotKey(
            currentPreset.carbonKeyCode,
            currentPreset.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregisterAll() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
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
