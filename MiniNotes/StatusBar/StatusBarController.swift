import AppKit
import SwiftUI

class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let notesStore = NotesStore()
    private var eventMonitor: EventMonitor?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "MiniNotes")
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        let contentView = ContentView().environmentObject(notesStore)
        popover.contentSize = NSSize(width: 620, height: 500)
        popover.contentViewController = NSHostingController(rootView: contentView)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self, self.popover.isShown {
                self.closePopover()
            }
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            if popover.isShown { closePopover() } else { openPopover() }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit MiniNotes",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.image = NSImage(systemSymbolName: "xmark.square", accessibilityDescription: nil)
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // NSPopover sits at .popUpMenu (101). On recent macOS the system IME candidate
        // window is at the same or lower level, so it renders behind the popover.
        // Dropping to .floating (3) lets the IME appear above us while still keeping
        // us above normal app windows (level 0).
        popover.contentViewController?.view.window?.level = .floating
        eventMonitor?.start()
    }

    private func closePopover() {
        popover.performClose(nil)
        eventMonitor?.stop()
    }
}

class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
