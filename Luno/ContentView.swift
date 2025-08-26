import SwiftUI
import WebKit

struct Tab: Identifiable, Equatable, Hashable {
    let id = UUID()
    var urlString: String
}

struct BrowserView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var tabs: [Tab] = [Tab(urlString: "https://www.apple.com")]
    @State private var selectedTab: Tab
    @State private var webViewNavigationPublishers: [UUID: WebViewNavigationPublisher] = [:]

    init() {
        let initialTab = Tab(urlString: "https://www.apple.com")
        _selectedTab = State(initialValue: initialTab)
        _webViewNavigationPublishers = State(initialValue: [initialTab.id: WebViewNavigationPublisher()])
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                Button(action: {
                    let homeTab = Tab(urlString: "https://www.apple.com")
                    tabs.append(homeTab)
                    webViewNavigationPublishers[homeTab.id] = WebViewNavigationPublisher()
                    selectedTab = homeTab
                }) {
                    Label("Startseite", systemImage: "house.fill")
                }

                Button(action: {
                    let settingsTab = Tab(urlString: "about:settings")
                    tabs.append(settingsTab)
                    webViewNavigationPublishers[settingsTab.id] = WebViewNavigationPublisher()
                    selectedTab = settingsTab
                }) {
                    Label("Einstellungen", systemImage: "gearshape.fill")
                }
            }
            .navigationTitle("Menü")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        } detail: {
            VStack(spacing: 0) {
                if let publisher = webViewNavigationPublishers[selectedTab.id] {
                    // Neue Toolbar-HStack für iPadLayout
                    HStack(spacing: 12) {
                        // Tab Overview Button
                        Button {
                            // Tab-Übersicht könnte hier später implementiert werden
                        } label: {
                            Image(systemName: "square.on.square")
                                .font(.title2)
                        }

                        // Back/Forward
                        Button {
                            publisher.action = .goBack
                        } label: {
                            Image(systemName: "chevron.backward")
                                .foregroundColor(publisher.canGoBack ? .blue : .gray)
                        }
                        .disabled(!publisher.canGoBack)

                        Button {
                            publisher.action = .goForward
                        } label: {
                            Image(systemName: "chevron.forward")
                                .foregroundColor(publisher.canGoForward ? .blue : .gray)
                        }
                        .disabled(!publisher.canGoForward)

                        // Address Field
                        HStack {
                            if selectedTab.urlString.starts(with: "https") {
                                Image(systemName: "lock.fill").foregroundColor(.green)
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
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Spacer()

                        // Share
                        Button {
                            // ShareSheet öffnen
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                        }

                        // New Tab
                        Button {
                            let newTab = Tab(urlString: "about:blank")
                            tabs.append(newTab)
                            webViewNavigationPublishers[newTab.id] = WebViewNavigationPublisher()
                            selectedTab = newTab
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)

                    if publisher.progress < 1.0 {
                        ProgressView(value: publisher.progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding(.horizontal)
                    }

                    if selectedTab.urlString == "about:settings" {
                        SettingsView()
                    } else if selectedTab.urlString == "about:blank" {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("Favoriten")
                                    .font(.title2)
                                    .bold()
                                HStack(spacing: 24) {
                                    ForEach(["apple.com", "google.com", "github.com"], id: \.self) { site in
                                        Button {
                                            openTab(url: "https://\(site)")
                                        } label: {
                                            VStack {
                                                Image(systemName: "globe")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 40, height: 40)
                                                    .padding(10)
                                                    .background(.thinMaterial)
                                                    .clipShape(Circle())
                                                Text(site)
                                                    .font(.caption)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .padding()
                        }
                    } else if let url = URL(string: fixURL(selectedTab.urlString)) {
                        WebView(url: url, navigationPublisher: publisher)
                            .edgesIgnoringSafeArea(.bottom)
                    }
                }
            }
        }
    }

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            // Address bar at the top
            if let publisher = webViewNavigationPublishers[selectedTab.id] {
                HStack(spacing: 8) {
                    // Schloss-Icon oder Warnung
                    Group {
                        if selectedTab.urlString.starts(with: "https") {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.green)
                        } else if selectedTab.urlString.starts(with: "http") {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                        } else {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.gray)
                        }
                    }
                    .font(.body)
                    // Address field
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
                    // Reload/Stop button
                    Button {
                        if publisher.progress < 1.0 {
                            // Stop loading
                            if let webView = publisher.webView {
                                webView.stopLoading()
                            }
                        } else if let index = tabs.firstIndex(of: selectedTab) {
                            let result = searchOrURL(tabs[index].urlString)
                            tabs[index].urlString = result
                            publisher.url = URL(string: result)
                            publisher.action = .load
                        }
                    } label: {
                        Image(systemName: publisher.progress < 1.0 ? "xmark.circle.fill" : "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Progress bar
            if let publisher = webViewNavigationPublishers[selectedTab.id], publisher.progress < 1.0 {
                ProgressView(value: publisher.progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal)
            }

            // WebView or about:blank/settings
            Group {
                if selectedTab.urlString == "about:settings" {
                    SettingsView()
                } else if selectedTab.urlString == "about:blank" {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Favoriten")
                                .font(.title2)
                                .bold()
                            HStack(spacing: 24) {
                                ForEach(["apple.com", "google.com", "github.com"], id: \.self) { site in
                                    Button {
                                        openTab(url: "https://\(site)")
                                    } label: {
                                        VStack {
                                            Image(systemName: "globe")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 40, height: 40)
                                                .padding(10)
                                                .background(.thinMaterial)
                                                .clipShape(Circle())
                                            Text(site)
                                                .font(.caption)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                            // Bookmarks aus UserDefaults
                            if let bookmarks = getBookmarks(), !bookmarks.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Lesezeichen")
                                        .font(.headline)
                                    ForEach(bookmarks, id: \.self) { url in
                                        Button(action: {
                                            openTab(url: url)
                                        }) {
                                            HStack {
                                                Image(systemName: "star.fill")
                                                    .foregroundColor(.yellow)
                                                Text(url)
                                                    .lineLimit(1)
                                                    .font(.subheadline)
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
                } else if let url = URL(string: fixURL(selectedTab.urlString)),
                          let publisher = webViewNavigationPublishers[selectedTab.id] {
                    WebView(url: url, navigationPublisher: publisher)
                        .edgesIgnoringSafeArea(.bottom)
                }
            }

            // Toolbar at the bottom
            if let publisher = webViewNavigationPublishers[selectedTab.id] {
                HStack(spacing: 28) {
                    Button(action: {
                        publisher.action = .goBack
                    }) {
                        Image(systemName: "chevron.backward")
                            .font(.title2)
                            .foregroundColor(publisher.canGoBack ? .blue : .gray)
                    }
                    .disabled(!publisher.canGoBack)

                    Button(action: {
                        publisher.action = .goForward
                    }) {
                        Image(systemName: "chevron.forward")
                            .font(.title2)
                            .foregroundColor(publisher.canGoForward ? .blue : .gray)
                    }
                    .disabled(!publisher.canGoForward)

                    Button(action: {
                        if publisher.progress < 1.0 {
                            if let webView = publisher.webView {
                                webView.stopLoading()
                            }
                        } else if let index = tabs.firstIndex(of: selectedTab) {
                            let result = searchOrURL(tabs[index].urlString)
                            tabs[index].urlString = result
                            publisher.url = URL(string: result)
                            publisher.action = .load
                        }
                    }) {
                        Image(systemName: publisher.progress < 1.0 ? "xmark.circle.fill" : "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }

                    // Tabs
                    Button(action: {
                        // Show tab selector (not implemented, placeholder for now)
                        // Could show a sheet to manage tabs
                    }) {
                        Image(systemName: "square.on.square")
                            .font(.title2)
                    }

                    // Bookmarks: add current page to bookmarks
                    Button(action: {
                        if let index = tabs.firstIndex(of: selectedTab) {
                            addBookmark(url: tabs[index].urlString)
                        }
                    }) {
                        Image(systemName: "star")
                            .font(.title2)
                    }

                    // Bookmarks list (show about:blank)
                    Button(action: {
                        if let blankTab = tabs.first(where: { $0.urlString == "about:blank" }) {
                            selectedTab = blankTab
                        } else {
                            let blankTab = Tab(urlString: "about:blank")
                            tabs.append(blankTab)
                            webViewNavigationPublishers[blankTab.id] = WebViewNavigationPublisher()
                            selectedTab = blankTab
                        }
                    }) {
                        Image(systemName: "book")
                            .font(.title2)
                    }

                    // Settings
                    Button(action: {
                        if let settingsTab = tabs.first(where: { $0.urlString == "about:settings" }) {
                            selectedTab = settingsTab
                        } else {
                            let settingsTab = Tab(urlString: "about:settings")
                            tabs.append(settingsTab)
                            webViewNavigationPublishers[settingsTab.id] = WebViewNavigationPublisher()
                            selectedTab = settingsTab
                        }
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }

    func fixURL(_ input: String) -> String {
        if input == "about:settings" || input == "about:blank" {
            return input
        }
        // If input looks like a URL with scheme, return as is
        if input.starts(with: "http") {
            return input
        }
        // If input has a dot (.), treat as domain
        if input.contains(".") && !input.contains(" ") {
            return "https://\(input)"
        }
        // Otherwise treat as search
        return searchOrURL(input)
    }

    // --- Suchmaschinen-Support ---
    func searchOrURL(_ input: String) -> String {
        // If input is about:settings/about:blank, passthrough
        if input == "about:settings" || input == "about:blank" {
            return input
        }
        // If input looks like URL with scheme
        if input.starts(with: "http") {
            return input
        }
        // If input has a dot and no spaces, treat as domain
        if input.contains(".") && !input.contains(" ") {
            return "https://\(input)"
        }
        // Otherwise, treat as search query
        let engine = UserDefaults.standard.string(forKey: "searchEngine") ?? "Google"
        let query = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        switch engine {
        case "DuckDuckGo":
            return "https://duckduckgo.com/?q=\(query)"
        case "Bing":
            return "https://www.bing.com/search?q=\(query)"
        case "Ecosia":
            return "https://www.ecosia.org/search?q=\(query)"
        default:
            return "https://www.google.com/search?q=\(query)"
        }
    }

    // --- Bookmarks ---
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

    private func openTab(url: String) {
        let newTab = Tab(urlString: url)
        tabs.append(newTab)
        webViewNavigationPublishers[newTab.id] = WebViewNavigationPublisher()
        selectedTab = newTab
    }
}

// MARK: - WebView Wrapper

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var navigationPublisher: WebViewNavigationPublisher

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        view.navigationDelegate = context.coordinator
        view.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        view.scrollView.minimumZoomScale = 1.0
        view.scrollView.maximumZoomScale = 5.0
        view.scrollView.zoomScale = 1.0
        context.coordinator.webView = view
        // Pull-to-refresh
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(context.coordinator.handleRefresh(_:)), for: .valueChanged)
        view.scrollView.refreshControl = refreshControl
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        switch navigationPublisher.action {
        case .load:
            if let newURL = navigationPublisher.url {
                uiView.load(URLRequest(url: newURL))
            }
        case .goBack:
            uiView.goBack()
        case .goForward:
            uiView.goForward()
        default:
            break
        }
        // navigationPublisher.action = .none // moved to didFinish in Coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(navigationPublisher: navigationPublisher)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var navigationPublisher: WebViewNavigationPublisher
        weak var webView: WKWebView?

        init(navigationPublisher: WebViewNavigationPublisher) {
            self.navigationPublisher = navigationPublisher
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigationPublisher.canGoBack = webView.canGoBack
            navigationPublisher.canGoForward = webView.canGoForward
            navigationPublisher.action = .none
            webView.scrollView.refreshControl?.endRefreshing()
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

// MARK: - Navigation Controller

class WebViewNavigationPublisher: ObservableObject {
    enum NavigationAction {
        case none, load, goBack, goForward
    }

    @Published var action: NavigationAction = .none
    @Published var url: URL?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var progress: Double = 0.0
    // Für Stop-Button Zugriff auf WKWebView (nur für iPhoneLayout)
    weak var webView: WKWebView?
}

// MARK: - App Entry

@main
struct SafariCloneApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("searchEngine") private var searchEngine: String = "Google"
    @AppStorage("privateMode") private var privateMode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Einstellungen")
                .font(.title)
                .padding(.bottom)

            // Suchmaschine auswählen
            VStack(alignment: .leading, spacing: 8) {
                Text("Suchmaschine auswählen:")
                    .font(.headline)
                Picker("Suchmaschine", selection: $searchEngine) {
                    Text("Google").tag("Google")
                    Text("DuckDuckGo").tag("DuckDuckGo")
                    Text("Bing").tag("Bing")
                    Text("Ecosia").tag("Ecosia")
                }
                .pickerStyle(.segmented)
            }

            // Privater Modus
            Toggle(isOn: $privateMode) {
                Label("Privater Modus", systemImage: "eye.slash")
            }
            .onChange(of: privateMode) { newValue in
                if newValue {
                    // Optionally: Clear tabs/bookmarks when activating private mode
                }
            }
            .padding(.top)

            Spacer()
        }
        .padding()
    }
}
