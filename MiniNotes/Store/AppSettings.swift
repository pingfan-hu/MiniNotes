import AppKit
import Combine
import Foundation
import ServiceManagement

// MARK: - Enums

enum EditorMode: String {
    case source, edit, view
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese, english
    var id: String { rawValue }

    // Language names are intentionally fixed — they never follow the current UI language.
    var displayName: String {
        switch self {
        case .system:  L.languageSystem   // only this one is localized
        case .chinese: "简中"
        case .english: "English"
        }
    }
}

// MARK: - AppSettings

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
            NotificationCenter.default.post(name: .miniNotesLanguageChanged, object: nil)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin()
        }
    }

    @Published var hotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode")
            HotkeyManager.shared.register(keyCode: hotkeyKeyCode, carbonModifiers: hotkeyCarbonModifiers)
        }
    }

    @Published var hotkeyCarbonModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(hotkeyCarbonModifiers), forKey: "hotkeyCarbonModifiers")
            HotkeyManager.shared.register(keyCode: hotkeyKeyCode, carbonModifiers: hotkeyCarbonModifiers)
        }
    }

    var hotkeyDisplayString: String {
        HotkeyManager.displayString(keyCode: hotkeyKeyCode, carbonModifiers: hotkeyCarbonModifiers)
    }

    func resetHotkey() {
        hotkeyKeyCode = HotkeyManager.defaultKeyCode
        hotkeyCarbonModifiers = HotkeyManager.defaultCarbonModifiers
    }

    private init() {
        let rawLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        self.appLanguage = AppLanguage(rawValue: rawLanguage) ?? .system
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")

        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        self.hotkeyKeyCode = savedKeyCode != 0
            ? UInt32(savedKeyCode)
            : HotkeyManager.defaultKeyCode

        let savedMods = UserDefaults.standard.integer(forKey: "hotkeyCarbonModifiers")
        self.hotkeyCarbonModifiers = savedMods != 0
            ? UInt32(savedMods)
            : HotkeyManager.defaultCarbonModifiers
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[MiniNotes] Launch at login error: \(error)")
        }
    }
}
