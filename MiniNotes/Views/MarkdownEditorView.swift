import SwiftUI
import WebKit

struct MarkdownEditorView: NSViewRepresentable {
    @EnvironmentObject var notesStore: NotesStore

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "contentChanged")
        userContent.add(context.coordinator, name: "openURL")

        let config = WKWebViewConfiguration()
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.notesStore = notesStore
        context.coordinator.observePopoverLifecycle()

        loadEditor(into: webView)

        return webView
    }

    private func loadEditor(into webView: WKWebView) {
        guard
            let htmlURL   = Bundle.main.url(forResource: "editor",        withExtension: "html"),
            let bundleURL = Bundle.main.url(forResource: "editor-bundle", withExtension: "js"),
            let html      = try? String(contentsOf: htmlURL,   encoding: .utf8),
            let bundleJS  = try? String(contentsOf: bundleURL, encoding: .utf8)
        else {
            webView.loadHTMLString(
                "<body style='font-family:monospace;padding:16px;color:red'>Editor bundle not found.</body>",
                baseURL: nil
            )
            return
        }
        let inlined = html.replacingOccurrences(
            of: #"<script src="editor-bundle.js"></script>"#,
            with: "<script>\(bundleJS)</script>"
        )
        webView.loadHTMLString(inlined, baseURL: nil)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var notesStore: NotesStore?
        private var observers: [NSObjectProtocol] = []
        private var currentMode: EditorMode = .edit

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        // Listen for NSPopover open/close to suspend/resume the JS editor,
        // and for file changes to reload content without closing the popover.
        func observePopoverLifecycle() {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSPopover.didCloseNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.webView?.evaluateJavaScript("suspendEditor()", completionHandler: nil)
                }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSPopover.willShowNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.resumeEditorInWebView()
                }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: .notesFileChanged,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.resumeEditorInWebView()
                }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: .miniNotesEditorModeChanged,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let self,
                          let raw = notification.object as? String,
                          let mode = EditorMode(rawValue: raw) else { return }
                    self.currentMode = mode
                    self.applyEditorMode(mode)
                }
            )
        }

        private func resumeEditorInWebView() {
            guard let webView, let notesStore else { return }
            do {
                let jsonData = try JSONEncoder().encode(notesStore.content)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    webView.evaluateJavaScript("resumeEditor(\(jsonString))", completionHandler: nil)
                    // Restore current mode after the view is (re)created
                    applyEditorMode(currentMode)
                }
            } catch {}
        }

        private func applyEditorMode(_ mode: EditorMode) {
            webView?.evaluateJavaScript("setEditorMode('\(mode.rawValue)')", completionHandler: nil)
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "contentChanged":
                guard let text = message.body as? String else { return }
                notesStore?.save(text)
            case "openURL":
                guard let urlString = message.body as? String,
                      let url = URL(string: urlString) else { return }
                NSWorkspace.shared.open(url)
                NotificationCenter.default.post(name: .miniNotesClosePopover, object: nil)
            default:
                break
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let notesStore else { return }
            do {
                let jsonData = try JSONEncoder().encode(notesStore.content)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    webView.evaluateJavaScript("setInitialContent(\(jsonString))", completionHandler: nil)
                }
            } catch {
                webView.evaluateJavaScript("setInitialContent('')", completionHandler: nil)
            }
        }
    }
}
