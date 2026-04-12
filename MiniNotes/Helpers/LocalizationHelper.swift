import Foundation

enum L {
    private static var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }

    // Toolbar
    static var buttonObsidian: String { "Obsidian" }
    static var buttonChoose: String { isChinese ? "选择" : "Choose" }
    static var autoSaved: String { isChinese ? "已保存" : "Auto-saved" }

    // Settings
    static var settingsTitle: String { isChinese ? "文件位置" : "File Location" }
    static var settingsCurrentFile: String { isChinese ? "当前文件" : "Current file" }
    static var settingsOpenExisting: String { isChinese ? "打开已有文件..." : "Open Existing File..." }
    static var settingsCreateNew: String { isChinese ? "新建文件..." : "Create New File..." }
    static var settingsDone: String { isChinese ? "完成" : "Done" }
    static var settingsPanelChooseTitle: String { isChinese ? "选择 Markdown 文件" : "Choose a Markdown file" }
    static var settingsPanelCreateTitle: String { isChinese ? "新建 Markdown 文件" : "Create a new Markdown file" }
}
