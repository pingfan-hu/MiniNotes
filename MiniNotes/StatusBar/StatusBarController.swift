import AppKit
import Sparkle
import SwiftUI

class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let notesStore = NotesStore()
    private var eventMonitor: EventMonitor?
    private var isPinned = false
    private weak var updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController?) {
        self.updaterController = updaterController
        statusItem = Self.createStatusItem()
        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true

        configureStatusButton()

        // Menu bar managers (Ice, Hidden Bar, ...) hide items by pushing them
        // off-screen, and macOS persists that position in our own defaults, so
        // the icon can stay invisible across relaunches. Check once the menu
        // bar has settled and rescue the icon if that happened.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.healStatusItemIfNeeded()
        }

        let contentView = ContentView().environmentObject(notesStore)
        popover.contentSize = NSSize(width: 620, height: 500)
        popover.contentViewController = NSHostingController(rootView: contentView)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self, self.popover.isShown, NSApp.modalWindow == nil {
                self.closePopover()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePinToggle(_:)),
            name: .miniNotesTogglePin,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForceClose),
            name: .miniNotesClosePopover,
            object: nil
        )

        let settings = AppSettings.shared
        HotkeyManager.shared.onActivate = { [weak self] in
            guard let self else { return }
            if self.popover.isShown { self.closePopover() } else { self.openPopover() }
        }
        HotkeyManager.shared.register(
            keyCode: settings.hotkeyKeyCode,
            carbonModifiers: settings.hotkeyCarbonModifiers
        )
    }

    // ─── Status item creation & self-healing ─────────────────────────────────

    private static let autosaveName = "MiniNotes"
    private static let preferredPositionKey = "NSStatusItem Preferred Position \(autosaveName)"
    /// Distance from the right edge of the menu bar. Small value = rightmost
    /// third-party slot, i.e. guaranteed visible territory.
    private static let healedPreferredPosition: Double = 50

    private static func createStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        return item
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.makeStatusIcon()
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    /// Outlined rounded-rect badge with a solid pen inside, drawn as a
    /// template image — the same construction as the system text-input-menu
    /// badge (the "A" icon), and the same 22x16 frame, so MiniNotes matches
    /// its menu bar neighbors exactly. Vector paths are rendered per backing
    /// scale, so the glyph stays crisp (and in one piece) at every scaled
    /// resolution — unlike the multi-part `square.and.pencil` SF Symbol it
    /// replaces.
    private static func makeStatusIcon() -> NSImage {
        let canvas = NSSize(width: 22, height: 16)
        let image = NSImage(size: canvas, flipped: false) { _ in
            // Border ring, stroked centered on an inset frame. Thickness and
            // outer corner radius measured from the system input-menu badge
            // (2 px border, 11 px radius at 2x).
            let border: CGFloat = 1.0
            let outerRadius: CGFloat = 5.5
            let inset = border / 2
            let frame = NSRect(x: inset, y: inset, width: 22 - border, height: 16 - border)
            let ring = NSBezierPath(roundedRect: frame, xRadius: outerRadius - inset, yRadius: outerRadius - inset)
            ring.lineWidth = border
            ring.stroke()

            // solid pen at 45°, tip pointing bottom-left
            let ux: CGFloat = 0.7071, uy: CGFloat = 0.7071   // along the axis
            let vx: CGFloat = -0.7071, vy: CGFloat = 0.7071  // perpendicular
            let tipX: CGFloat = 6.4, tipY: CGFloat = 3.4
            let tipLen: CGFloat = 3.0, gap: CGFloat = 0.8, totalLen: CGFloat = 10.8
            let halfWidth: CGFloat = 1.35
            func point(_ d: CGFloat, _ side: CGFloat) -> NSPoint {
                NSPoint(x: tipX + d * ux + side * halfWidth * vx,
                        y: tipY + d * uy + side * halfWidth * vy)
            }
            func fill(_ points: [NSPoint]) {
                let path = NSBezierPath()
                path.move(to: points[0])
                for p in points.dropFirst() { path.line(to: p) }
                path.close()
                path.fill()
            }
            // tip triangle, then the shaft separated by a small gap
            fill([NSPoint(x: tipX, y: tipY), point(tipLen, 1), point(tipLen, -1)])
            fill([point(tipLen + gap, 1), point(totalLen, 1),
                  point(totalLen, -1), point(tipLen + gap, -1)])
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MiniNotes"
        return image
    }

    private func statusItemIsOffscreen() -> Bool {
        guard let window = statusItem.button?.window else { return true }
        return !NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    /// Recreates the status item at a known-visible position when it has been
    /// pushed off-screen (menu bar manager hidden section, stale persisted
    /// position). Writing the preferred-position default before recreating is
    /// what forces macOS to place the new item in visible territory.
    func healStatusItemIfNeeded() {
        guard statusItemIsOffscreen() else { return }
        if popover.isShown { popover.performClose(nil) }
        NSStatusBar.system.removeStatusItem(statusItem)
        UserDefaults.standard.set(Self.healedPreferredPosition, forKey: Self.preferredPositionKey)
        statusItem = Self.createStatusItem()
        configureStatusButton()
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .miniNotesOpenSettings, object: nil)
    }

    @objc private func handleForceClose() {
        closePopover()
    }

    @objc private func handlePinToggle(_ notification: Notification) {
        isPinned = notification.object as? Bool ?? false
        if isPinned {
            eventMonitor?.stop()
        } else if popover.isShown {
            eventMonitor?.start()
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            if popover.isShown { closePopover() }
            showContextMenu()
        } else {
            if popover.isShown { closePopover() } else { openPopover() }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: L.settings,
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: L.checkForUpdates,
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        updateItem.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise", accessibilityDescription: nil)
        menu.addItem(updateItem)

        menu.addItem(.separator())

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
        healStatusItemIfNeeded()
        guard let button = statusItem.button else { return }
        notesStore.reloadFromDisk()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // NSPopover sits at .popUpMenu (101). On recent macOS the system IME candidate
        // window is at the same or lower level, so it renders behind the popover.
        // Dropping to .floating (3) lets the IME appear above us while still keeping
        // us above normal app windows (level 0).
        popover.contentViewController?.view.window?.level = .floating
        if !isPinned {
            eventMonitor?.start()
        }
    }

    private func closePopover() {
        notesStore.flush()
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
