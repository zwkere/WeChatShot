import Cocoa

// MARK: - App Settings (SharedPreferences via UserDefaults)
/// 界面设置项统一存放与持久化。Bool 类型默认值即「未设置过」时的行为。
enum AppSettings {
    private static let windowSnappingKey = "WindowSnappingEnabled"

    /// 移动鼠标自动高亮 / 单击选中所在系统窗口（微信式窗口吸附）。
    /// 默认关闭：启动截图后默认为鼠标自由拖拽框选。
    static var windowSnappingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: windowSnappingKey) } // 未设置过 == false
        set { UserDefaults.standard.set(newValue, forKey: windowSnappingKey) }
    }
}
