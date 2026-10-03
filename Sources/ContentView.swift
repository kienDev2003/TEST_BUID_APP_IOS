import SwiftUI
import WebKit

struct ContentView: View {
    let websiteUrl = URL(string: "https://flight-booking-b2b-ui.kien-developer.id.vn")!

    var body: some View {
        WebViewWrapper(url: websiteUrl)
            .ignoresSafeArea()
    }
}

struct WebViewWrapper: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}