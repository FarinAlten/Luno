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
                    HStack(spacing: 16) {
                        Button(action: {
                            publisher.action = .goBack
                        }) {
                            Image(systemName: "chevron.backward.circle.fill")
                                .font(.title2)
                                .foregroundColor(publisher.canGoBack ? .blue : .gray)
                        }
                        .disabled(!publisher.canGoBack)

                        Button(action: {
                            publisher.action = .goForward
                        }) {
                            Image(systemName: "chevron.forward.circle.fill")
                                .font(.title2)
                                .foregroundColor(publisher.canGoForward ? .blue : .gray)
                        }
                        .disabled(!publisher.canGoForward)

                        TextField("Adresse eingeben", text: Binding(
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
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 2)

                        Button(action: {
                            if let index = tabs.firstIndex(of: selectedTab) {
                                let fixed = fixURL(tabs[index].urlString)
                                tabs[index].urlString = fixed
                                publisher.url = URL(string: fixed)
                                publisher.action = .load
                            }
                        }) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(radius: 2)
                    .padding(.horizontal)
                    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(tabs) { tab in
                                        Button(action: {
                                            withAnimation {
                                                selectedTab = tab
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: selectedTab == tab ? "circle.fill" : "circle")
                                                    .font(.caption2)
                                                    .foregroundColor(selectedTab == tab ? .blue : .gray)
                                                Text(tab.urlString)
                                                    .lineLimit(1)
                                                    .font(.subheadline)
                                                    .foregroundColor(selectedTab == tab ? .blue : .primary)
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(selectedTab == tab ? Color.blue.opacity(0.2) : Color.clear)
                                                    .animation(.easeInOut(duration: 0.3), value: selectedTab)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Button(action: {
                                        let newTab = Tab(urlString: "about:blank")
                                        tabs.append(newTab)
                                        webViewNavigationPublishers[newTab.id] = WebViewNavigationPublisher()
                                        withAnimation {
                                            selectedTab = newTab
                                        }
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

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
            Picker("Tab", selection: $selectedTab) {
                ForEach(tabs, id: \.id) { tab in
                    Text(tab.urlString.prefix(20))
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if let publisher = webViewNavigationPublishers[selectedTab.id] {
                HStack(spacing: 12) {
                    Button {
                        publisher.action = .goBack
                    } label: {
                        Image(systemName: "chevron.backward.circle.fill")
                            .font(.title2)
                            .foregroundColor(publisher.canGoBack ? .blue : .gray)
                    }
                    .disabled(!publisher.canGoBack)

                    Button {
                        publisher.action = .goForward
                    } label: {
                        Image(systemName: "chevron.forward.circle.fill")
                            .font(.title2)
                            .foregroundColor(publisher.canGoForward ? .blue : .gray)
                    }
                    .disabled(!publisher.canGoForward)

                    TextField("Adresse eingeben", text: Binding(
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
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.URL)

                    Button {
                        if let index = tabs.firstIndex(of: selectedTab) {
                            let fixed = fixURL(tabs[index].urlString)
                            tabs[index].urlString = fixed
                            publisher.url = URL(string: fixed)
                            publisher.action = .load
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
            }

            if let publisher = webViewNavigationPublishers[selectedTab.id], publisher.progress < 1.0 {
                ProgressView(value: publisher.progress)
                    .progressViewStyle(.linear)
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
            } else if let url = URL(string: fixURL(selectedTab.urlString)),
                      let publisher = webViewNavigationPublishers[selectedTab.id] {
                WebView(url: url, navigationPublisher: publisher)
                    .edgesIgnoringSafeArea(.bottom)
            }
        }
    }

    func fixURL(_ input: String) -> String {
        if input == "about:settings" || input == "about:blank" {
            return input
        }
        return input.starts(with: "http") ? input : "https://\(input)"
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
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "estimatedProgress", let webView = object as? WKWebView {
                navigationPublisher.progress = webView.estimatedProgress
            }
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
    var body: some View {
        VStack {
            Text("Einstellungen kommen hier hin")
                .font(.title)
                .padding()
            // Weitere Einstellungen können hier hinzugefügt werden
        }
        .padding()
    }
}
