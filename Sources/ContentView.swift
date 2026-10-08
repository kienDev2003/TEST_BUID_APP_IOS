import SwiftUI
import WebKit
import Security

struct ContentView: View {
    var websiteUrl: URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let version = formatter.string(from: Date())
        
        return URL(string: "https://flight-booking-b2b-ui.kien-developer.id.vn/pages/main.html?version=\(version)")!
    }

    var body: some View {
        WebViewWrapper(url: websiteUrl)
            .ignoresSafeArea()
    }
}

// ----------------------------------------
// MARK: - Keychain Helper
// ----------------------------------------
class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "vn.id.kien-developer.flightbooking"
    private let account = "refreshToken"

    // Query dùng chung để tìm item (KHÔNG chứa kSecValueData)
    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    @discardableResult
    func saveToken(_ token: String) -> OSStatus {
        let data = Data(token.utf8)

        // Thử update trước, chưa có item thì thêm mới
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                         [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return errSecSuccess }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil)
        }
        return updateStatus
    }

    func getToken() -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    @discardableResult
    func deleteToken() -> OSStatus {
        return SecItemDelete(baseQuery as CFDictionary)
    }
}

// ----------------------------------------
// MARK: - WebView Wrapper
// ----------------------------------------
struct WebViewWrapper: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        config.userContentController.add(context.coordinator, name: "keychainBridge")

        // Khôi phục token từ Keychain vào localStorage (chỉ khi localStorage đang trống)
        if let savedToken = KeychainHelper.shared.getToken(),
           let jsonData = try? JSONEncoder().encode(savedToken),
           let jsonToken = String(data: jsonData, encoding: .utf8) {

            let jsCode = """
            try {
                if (!window.localStorage.getItem('vbs_refresh_token')) {
                    window.localStorage.setItem('vbs_refresh_token', \(jsonToken));
                }
            } catch (e) {}
            """
            let userScript = WKUserScript(source: jsCode,
                                          injectionTime: .atDocumentStart,
                                          forMainFrameOnly: true)
            config.userContentController.addUserScript(userScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

        // Hứng message từ JS
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "keychainBridge",
                  let dict = message.body as? [String: Any],
                  let action = dict["action"] as? String else { return }

            if action == "save", let token = dict["token"] as? String, !token.isEmpty {
                KeychainHelper.shared.saveToken(token)
            } else if action == "delete" {
                KeychainHelper.shared.deleteToken()
            }
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { UIApplication.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}