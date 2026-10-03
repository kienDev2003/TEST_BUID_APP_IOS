import SwiftUI
import WebKit

struct ContentView: View {
    // URL web app B2B của bạn
    let websiteUrl = URL(string: "https://flight-booking-b2b-ui.kien-developer.id.vn")!

    var body: some View {
        WebViewWrapper(url: websiteUrl)
            .ignoresSafeArea() // Che phủ toàn màn hình (kể cả tai thỏ/dynamic island)
    }
}

struct WebViewWrapper: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        
        // Tắt hiệu ứng kéo nảy (bounce) để tạo cảm giác giống App Native thay vì Trình duyệt
        webView.scrollView.bounces = false 
        
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Không cần xử lý update cho logic webview tĩnh
    }
}