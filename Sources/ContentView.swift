import SwiftUI
import WebKit
import Security

struct ContentView: View {
    let websiteUrl = URL(string: "https://flight-booking-b2b-ui.kien-developer.id.vn/pages/main.html")!

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

    // Trả về OSStatus để hiển thị debug (0 = thành công)
    @discardableResult
    func saveToken(_ token: String) -> OSStatus {
        let data = Data(token.utf8)

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
        context.coordinator.webView = webView

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

        weak var webView: WKWebView?

        // ===== DEBUG: hiện thông báo nổi trên trang (xoá khi xong) =====
        func showDebug(_ text: String) {
            let safe = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: " ")
            let js = """
            (function(){
              var d=document.createElement('div');
              d.textContent='[iOS] \(safe)';
              d.style.cssText='position:fixed;left:8px;right:8px;top:50px;z-index:2147483647;background:rgba(0,0,0,.85);color:#0f0;font:12px monospace;padding:8px;border-radius:6px;word-break:break-all;pointer-events:none';
              (document.body||document.documentElement).appendChild(d);
              setTimeout(function(){d.remove()},6000);
            })();
            """
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        // Khi trang load xong: báo trạng thái bridge / localStorage / Keychain
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = """
            JSON.stringify({
                bridge: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.keychainBridge),
                lsToken: !!localStorage.getItem('vbs_refresh_token')
            })
            """
            webView.evaluateJavaScript(js) { [weak self] result, error in
                let kc = KeychainHelper.shared.getToken() != nil
                self?.showDebug("load: \(result as? String ?? "nil") keychain=\(kc)")
            }
        }

        // Hứng message từ JS
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "keychainBridge",
                  let dict = message.body as? [String: Any],
                  let action = dict["action"] as? String else {
                showDebug("bridge nhận message lạ")
                return
            }

            if action == "save", let token = dict["token"] as? String, !token.isEmpty {
                let status = KeychainHelper.shared.saveToken(token)
                let readBack = KeychainHelper.shared.getToken() != nil
                showDebug("SAVE status=\(status) readBack=\(readBack)")
            } else if action == "delete" {
                let status = KeychainHelper.shared.deleteToken()
                showDebug("DELETE status=\(status)")
            } else {
                showDebug("action=\(action) nhưng token rỗng/null")
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