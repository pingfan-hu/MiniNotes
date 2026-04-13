import Foundation
import Combine

extension Notification.Name {
    static let notesFileChanged = Notification.Name("MiniNotesFileChanged")
}

class NotesStore: NSObject, ObservableObject, NSFilePresenter {
    @Published private(set) var content: String = ""
    @Published private(set) var fileURL: URL
    @Published private(set) var isFileOpen: Bool
    @Published private(set) var recentFileURL: URL?
    private var saveTask: Task<Void, Never>?
    private static let userDefaultsKey = "notesFilePath"

    // MARK: NSFilePresenter

    var presentedItemURL: URL? { fileURL }
    let presentedItemOperationQueue: OperationQueue = .main

    /// Called by the OS when another coordinated writer (including iCloud) modifies the file.
    func presentedItemDidChange() {
        saveTask?.cancel()
        guard let newContent = try? String(contentsOf: fileURL, encoding: .utf8),
              newContent != content else { return }
        content = newContent
        NotificationCenter.default.post(name: .notesFileChanged, object: nil)
    }

    // MARK: Init / deinit

    init(fileURL: URL? = nil) {
        let stored = UserDefaults.standard.string(forKey: Self.userDefaultsKey)
        let hasStoredPath = stored != nil && !(stored!.isEmpty)
        let url = fileURL ?? Self.resolveFileURL()
        self.fileURL = url
        // Show landing page when no file has ever been explicitly chosen
        self.isFileOpen = fileURL != nil || hasStoredPath
        self.recentFileURL = nil
        super.init()
        content = isFileOpen ? ((try? String(contentsOf: url, encoding: .utf8)) ?? "") : ""
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    // MARK: Public API

    /// Re-reads the file from disk. Call this before showing the popover
    /// to pick up edits made by external apps that don't use NSFileCoordinator.
    func reloadFromDisk() {
        guard let newContent = try? String(contentsOf: fileURL, encoding: .utf8),
              newContent != content else { return }
        content = newContent
    }

    /// Called on every keystroke — updates in-memory content only.
    /// Disk write happens in flush(), triggered when the popover closes.
    func save(_ text: String) {
        DispatchQueue.main.async { self.content = text }
    }

    /// Writes the current in-memory content to disk. Call when the popover closes.
    func flush() {
        let snapshot = content
        let url = fileURL
        saveTask?.cancel()
        saveTask = Task { [weak self, snapshot, url] in
            guard let self else { return }
            let coordinator = NSFileCoordinator(filePresenter: self)
            var nsError: NSError?
            coordinator.coordinate(writingItemAt: url, options: [], error: &nsError) { dest in
                do {
                    try snapshot.write(to: dest, atomically: true, encoding: .utf8)
                } catch {
                    print("[MiniNotes] Save failed: \(error)")
                }
            }
            if let nsError { print("[MiniNotes] Coordination error: \(nsError)") }
        }
    }

    /// Saves the current file and returns to the landing page.
    func closeFile() {
        flush()
        recentFileURL = fileURL
        isFileOpen = false
    }

    func changeFile(to newURL: URL) {
        // Flush current content to old file immediately
        saveTask?.cancel()
        let oldCoordinator = NSFileCoordinator(filePresenter: self)
        var writeError: NSError?
        oldCoordinator.coordinate(writingItemAt: fileURL, options: [], error: &writeError) { dest in
            try? content.write(to: dest, atomically: true, encoding: .utf8)
        }

        // Re-register presenter under the new URL
        NSFileCoordinator.removeFilePresenter(self)
        fileURL = newURL
        UserDefaults.standard.set(newURL.path, forKey: Self.userDefaultsKey)
        NSFileCoordinator.addFilePresenter(self)

        // Load new file (create if it doesn't exist)
        if !FileManager.default.fileExists(atPath: newURL.path) {
            try? "".write(to: newURL, atomically: true, encoding: .utf8)
        }
        content = (try? String(contentsOf: newURL, encoding: .utf8)) ?? ""
        isFileOpen = true
        NotificationCenter.default.post(name: .notesFileChanged, object: nil)
    }

    // MARK: Private helpers

    private static func resolveFileURL() -> URL {
        if let stored = UserDefaults.standard.string(forKey: userDefaultsKey), !stored.isEmpty {
            return URL(fileURLWithPath: stored)
        }
        return defaultFileURL()
    }

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("MiniNotes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.md")
    }
}
