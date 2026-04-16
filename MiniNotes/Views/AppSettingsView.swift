import AppKit
import SwiftUI

// MARK: - Root

struct AppSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: L.generalTab
            case .about:   L.aboutTab
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 625, height: 440)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.appSettingsTitle)
                .font(Font.custom("LXGWWenKai-Medium", size: 17))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ForEach(SettingsTab.allCases) { tab in
                sidebarItem(tab)
            }

            Spacer()
        }
        .frame(width: 160)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            Text(tab.label)
                .font(Font.custom("LXGWWenKai-Medium", size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    selectedTab == tab
                        ? RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.8))
                        : RoundedRectangle(cornerRadius: 6).fill(Color.clear)
                )
                .foregroundColor(selectedTab == tab ? .white : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case .general: GeneralPane(settings: settings).id(settings.appLanguage)
        case .about:   AboutPane()
        }
    }
}

// MARK: - General Pane

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.generalTab)
                .font(Font.custom("LXGWWenKai-Medium", size: 17))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            HStack(spacing: 8) {
                Text(L.languageLabel + "：")
                    .font(Font.custom("LXGWWenKai-Medium", size: 14))
                Picker("", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName)
                            .font(Font.custom("LXGWWenKai-Medium", size: 14))
                            .tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                Toggle("", isOn: $settings.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                Text(L.launchAtLogin)
                    .font(Font.custom("LXGWWenKai-Medium", size: 14))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - About Pane

private struct AboutPane: View {
    @State private var isHoveringName = false
    @State private var isHoveringGithub = false

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "\(L.aboutVersion)  \(v)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("MiniNotes")
                .font(Font.custom("LXGWWenKai-Medium", size: 36))
                .padding(.bottom, 8)

            Text(L.aboutDescription)
                .font(Font.custom("LXGWWenKai-Medium", size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            HStack(spacing: 4) {
                Text(L.aboutMadeBy)
                    .font(Font.custom("LXGWWenKai-Medium", size: 13))
                    .foregroundColor(.secondary)

                Link("Pingfan Hu", destination: URL(string: "https://pingfanhu.com")!)
                    .font(Font.custom("LXGWWenKai-Medium", size: 13))
                    .foregroundColor(Color(red: 0.42, green: 0.50, blue: 0.77))
                    .underline(isHoveringName, color: Color(red: 0.42, green: 0.50, blue: 0.77))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) { isHoveringName = hovering }
                        hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                    }

                Text(L.aboutMadeByAfter)
                    .font(Font.custom("LXGWWenKai-Medium", size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            Text(versionString)
                .font(Font.custom("LXGWWenKai-Medium", size: 13))
                .foregroundColor(.secondary)
                .padding(.bottom, 16)

            Link(destination: URL(string: "https://github.com/pingfan-hu/MiniNotes")!) {
                Image("github-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 55, height: 55)
                    .clipShape(Circle())
                    .opacity(isHoveringGithub ? 1.0 : 0.75)
                    .scaleEffect(isHoveringGithub ? 1.05 : 1.0)
            }
            .buttonStyle(.plain)
            .help("GitHub")
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHoveringGithub = hovering }
                hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 32)
    }
}
