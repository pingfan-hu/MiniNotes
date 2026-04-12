import Foundation
import Combine

class NotesStore: ObservableObject {
    @Published private(set) var content: String = ""
    private var saveTask: Task<Void, Never>?
    let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("MiniNotes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("notes.md")

        content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func save(_ text: String) {
        DispatchQueue.main.async { self.content = text }
        saveTask?.cancel()
        saveTask = Task { [fileURL, text] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            do {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("[MiniNotes] Save failed: \(error)")
            }
        }
    }
}
