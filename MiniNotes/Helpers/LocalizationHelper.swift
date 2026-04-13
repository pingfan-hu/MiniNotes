import Foundation

extension Notification.Name {
    static let miniNotesTogglePin = Notification.Name("MiniNotesTogglePin")
    static let miniNotesClosePopover = Notification.Name("MiniNotesClosePopover")
}

enum L {
    private static var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
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

    // Settings
    static var settingsTitle: String { isChinese ? "文件位置" : "File Location" }
    static var settingsCurrentFile: String { isChinese ? "当前文件" : "Current file" }
    static var settingsOpenExisting: String { isChinese ? "打开已有文件..." : "Open Existing File..." }
    static var settingsCreateNew: String { isChinese ? "新建文件..." : "Create New File..." }
    static var settingsDone: String { isChinese ? "完成" : "Done" }
    static var settingsPanelChooseTitle: String { isChinese ? "选择 Markdown 文件" : "Choose a Markdown file" }
    static var settingsPanelCreateTitle: String { isChinese ? "新建 Markdown 文件" : "Create a new Markdown file" }
}
