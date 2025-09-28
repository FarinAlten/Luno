import SwiftUI
import WebKit

// MARK: - Models

struct Tab: Identifiable, Equatable, Hashable {
    let id = UUID()
    var urlString: String
    var title: String?
}

// MARK: - Root Browser View

struct BrowserView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // Global Settings
    @AppStorage("desktopMode") private var desktopMode: Bool = false
    @AppStorage("enableJavaScript") private var enableJavaScript: Bool = true
    @AppStorage("openLinksInNewTab") private var openLinksInNewTab: Bool = true
    @AppStorage("homepageURL") private var homepageURL: String = "https://www.apple.com"
    @AppStorage("newTabBehavior") private var newTabBehavior: String = "blank" // "blank" | "homepage"
    @AppStorage("showTabStrip") private var showTabStrip: Bool = true
    @AppStorage("enableGlass") private var enableGlass: Bool = true

    // Appearance personalization
    @AppStorage("accentColorKey") private var accentColorKey: String = "blue"
    @AppStorage("tabCornerRadius") private var tabCornerRadius: Double = 12
    @AppStorage("compactUI") private var compactUI: Bool = false
    @AppStorage("startPageBackground") private var startPageBackground: String = "default"

    // Tabs
    @State private var tabs: [Tab]
    @State private var selectedTab: Tab
    @State private var webViewNavigationPublishers: [UUID: WebViewNavigationPublisher]

    // UI State
    @State private var isShowingShare: Bool = false
    @State private var isShowingTabManager: Bool = false
    @State private var startSearchText: String = ""
    @FocusState private var addressFieldFocused: Bool

    init() {
        let initialTab = Tab(urlString: "https://www.apple.com", title: "Apple")
        _tabs = State(initialValue: [initialTab])
        _selectedTab = State(initialValue: initialTab)
        _webViewNavigationPublishers = State(initialValue: [initialTab.id: WebViewNavigationPublisher()])
    }

    private var accentColor: Color { colorForTheme(accentColorKey) }
    private var tabRadius: CGFloat { CGFloat(tabCornerRadius) }
    private var vPad: CGFloat { compactUI ? 6 : 10 }
    private var hPad: CGFloat { compactUI ? 8 : 12 }
    private var hSpacing: CGFloat { compactUI ? 8 : 12 }

    var body: some View {
        ZStack {
            Group {
                if horizontalSizeClass == .compact {
                    iPhoneLayout
                } else {
                    iPadLayout
                }
            }

            // Hidden buttons to host keyboard shortcuts
            keyboardShortcutsLayer
                .opacity(0.001) // keep in hierarchy without being visible
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { selectedTab.id },
                set: { newID in
                    if let id = newID, let t = tabs.first(where: { $0.id == id }) {
                        selectTab(t)
                    }
                })
            ) {
                Section("Tabs") {
                    ForEach(tabs) { tab in
                        HStack(spacing: 12) {
                            Image(systemName: tabIcon(for: tab))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayTitle(for: tab))
                                    .lineLimit(1)
                                Text(displayURL(for: tab))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(tab.id)
                        .contextMenu {
                            Button(role: .destructive) { closeTab(tab) } label: {
                                Label("Tab schließen", systemImage: "xmark")
                            }
                            Button { duplicateTab(tab) } label: {
                                Label("Tab duplizieren", systemImage: "square.on.square")
                            }
                            Button { openTab(url: "about:blank") } label: {
                                Label("Neuer Tab", systemImage: "plus")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet { closeTab(tabs[idx]) }
                    }
                }

                Section("Aktionen") {
                    Button {
                        openTab(url: fixURL(homepageURL))
                    } label: {
                        Label("Startseite", systemImage: "house.fill")
                    }
                    Button {
                        openOrSelectSpecial("about:settings")
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape.fill")
                    }
                    Button {
                        openOrSelectSpecial("about:blank")
                    } label: {
                        Label("Favoriten & Lesezeichen", systemImage: "book")
                    }
                }
            }
            .navigationTitle("Menü")
            .toolbarBackground(.visible, for: .navigationBar)
        } detail: {
            VStack(spacing: 0) {
                if let publisher = webViewNavigationPublishers[selectedTab.id] {
                    // Top controls + address bar + actions with Liquid Glass
                    topGlassToolbar(publisher: publisher)

                    // Tab Strip (scrollable) with Liquid Glass
                    if showTabStrip { tabStrip }

                    // Progress bar
                    if publisher.progress < 1.0 {
                        ProgressView(value: publisher.progress)
                            .progressViewStyle(.linear)
                            .tint(accentColor)
                            .padding(.horizontal)
                    }

                    // Content area
                    Group {
                        if selectedTab.urlString == "about:settings" {
                            SettingsView()
                        } else if selectedTab.urlString == "about:blank" {
                            favoritesAndBookmarks
                        } else if let url = URL(string: fixURL(selectedTab.urlString)) {
                            WebView(
                                url: url,
                                navigationPublisher: publisher,
                                useDesktopUserAgent: desktopMode,
                                openLinksInNewTab: openLinksInNewTab,
                                enableJavaScript: enableJavaScript,
                                onCreateNewTab: { newURL in
                                    openTab(url: newURL.absoluteString)
                                },
                                onURLChange: { url in
                                    syncSelectedTabURL(url.absoluteString)
                                },
                                onTitleChange: { title in
                                    syncSelectedTabTitle(title)
                                }
                            )
                            .edgesIgnoringSafeArea(.bottom)
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingShare) {
                if let url = URL(string: fixURL(selectedTab.urlString)) {
                    ActivityView(activityItems: [url])
                        .presentationDetents([.medium])
                }
            }
            .sheet(isPresented: $isShowingTabManager) {
                TabManagerView(
                    tabs: $tabs,
                    selectedTab: $selectedTab,
                    onClose: { closeTab($0) },
                    onSelect: { selectTab($0) }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Top Glass Toolbar (iPad)

    private func topGlassToolbar(publisher: WebViewNavigationPublisher) -> some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: hSpacing) {
                // Tab overview
                Button { isShowingTabManager = true } label: {
                    Image(systemName: "square.on.square")
                        .font(.title2)
                }
                .buttonStyle(.glass)

                // Back / Forward
                HStack(spacing: 8) {
                    Button { publisher.action = .goBack } label: {
                        Image(systemName: "chevron.backward")
                            .foregroundStyle(publisher.canGoBack ? accentColor : .gray)
                    }
                    .disabled(!publisher.canGoBack)

                    Button { publisher.action = .goForward } label: {
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(publisher.canGoForward ? accentColor : .gray)
                    }
                    .disabled(!publisher.canGoForward)
                }
                .buttonStyle(.glass)

                // Address Field
                HStack(spacing: 8) {
                    Group {
                        if selectedTab.urlString.starts(with: "https") {
                            Image(systemName: "lock.fill").foregroundColor(.green)
                        }
                    }
                    TextField("Adresse oder Suche", text: Binding(
                        get: { selectedTab.urlString },
                        set: { newValue in
                            if let index = tabs.firstIndex(of: selectedTab) {
                                tabs[index].urlString = newValue
                                selectedTab = tabs[index]
                            }
                        }
                    ), onCommit: {
                        if let index = tabs.firstIndex(of: selectedTab) {
                            let fixed = fixURL(tabs[index].urlString)
                            tabs[index].urlString = fixed
                            publisher.url = URL(string: fixed)
                            publisher.action = .load
                        }
                    })
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    .focused($addressFieldFocused)

                    Button {
                        if publisher.progress < 1.0 {
                            publisher.webView?.stopLoading()
                        } else if let index = tabs.firstIndex(of: selectedTab) {
                            let fixed = fixURL(tabs[index].urlString)
                            tabs[index].urlString = fixed
                            publisher.url = URL(string: fixed)
                            publisher.action = .load
                        }
                    } label: {
                        Image(systemName: publisher.progress < 1.0 ? "xmark.circle.fill" : "arrow.clockwise")
                            .foregroundStyle(accentColor)
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .background(
                    RoundedRectangle(cornerRadius: tabRadius)
                        .fill(Color.clear)
                )
                .maybeGlassRect(enableGlass, cornerRadius: tabRadius)

                Spacer(minLength: 8)

                // Share
                Button { isShowingShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                }
                .buttonStyle(.glass)

                // New Tab
                Button { newBlankTab() } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal)
            .padding(.vertical, compactUI ? 4 : 6)
            .maybeGlass(enableGlass)
        }
    }

    // MARK: - Tab Strip (iPad)

    private var tabStrip: some View {
        GlassEffectContainer(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        HStack(spacing: 8) {
                            Text(displayTitle(for: tab))
                                .lineLimit(1)
                                .font(.subheadline)
                            Button(role: .destructive) { closeTab(tab) } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, hPad)
                        .padding(.vertical, compactUI ? 6 : 8)
                        .background(
                            RoundedRectangle(cornerRadius: tabRadius)
                                .fill(tab.id == selectedTab.id ? accentColor.opacity(0.18) : Color.clear)
                        )
                        .maybeGlassRect(enableGlass, cornerRadius: tabRadius)
                        .onTapGesture { selectTab(tab) }
                        .contextMenu {
                            Button("Tab schließen", role: .destructive) { closeTab(tab) }
                            Button("Duplizieren") { duplicateTab(tab) }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - iPhone Layout (leichte Glass-Optimierung)

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            if let publisher = webViewNavigationPublishers[selectedTab.id] {
                HStack(spacing: 8) {
                    Group {
                        if selectedTab.urlString.starts(with: "https") {
                            Image(systemName: "lock.fill").foregroundColor(.green)
                        } else if selectedTab.urlString.starts(with: "http") {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                        } else {
                            Image(systemName: "questionmark.circle").foregroundColor(.gray)
                        }
                    }
                    .font(.body)

                    TextField("Adresse oder Suche", text: Binding(
                        get: { selectedTab.urlString },
                        set: { newValue in
                            if let index = tabs.firstIndex(of: selectedTab) {
                                tabs[index].urlString = newValue
                                selectedTab = tabs[index]
                            }
                        }
                    ), onCommit: {
                        if let index = tabs.firstIndex(of: selectedTab) {
                            let result = searchOrURL(tabs[index].urlString)
                            tabs[index].urlString = result
                            publisher.url = URL(string: result)
                            publisher.action = .load
                        }
                    })
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .focused($addressFieldFocused)

                    Button {
                        if publisher.progress < 1.0 {
                            publisher.webView?.stopLoading()
                        } else if let index = tabs.firstIndex(of: selectedTab) {
                            let result = searchOrURL(tabs[index].urlString)
                            tabs[index].urlString = result
                            publisher.url = URL(string: result)
                            publisher.action = .load
                        }
                    } label: {
                        Image(systemName: publisher.progress < 1.0 ? "xmark.circle.fill" : "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(accentColor)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .maybeGlass(enableGlass)
            }

            if let publisher = webViewNavigationPublishers[selectedTab.id], publisher.progress < 1.0 {
                ProgressView(value: publisher.progress)
                    .progressViewStyle(.linear)
                    .tint(accentColor)
                    .padding(.horizontal)
            }

            Group {
                if selectedTab.urlString == "about:settings" {
                    SettingsView()
                } else if selectedTab.urlString == "about:blank" {
                    favoritesAndBookmarks
                } else if let url = URL(string: fixURL(selectedTab.urlString)),
                          let publisher = webViewNavigationPublishers[selectedTab.id] {
                    WebView(
                        url: url,
                        navigationPublisher: publisher,
                        useDesktopUserAgent: desktopMode,
                        openLinksInNewTab: openLinksInNewTab,
                        enableJavaScript: enableJavaScript,
                        onCreateNewTab: { newURL in openTab(url: newURL.absoluteString) },
                        onURLChange: { url in syncSelectedTabURL(url.absoluteString) },
                        onTitleChange: { title in syncSelectedTabTitle(title) }
                    )
                    .edgesIgnoringSafeArea(.bottom)
                }
            }

            if let publisher = webViewNavigationPublishers[selectedTab.id] {
                HStack(spacing: 28) {
                    Button { publisher.action = .goBack } label: {
                        Image(systemName: "chevron.backward").font(.title2)
                            .foregroundColor(publisher.canGoBack ? accentColor : .gray)
                    }
                    .disabled(!publisher.canGoBack)

                    Button { publisher.action = .goForward } label: {
                        Image(systemName: "chevron.forward").font(.title2)
                            .foregroundColor(publisher.canGoForward ? accentColor : .gray)
                    }
                    .disabled(!publisher.canGoForward)

                    Button {
                        if publisher.progress < 1.0 { publisher.webView?.stopLoading() }
                        else if let index = tabs.firstIndex(of: selectedTab) {
                            let result = searchOrURL(tabs[index].urlString)
                            tabs[index].urlString = result
                            publisher.url = URL(string: result)
                            publisher.action = .load
                        }
                    } label: {
                        Image(systemName: publisher.progress < 1.0 ? "xmark.circle.fill" : "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(accentColor)
                    }

                    Button { isShowingTabManager = true } label: {
                        Image(systemName: "square.on.square").font(.title2)
                    }

                    Button {
                        if let index = tabs.firstIndex(of: selectedTab) { addBookmark(url: tabs[index].urlString) }
                    } label: {
                        Image(systemName: "star").font(.title2)
                    }

                    Button { openOrSelectSpecial("about:blank") } label: {
                        Image(systemName: "book").font(.title2)
                    }

                    Button { openOrSelectSpecial("about:settings") } label: {
                        Image(systemName: "gearshape").font(.title2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .maybeGlass(enableGlass)
            }
        }
        .sheet(isPresented: $isShowingTabManager) {
            TabManagerView(
                tabs: $tabs,
                selectedTab: $selectedTab,
                onClose: { closeTab($0) },
                onSelect: { selectTab($0) }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Favorites & Bookmarks (about:blank)

    private var favoritesAndBookmarks: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Start page search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Im Web suchen", text: $startSearchText, onCommit: {
                        let result = searchOrURL(startSearchText)
                        openTab(url: result)
                        startSearchText = ""
                    })
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    Button {
                        let result = searchOrURL(startSearchText)
                        openTab(url: result)
                        startSearchText = ""
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(accentColor)
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .background(RoundedRectangle(cornerRadius: tabRadius).fill(Color.clear))
                .maybeGlassRect(enableGlass, cornerRadius: tabRadius)

                // Quick actions
                HStack(spacing: 16) {
                    Button { newBlankTab() } label: {
                        Label("Neuer Tab", systemImage: "plus")
                    }.buttonStyle(.glass)
                    Button { openOrSelectSpecial("about:settings") } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }.buttonStyle(.glass)
                    Button { openTab(url: fixURL(homepageURL)) } label: {
                        Label("Startseite", systemImage: "house")
                    }.buttonStyle(.glass)
                }

                Text("Favoriten").font(.title2).bold()
                // Favorites grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                    ForEach(["apple.com", "google.com", "github.com"], id: \.self) { site in
                        Button { openTab(url: "https://\(site)") } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .resizable().scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .padding(12)
                                    .background(Circle().fill(accentColor.opacity(0.15)))
                                Text(site)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: tabRadius).fill(Color.clear))
                            .maybeGlassRect(enableGlass, cornerRadius: tabRadius)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let bookmarks = getBookmarks(), !bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lesezeichen").font(.headline)
                        ForEach(bookmarks, id: \.self) { url in
                            Button(action: { openTab(url: url) }) {
                                HStack {
                                    Image(systemName: "star.fill").foregroundColor(.yellow)
                                    Text(url).lineLimit(1).font(.subheadline)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top)
                }
            }
            .padding()
        }
        .background(startPageBackgroundView.ignoresSafeArea())
    }

    private var startPageBackgroundView: some View {
        Group {
            switch startPageBackground {
            case "blue":
                LinearGradient(colors: [Color.blue.opacity(0.25), Color.indigo.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case "sunset":
                LinearGradient(colors: [Color.orange.opacity(0.25), Color.pink.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case "forest":
                LinearGradient(colors: [Color.green.opacity(0.25), Color.teal.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            default:
                Color.clear
            }
        }
    }

    // MARK: - Keyboard Shortcuts Layer

    private var keyboardShortcutsLayer: some View {
        Group {
            // New Tab
            Button(action: { newBlankTab() }) { EmptyView() }
                .keyboardShortcut("t", modifiers: .command)

            // Close Tab
            Button(action: { closeTab(selectedTab) }) { EmptyView() }
                .keyboardShortcut("w", modifiers: .command)

            // Reload
            Button(action: { reloadSelectedTab() }) { EmptyView() }
                .keyboardShortcut("r", modifiers: .command)

            // Back / Forward
            Button(action: { if let p = webViewNavigationPublishers[selectedTab.id] { p.action = .goBack } }) { EmptyView() }
                .keyboardShortcut("[", modifiers: .command)
            Button(action: { if let p = webViewNavigationPublishers[selectedTab.id] { p.action = .goForward } }) { EmptyView() }
                .keyboardShortcut("]", modifiers: .command)

            // Focus Address Bar
            Button(action: { addressFieldFocused = true }) { EmptyView() }
                .keyboardShortcut("l", modifiers: .command)

            // Next / Previous Tab
            Button(action: { selectNextTab() }) { EmptyView() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button(action: { selectPreviousTab() }) { EmptyView() }
                .keyboardShortcut("[", modifiers: [.command, .shift])

            // Open Settings
            Button(action: { openOrSelectSpecial("about:settings") }) { EmptyView() }
                .keyboardShortcut(",", modifiers: .command)

            // Open Tab Manager
            Button(action: { isShowingTabManager = true }) { EmptyView() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }

    private func selectNextTab() {
        guard let idx = tabs.firstIndex(of: selectedTab) else { return }
        let nextIndex = (idx + 1) % tabs.count
        selectTab(tabs[nextIndex])
    }

    private func selectPreviousTab() {
        guard let idx = tabs.firstIndex(of: selectedTab) else { return }
        let prevIndex = (idx - 1 + tabs.count) % tabs.count
        selectTab(tabs[prevIndex])
    }

    private func reloadSelectedTab() {
        guard let publisher = webViewNavigationPublishers[selectedTab.id], let index = tabs.firstIndex(of: selectedTab) else { return }
        let fixed = fixURL(tabs[index].urlString)
        tabs[index].urlString = fixed
        publisher.url = URL(string: fixed)
        publisher.action = .load
    }

    // MARK: - Helpers (Display)

    private func displayTitle(for tab: Tab) -> String {
        if let title = webViewNavigationPublishers[tab.id]?.pageTitle, !title.isEmpty { return title }
        if let title = tab.title, !title.isEmpty { return title }
        return URL(string: fixURL(tab.urlString))?.host ?? tab.urlString
    }

    private func displayURL(for tab: Tab) -> String {
        URL(string: fixURL(tab.urlString))?.host ?? tab.urlString
    }

    private func tabIcon(for tab: Tab) -> String {
        let s = tab.urlString
        if s.starts(with: "about:") { return s == "about:settings" ? "gearshape" : "book" }
        if s.starts(with: "https") { return "lock.fill" }
        if s.starts(with: "http") { return "exclamationmark.triangle.fill" }
        return "globe"
    }

    // MARK: - Tab Operations

    private func newBlankTab() {
        if newTabBehavior == "homepage" {
            openTab(url: fixURL(homepageURL))
        } else {
            openTab(url: "about:blank")
        }
    }

    private func openOrSelectSpecial(_ special: String) {
        if let existing = tabs.first(where: { $0.urlString == special }) { selectTab(existing) }
        else { openTab(url: special) }
    }

    private func selectTab(_ tab: Tab) {
        selectedTab = tab
        // Ensure publisher exists
        if webViewNavigationPublishers[tab.id] == nil {
            webViewNavigationPublishers[tab.id] = WebViewNavigationPublisher()
        }
    }

    private func duplicateTab(_ tab: Tab) {
        var copy = tab
        copy = Tab(urlString: tab.urlString, title: tab.title)
        tabs.append(copy)
        webViewNavigationPublishers[copy.id] = WebViewNavigationPublisher()
        selectedTab = copy
    }

    private func closeTab(_ tab: Tab) {
        guard let idx = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: idx)
        webViewNavigationPublishers.removeValue(forKey: tab.id)
        if tabs.isEmpty {
            let newTab = Tab(urlString: "about:blank", title: nil)
            tabs.append(newTab)
            webViewNavigationPublishers[newTab.id] = WebViewNavigationPublisher()
            selectedTab = newTab
        } else {
            let newIndex = max(0, min(idx, tabs.count - 1))
            selectedTab = tabs[newIndex]
        }
    }

    private func openTab(url: String) {
        let newTab = Tab(urlString: url, title: nil)
        tabs.append(newTab)
        webViewNavigationPublishers[newTab.id] = WebViewNavigationPublisher()
        selectedTab = newTab
    }

    private func syncSelectedTabURL(_ newURL: String) {
        if let index = tabs.firstIndex(of: selectedTab) {
            tabs[index].urlString = newURL
            selectedTab = tabs[index]
        }
    }

    private func syncSelectedTabTitle(_ title: String?) {
        if let index = tabs.firstIndex(of: selectedTab) {
            tabs[index].title = title
            selectedTab = tabs[index]
        }
    }

    // MARK: - URL Helpers

    func fixURL(_ input: String) -> String {
        if input == "about:settings" || input == "about:blank" { return input }
        if input.starts(with: "http") { return input }
        if input.contains(".") && !input.contains(" ") { return "https://\(input)" }
        return searchOrURL(input)
    }

    func searchOrURL(_ input: String) -> String {
        if input == "about:settings" || input == "about:blank" { return input }
        if input.starts(with: "http") { return input }
        if input.contains(".") && !input.contains(" ") { return "https://\(input)" }
        let engine = UserDefaults.standard.string(forKey: "searchEngine") ?? "Google"
        let customTemplate = UserDefaults.standard.string(forKey: "customSearchTemplate") ?? "https://www.google.com/search?q={query}"
        let query = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        switch engine {
        case "DuckDuckGo": return "https://duckduckgo.com/?q=\(query)"
        case "Bing": return "https://www.bing.com/search?q=\(query)"
        case "Ecosia": return "https://www.ecosia.org/search?q=\(query)"
        case "Custom":
            if customTemplate.contains("{query}") {
                return customTemplate.replacingOccurrences(of: "{query}", with: query)
            } else {
                // Fallback: append query param if placeholder missing
                let sep = customTemplate.contains("?") ? "&" : "?"
                return "\(customTemplate)\(sep)q=\(query)"
            }
        default: return "https://www.google.com/search?q=\(query)"
        }
    }

    // MARK: - Bookmarks

    func addBookmark(url: String) {
        let isPrivate = UserDefaults.standard.bool(forKey: "privateMode")
        guard !isPrivate else { return }
        var bookmarks = UserDefaults.standard.stringArray(forKey: "bookmarks") ?? []
        if !bookmarks.contains(url) {
            bookmarks.append(url)
            UserDefaults.standard.set(bookmarks, forKey: "bookmarks")
        }
    }

    func getBookmarks() -> [String]? {
        let isPrivate = UserDefaults.standard.bool(forKey: "privateMode")
        guard !isPrivate else { return nil }
        return UserDefaults.standard.stringArray(forKey: "bookmarks")
    }

    // MARK: - Theme Helpers

    private func colorForTheme(_ key: String) -> Color {
        switch key {
        case "teal": return .teal
        case "purple": return .purple
        case "orange": return .orange
        case "pink": return .pink
        case "indigo": return .indigo
        case "green": return .green
        case "gray": return .gray
        default: return .blue
        }
    }
}

// MARK: - WebView Wrapper

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var navigationPublisher: WebViewNavigationPublisher

    var useDesktopUserAgent: Bool = false
    var openLinksInNewTab: Bool = true
    var enableJavaScript: Bool = true

    var onCreateNewTab: ((URL) -> Void)? = nil
    var onURLChange: ((URL) -> Void)? = nil
    var onTitleChange: ((String?) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = enableJavaScript
        let view = WKWebView(frame: .zero, configuration: config)

        if useDesktopUserAgent {
            // macOS Safari-like UA for desktop mode
            view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        } else {
            // Default system UA
        }

        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        view.scrollView.minimumZoomScale = 1.0
        view.scrollView.maximumZoomScale = 5.0
        view.scrollView.zoomScale = 1.0
        context.coordinator.webView = view
        context.coordinator.openLinksInNewTab = openLinksInNewTab

        // Pull-to-refresh
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(context.coordinator.handleRefresh(_:)), for: .valueChanged)
        view.scrollView.refreshControl = refreshControl
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Update preferences dynamically
        uiView.configuration.preferences.javaScriptEnabled = enableJavaScript

        switch navigationPublisher.action {
        case .load:
            if let newURL = navigationPublisher.url { uiView.load(URLRequest(url: newURL)) }
        case .goBack:
            uiView.goBack()
        case .goForward:
            uiView.goForward()
        default:
            break
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(navigationPublisher: navigationPublisher, onCreateNewTab: onCreateNewTab, onURLChange: onURLChange, onTitleChange: onTitleChange)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var navigationPublisher: WebViewNavigationPublisher
        weak var webView: WKWebView?
        var onCreateNewTab: ((URL) -> Void)?
        var onURLChange: ((URL) -> Void)?
        var onTitleChange: ((String?) -> Void)?
        var openLinksInNewTab: Bool = true

        init(navigationPublisher: WebViewNavigationPublisher, onCreateNewTab: ((URL) -> Void)?, onURLChange: ((URL) -> Void)?, onTitleChange: ((String?) -> Void)?) {
            self.navigationPublisher = navigationPublisher
            self.onCreateNewTab = onCreateNewTab
            self.onURLChange = onURLChange
            self.onTitleChange = onTitleChange
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            navigationPublisher.canGoBack = webView.canGoBack
            navigationPublisher.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            navigationPublisher.canGoBack = webView.canGoBack
            navigationPublisher.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigationPublisher.canGoBack = webView.canGoBack
            navigationPublisher.canGoForward = webView.canGoForward
            navigationPublisher.action = .none
            webView.scrollView.refreshControl?.endRefreshing()

            if let url = webView.url {
                navigationPublisher.currentURLString = url.absoluteString
                onURLChange?(url)
            }
            navigationPublisher.pageTitle = webView.title
            onTitleChange?(webView.title)
        }

        // Handle target=_blank and new windows
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if navigationAction.targetFrame == nil {
                if openLinksInNewTab {
                    onCreateNewTab?(url)
                } else {
                    webView.load(URLRequest(url: url))
                }
                return nil
            }
            return nil
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "estimatedProgress", let webView = object as? WKWebView {
                navigationPublisher.progress = webView.estimatedProgress
            }
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            webView?.reload()
        }

        deinit {
            webView?.removeObserver(self, forKeyPath: "estimatedProgress")
        }
    }
}

// MARK: - Navigation Controller / Publisher

class WebViewNavigationPublisher: ObservableObject {
    enum NavigationAction { case none, load, goBack, goForward }

    @Published var action: NavigationAction = .none
    @Published var url: URL?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var progress: Double = 0.0

    @Published var currentURLString: String = ""
    @Published var pageTitle: String? = nil

    weak var webView: WKWebView?
}

// MARK: - App Entry

@main
struct SafariCloneApp: App {
    var body: some Scene {
        WindowGroup { BrowserView() }
    }
}

// MARK: - Settings (Sidebar)

struct SettingsView: View {
    @State private var selection: SettingsCategory? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("Einstellungen")
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    SettingsGeneralView()
                        .navigationTitle("Allgemein")
                case .homepage:
                    SettingsHomepageTabsView()
                        .navigationTitle("Startseite & Tabs")
                case .features:
                    SettingsFeaturesView()
                        .navigationTitle("Funktionen")
                case .appearance:
                    SettingsAppearanceView()
                        .navigationTitle("Darstellung")
                case .privacyData:
                    SettingsPrivacyDataView()
                        .navigationTitle("Datenschutz & Daten")
                }
            }
            .padding()
        }
    }
}

private enum SettingsCategory: CaseIterable, Identifiable {
    case general
    case homepage
    case features
    case appearance
    case privacyData

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "Allgemein"
        case .homepage: return "Startseite & Tabs"
        case .features: return "Funktionen"
        case .appearance: return "Darstellung"
        case .privacyData: return "Datenschutz & Daten"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .homepage: return "house"
        case .features: return "slider.horizontal.3"
        case .appearance: return "sparkles"
        case .privacyData: return "lock.shield"
        }
    }
}

private struct SettingsGeneralView: View {
    @AppStorage("searchEngine") private var searchEngine: String = "Google"
    @AppStorage("customSearchTemplate") private var customSearchTemplate: String = "https://www.google.com/search?q={query}"

    var body: some View {
        Form {
            Section("Suchmaschine") {
                Picker("Suchmaschine", selection: $searchEngine) {
                    Text("Google").tag("Google")
                    Text("DuckDuckGo").tag("DuckDuckGo")
                    Text("Bing").tag("Bing")
                    Text("Ecosia").tag("Ecosia")
                    Text("Eigene").tag("Custom")
                }
                .pickerStyle(.segmented)

                if searchEngine == "Custom" {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Vorlage mit {query}", text: $customSearchTemplate)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        Text("Beispiel: https://example.com/search?q={query}")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct SettingsHomepageTabsView: View {
    @AppStorage("homepageURL") private var homepageURL: String = "https://www.apple.com"
    @AppStorage("newTabBehavior") private var newTabBehavior: String = "blank" // blank | homepage
    @AppStorage("showTabStrip") private var showTabStrip: Bool = true

    var body: some View {
        Form {
            Section("Startseite") {
                TextField("Startseiten-URL", text: $homepageURL)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
            }
            Section("Neuer Tab") {
                Picker("Neuer Tab öffnet", selection: $newTabBehavior) {
                    Text("Leere Seite").tag("blank")
                    Text("Startseite").tag("homepage")
                }
                .pickerStyle(.segmented)
            }
            Section("Tabs") {
                Toggle("Tab-Leiste anzeigen (iPad)", isOn: $showTabStrip)
            }
        }
    }
}

private struct SettingsFeaturesView: View {
    @AppStorage("enableJavaScript") private var enableJavaScript: Bool = true
    @AppStorage("openLinksInNewTab") private var openLinksInNewTab: Bool = true
    @AppStorage("desktopMode") private var desktopMode: Bool = false

    var body: some View {
        Form {
            Section("Web") {
                Toggle("JavaScript aktivieren", isOn: $enableJavaScript)
                Toggle("Links in neuem Tab öffnen", isOn: $openLinksInNewTab)
                Toggle("Desktop-Modus (User-Agent)", isOn: $desktopMode)
            }
        }
    }
}

private struct SettingsAppearanceView: View {
    @AppStorage("enableGlass") private var enableGlass: Bool = true
    @AppStorage("accentColorKey") private var accentColorKey: String = "blue"
    @AppStorage("tabCornerRadius") private var tabCornerRadius: Double = 12
    @AppStorage("compactUI") private var compactUI: Bool = false
    @AppStorage("startPageBackground") private var startPageBackground: String = "default"

    var body: some View {
        Form {
            Section("Liquid Glass") {
                Toggle("Liquid Glass aktivieren", isOn: $enableGlass)
            }
            Section("Akzentfarbe") {
                Picker("Akzentfarbe", selection: $accentColorKey) {
                    Text("Blau").tag("blue")
                    Text("Türkis").tag("teal")
                    Text("Violett").tag("purple")
                    Text("Orange").tag("orange")
                    Text("Pink").tag("pink")
                    Text("Indigo").tag("indigo")
                    Text("Grün").tag("green")
                    Text("Grau").tag("gray")
                }
                .pickerStyle(.segmented)
            }
            Section("Form & Dichte") {
                HStack {
                    Text("Tab-Eckenradius")
                    Slider(value: $tabCornerRadius, in: 8...24)
                    Text("\(Int(tabCornerRadius))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 34)
                }
                Toggle("Kompakte UI", isOn: $compactUI)
            }
            Section("Startseite Hintergrund") {
                Picker("Hintergrund", selection: $startPageBackground) {
                    Text("Standard").tag("default")
                    Text("Blau").tag("blue")
                    Text("Sonnenuntergang").tag("sunset")
                    Text("Wald").tag("forest")
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private struct SettingsPrivacyDataView: View {
    @AppStorage("privateMode") private var privateMode: Bool = false
    @State private var showDataClearedAlert: Bool = false
    @State private var showBookmarksClearedAlert: Bool = false

    var body: some View {
        Form {
            Section("Datenschutz") {
                Toggle("Privater Modus", isOn: $privateMode)
            }
            Section("Daten löschen") {
                Button(role: .destructive) { clearWebsiteData() } label: {
                    Label("Websitedaten löschen", systemImage: "trash")
                }
                .alert("Websitedaten gelöscht", isPresented: $showDataClearedAlert) {
                    Button("OK", role: .cancel) { }
                }

                Button(role: .destructive) { clearBookmarks() } label: {
                    Label("Lesezeichen löschen", systemImage: "trash")
                }
                .alert("Lesezeichen gelöscht", isPresented: $showBookmarksClearedAlert) {
                    Button("OK", role: .cancel) { }
                }
            }
        }
    }

    private func clearWebsiteData() {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: dateFrom) {
            showDataClearedAlert = true
        }
    }

    private func clearBookmarks() {
        UserDefaults.standard.removeObject(forKey: "bookmarks")
        showBookmarksClearedAlert = true
    }
}

// MARK: - ActivityView (ShareSheet)

struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Tab Manager Sheet

struct TabManagerView: View {
    @Binding var tabs: [Tab]
    @Binding var selectedTab: Tab
    var onClose: (Tab) -> Void
    var onSelect: (Tab) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(tabs) { tab in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tab.title ?? URL(string: tab.urlString)?.host ?? tab.urlString)
                                .font(.headline)
                                .lineLimit(1)
                            Text(tab.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if tab.id == selectedTab.id {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(tab) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { onClose(tab) } label: { Label("Schließen", systemImage: "xmark") }
                    }
                }
            }
            .navigationTitle("Tabs")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        }
    }
}

// MARK: - Conditional Glass Helpers

extension View {
    @ViewBuilder func maybeGlass(_ enabled: Bool) -> some View {
        if enabled { self.glassEffect(.regular.interactive()) } else { self }
    }
    @ViewBuilder func maybeGlassRect(_ enabled: Bool, cornerRadius: CGFloat) -> some View {
        if enabled { self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius)) } else { self }
    }
}
