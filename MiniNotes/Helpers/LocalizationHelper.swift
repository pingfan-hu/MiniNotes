import Foundation

extension Notification.Name {
    static let miniNotesTogglePin    = Notification.Name("MiniNotesTogglePin")
    static let miniNotesClosePopover = Notification.Name("MiniNotesClosePopover")
    static let miniNotesOpenSettings  = Notification.Name("MiniNotesOpenSettings")
    static let miniNotesLanguageChanged = Notification.Name("MiniNotesLanguageChanged")
}

enum L {
    static var isChinese: Bool {
        let setting = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        switch setting {
        case "chinese": return true
        case "english": return false
        default:        return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    // Toolbar
    static var buttonOpenInObsidian: String { isChinese ? "在Obsidian中打开" : "Open in Obsidian" }
    static var autoSaved: String { isChinese ? "已保存" : "Auto-saved" }
    static var pinTooltipPin: String { isChinese ? "固定窗口" : "Keep window open" }
    static var pinTooltipUnpin: String { isChinese ? "取消固定" : "Auto-hide window" }
    static var exitTooltip: String { isChinese ? "关闭文件" : "Close file" }

    // Landing page
    static func reopenFile(name: String) -> String {
        isChinese ? "重新打开 \(name)" : "Reopen \"\(name)\""
    }

    // Context menu
    static var settings: String        { isChinese ? "设置..." : "Settings..." }
    static var checkForUpdates: String { isChinese ? "检查更新..." : "Check for Updates..." }

    // App settings window
    static var appSettingsTitle:    String { isChinese ? "应用设置" : "App Settings" }
    static var generalTab:          String { isChinese ? "基本设置" : "General" }
    static var aboutTab:            String { isChinese ? "关于" : "About" }
    static var languageLabel:       String { isChinese ? "语言" : "Language" }
    static var launchAtLogin:       String { isChinese ? "开机时自动启动" : "Launch at Login" }
    static var languageSystem:      String { isChinese ? "跟随系统" : "Follow System" }
    static var aboutDescription:    String { isChinese ? "免费且开源的 macOS 菜单栏 Markdown 编辑器。" : "A free and open-source macOS menu bar Markdown editor." }
    static var aboutMadeBy:         String { isChinese ? "由" : "Made by" }
    static var aboutMadeByAfter:    String { isChinese ? "制作。" : "." }
    static var aboutVersion:        String { isChinese ? "版本" : "Version" }

    // File location settings (toolbar sheet)
    static var settingsTitle: String { isChinese ? "文件位置" : "File Location" }
    static var settingsCurrentFile: String { isChinese ? "当前文件" : "Current file" }
    static var settingsOpenExisting: String { isChinese ? "打开已有文件..." : "Open Existing File..." }
    static var settingsCreateNew: String { isChinese ? "新建文件..." : "Create New File..." }
    static var settingsDone: String { isChinese ? "完成" : "Done" }
    static var settingsPanelChooseTitle: String { isChinese ? "选择 Markdown 文件" : "Choose a Markdown file" }
    static var settingsPanelCreateTitle: String { isChinese ? "新建 Markdown 文件" : "Create a new Markdown file" }
}
