import Cocoa

// MARK: - App Settings (SharedPreferences via UserDefaults)
/// 界面设置项统一存放与持久化。Bool 类型默认值即「未设置过」时的行为。
enum AppSettings {
    private static let windowSnappingKey = "WindowSnappingEnabled"
    private static let autoTranslateKey = "EnableAutoTranslate"
    private static let maskAlphaKey = "ScreenshotMaskAlpha"

    /// 移动鼠标自动高亮 / 单击选中所在系统窗口（微信式窗口吸附）。
    /// 默认关闭：启动截图后默认为鼠标自由拖拽框选。
    static var windowSnappingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: windowSnappingKey) } // 未设置过 == false
        set { UserDefaults.standard.set(newValue, forKey: windowSnappingKey) }
    }

    /// 截图翻译模式：开启后每次截图完成（双击 / Enter / 完成按钮）自动弹出翻译窗口。
    /// 默认关闭：截图完成后仅复制到剪贴板（现行为）。
    static var autoTranslateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoTranslateKey) } // 未设置过 == false
        set { UserDefaults.standard.set(newValue, forKey: autoTranslateKey) }
    }

    /// 截图时选区外黑色蒙层的透明度（0.0 = 关闭，默认 0.45 仿微信标准）
    static var maskAlpha: Double {
        get {
            let v = UserDefaults.standard.double(forKey: maskAlphaKey)
            return UserDefaults.standard.object(forKey: maskAlphaKey) == nil ? 0.45 : v
        }
        set {
            UserDefaults.standard.set(newValue, forKey: maskAlphaKey)
        }
    }

    /// 蒙层浓度档位（与主面板下拉选择对应）
    static let maskLevels: [(name: String, alpha: Double)] = [
        ("关闭", 0.0),
        ("轻 (25%)", 0.25),
        ("标准 (45%)", 0.45),
        ("深 (70%)", 0.70)
    ]
}
