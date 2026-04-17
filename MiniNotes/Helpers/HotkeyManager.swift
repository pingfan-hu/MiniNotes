import AppKit
import Carbon

// MARK: - HotkeyManager

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Default: ⌃⌥⌘N
    static let defaultKeyCode: UInt32        = UInt32(kVK_ANSI_N)
    static let defaultCarbonModifiers: UInt32 = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)

    private init() {}

    func register(keyCode: UInt32, carbonModifiers: UInt32) {
        unregister()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = 0x4D6E4E74  // 'MnNt'
        hotKeyID.id = 1

        let status = RegisterEventHotKey(
            keyCode, carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return noErr }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async { mgr.onActivate?() }
                return noErr
            },
            1, &eventSpec, selfPtr, &eventHandlerRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef     { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let h   = eventHandlerRef { RemoveEventHandler(h);    eventHandlerRef = nil }
    }

    // MARK: - Display helpers

    static func displayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.control) { c |= UInt32(controlKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }

    // swiftlint:disable:next large_tuple
    private static let keyNameMap: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Return: "↩", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_F1: "F1", kVK_F2: "F2",  kVK_F3: "F3",  kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6",  kVK_F7: "F7",  kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func keyName(for keyCode: UInt32) -> String {
        keyNameMap[Int(keyCode)] ?? "?"
    }
}
