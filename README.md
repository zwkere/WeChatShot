# WeChatShot ✂️ — macOS 原生仿微信截图工具

![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-brightgreen)
![Arch](https://img.shields.io/badge/arch-Universal%20(Apple%20Silicon%20%26%20Intel)-blue)
![License](https://img.shields.io/badge/license-MIT-green)

**WeChatShot** 是一款使用原生 **Swift + AppKit + ScreenCaptureKit + Vision** 开发的轻量级 macOS 截图软件，深度还原 Mac 版微信截图的交互体验与视觉样式，无需登录微信即可随时使用。

---

## ✨ 功能特性

- **🎯 智能窗口识别与框选**：移动鼠标自动识别并高亮鼠标下的系统窗口（微信绿 `#07C160` 边框 + 窗口尺寸显示），**单击即可选中窗口**，或按住拖拽自由框选，支持 **8 个控制点**微调选区。
- **🔍 像素级放大镜与取色器**：选区及微调边缘时跟随光标显示局部像素放大预览、十字准星、实时坐标 `(X, Y)` 与 `#HEX` 色值。
- **🎨 微信同款深色工具栏与标注**：
  - 支持 **矩形**、**椭圆**、**微信实心渐变箭头**、**画笔涂鸦**、**像素马赛克**、**文字输入** 6 大工具。
  - 二级调色栏支持 **3 档粗细/字号切换** 与 **微信标准 7 色调色盘**（`#FA5151`、`#FFC300`、`#07C160`、`#10AEFF`、`#6467F0`、`#FFFFFF`、`#191919`）。
- **📌 屏幕贴图 (Pin) 悬浮置顶**：一键将截图钉在屏幕最顶层，支持拖拽移动、滚轮无级缩放（`25% ~ 400%`）、透明度调节（`100% / 80% / 50%`）、双击或 `ESC` 关闭。
- **📝 离线 OCR 文字提取**：基于 macOS 原生 `Vision` 引擎离线高精度识别中英文，支持一键复制全文。
- **🚀 开机自启动 & 快捷键切换**：默认全局快捷键 `⌥Z`，支持在主界面或状态栏菜单一键切换常用预设快捷键（`⌥Z`、`⌥A`、`⌃⌘A`、`⇧⌘A`、`⇧⌘X`、`⌥S`）及开启开机自启动。

---

## 📦 下载与安装

### 方式一：直接下载安装包（推荐）

1. 前往 [Releases](../../releases) 页面下载最新版本的 **`WeChatShot-v1.0.0-macOS-universal.dmg`**（或 `.zip`），同时支持 **Apple Silicon (M1/M2/M3/M4)** 与 **Intel** 芯片。
2. 双击打开 `.dmg`，将 **`WeChatShot.app`** 拖入 **`Applications`（应用程序）** 文件夹。
3. **首次打开说明（重要）**：
   由于开源免费分发未经过苹果付费开发者公证（Notarization），首次从浏览器下载打开时若遇到 macOS 提示*“无法验证开发者”*或*“已损坏”*，请在终端执行以下一行命令解除隔离属性即可正常打开：
   ```bash
   xattr -cr /Applications/WeChatShot.app
   ```
4. 首次截图时，请按系统提示在 **「系统设置 -> 隐私与安全性 -> 录屏与系统录音」** 中勾选授权 `WeChatShot`。

### 方式二：从源码一键编译安装

确保已安装 Xcode Command Line Tools（`xcode-select --install`），在终端执行：

```bash
git clone https://github.com/zwkere/WeChatShot.git
cd WeChatShot
./build.sh
open /Applications/WeChatShot.app
```

执行 `./build.sh` 会自动：
1. 生成 `AppIcon.icns` 应用图标
2. 编译 `arm64 + x86_64` 双架构通用二进制（Universal Binary）
3. 在 `dist/` 目录生成 `.dmg` 安装镜像和 `.zip` 发布包
4. 自动安装到 `/Applications/WeChatShot.app`

---

## ⌨️ 快捷键一览

| 快捷键 / 操作 | 功能说明 |
| :--- | :--- |
| **`⌥Z` (`Option + Z`)** | **默认全局触发截图**（支持在设置中切换为 `⌥A`、`⌃⌘A`、`⇧⌘A`、`⇧⌘X`、`⌥S`） |
| **鼠标移动 + 左键单击** | 自动高亮并锁定鼠标指向的系统窗口 |
| **鼠标按住拖拽** | 自定义框选任意区域 |
| **双击选区 / `Enter` 键** | 完成截图并复制到系统剪贴板 |
| **`⌘S` (`Command + S`)** | 保存截图为 PNG 文件 |
| **`⌘Z` (`Command + Z`)** | 撤销上一步标注操作 |
| **右键单击 / `ESC` 键** | 取消当前选区或退出截图模式 |
| **贴图窗口滚轮上下滚动** | 放大 / 缩小悬浮贴图 (`25% ~ 400%`) |
| **贴图窗口双击 / `ESC`** | 关闭当前悬浮贴图 |

---

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 开源。

---

## ☕ 赞赏与支持

如果这款工具对您有所帮助，欢迎扫码赞赏支持作者继续维护更新：

<p align="left">
  <img src="Resources/wechat.jpg" alt="微信赞赏码" width="260" />
</p>

