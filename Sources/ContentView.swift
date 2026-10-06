import SwiftUI
import WebKit

struct ContentView: View {
    let websiteUrl = URL(string: "https://flight-booking-b2b-ui.kien-developer.id.vn/pages/main.html")!

    var body: some View {
        WebViewWrapper(url: websiteUrl)
            .ignoresSafeArea()
    }
}

// ----------------------------------------
// MARK: - Keychain Helper Đơn giản
// ----------------------------------------
class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "vn.id.kien-developer.flightbooking"
    private let account = "refreshToken"
    
    func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary
        
        SecItemDelete(query)
        SecItemAdd(query, nil)
    }
    
    func getToken() -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func deleteToken() {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        SecItemDelete(query)
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
        
        if let savedToken = KeychainHelper.shared.getToken() {
            let jsCode = "window.localStorage.setItem('vbs_refresh_token', '\(savedToken)');"
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
        
        // Hứng Message từ JS
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "keychainBridge" {
                if let dict = message.body as? [String: Any] {
                    let action = dict["action"] as? String
                    
                    if action == "save", let token = dict["token"] as? String {
                        KeychainHelper.shared.saveToken(token)
                        print("Đã lưu token vào Keychain")
                    } else if action == "delete" {
                        KeychainHelper.shared.deleteToken()
                        print("Đã xoá token khỏi Keychain")
                    }
                }
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