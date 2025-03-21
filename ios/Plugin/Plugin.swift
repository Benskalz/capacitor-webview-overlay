import Foundation
import Capacitor
import GCDWebServer

class WebviewOverlay: UIViewController, WKUIDelegate, WKNavigationDelegate {

    var webview: WKWebView?
    var plugin: WebviewOverlayPlugin!
    var configuration: WKWebViewConfiguration!

    var closeFullscreenButton: UIButton!
    var topSafeArea: CGFloat!

    var webServer: GCDWebServer?

    var currentDecisionHandler: ((WKNavigationResponsePolicy) -> Void)? = nil

    var openNewWindow: Bool = false

    var currentUrl: URL?

    var loadUrlCall: CAPPluginCall?

    
    
    
    
    var webViewURLObserver: NSKeyValueObservation?
       
     
       
    func setupURLObserver() {
        // Observe URL changes with modern KVO syntax
        webViewURLObserver = webview?.observe(\.url, options: [.new]) { [weak self] webView, change in
            guard let self = self else { return }
            let newUrl = change.newValue ?? nil
            
            // Only notify if URL actually changed and it's the main frame URL
            if self.currentUrl?.absoluteString != newUrl?.absoluteString {
                // Check if this is a main frame navigation
                // We can determine this by comparing with the webView.url which always represents the main frame
                if webView.url?.absoluteString == newUrl?.absoluteString {
                    self.currentUrl = newUrl as? URL
                    
                    // Notify that URL has changed if listeners are registered
                    if (self.plugin.hasListeners("navigationHandler")) {
                        self.plugin.notifyListeners("navigationHandler", data: [
                            "url": newUrl?.absoluteString ?? "",
                            "newWindow": false,
                            "sameHost": true, // Assuming same host as it's typically a JS navigation
                            "currentUrl": newUrl?.absoluteString ?? "",
                            "isJsNavigation": true
                        ])
                    }
                }
            }
        }
    }
       
      
    
    
    
    
    init(_ plugin: WebviewOverlayPlugin, configuration: WKWebViewConfiguration) {
        super.init(nibName: "WebviewOverlay", bundle: nil)
        self.plugin = plugin
        self.configuration = configuration
    }

    deinit {
        self.webview?.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            // Check if the URL is a deep link (non-http/https scheme)
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme != "http" && scheme != "https" && scheme != "file" && scheme != "about" {
                // This is likely a deep link
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    decisionHandler(.cancel) // Cancel the navigation in the webview
                    return
                }
            }
            
            // Handle navigation event if listeners are registered
            if webView.url?.absoluteString == url.absoluteString {
//                self.currentUrl = newUrl as? URL
                
            if (plugin.hasListeners("navigationHandler")) {
                self.openNewWindow = navigationAction.targetFrame == nil
                plugin.notifyListeners("navigationHandler", data: [
                    "url": url.absoluteString,
                    "newWindow": self.openNewWindow,
                    "sameHost": currentUrl?.host == url.host
                ])
                // Note: We don't call the decision handler here because we'll do it in handleNavigationEvent
                self.currentDecisionHandler = { policy in
                    decisionHandler(policy == .allow ? .allow : .cancel)
                }
                return
            }
            }
        }
        
        // Default behavior: allow navigation
        decisionHandler(.allow)
    }
    override func loadView() {
        self.webview = WKWebView(frame: .zero, configuration: self.configuration)
        self.webview?.uiDelegate = self
        self.webview?.navigationDelegate = self

        view = self.webview
        view.isHidden = plugin.hidden
        self.webview?.scrollView.bounces = false
        self.webview?.allowsBackForwardNavigationGestures = true

        self.webview?.isOpaque = false
        
        
        // Rest of existing loadView implementation...
        
        // Add observer for URL changes
        setupURLObserver()
        
        // Existing observer for progress
        self.webview?.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        let button = UIButton(frame: CGRect(x: UIScreen.main.bounds.width - 60, y: 20, width: 40, height: 40))
        let image = UIImage(named: "icon", in: Bundle(for: NSClassFromString("WebviewOverlayPlugin")!), compatibleWith: nil)
        button.setImage(image, for: .normal)
        button.isHidden = true;
        button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.adjustsImageWhenHighlighted = false
        button.layer.cornerRadius = 0.5 * button.bounds.size.width
        button.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: UIBlurEffect.Style.regular))
        blur.frame = button.bounds
        blur.layer.cornerRadius = 0.5 * button.bounds.size.width
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        button.insertSubview(blur, at: 0)
        button.bringSubviewToFront(button.imageView!)

        self.closeFullscreenButton = button
        view.addSubview(self.closeFullscreenButton)

        self.webview?.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
    }

    override func viewDidLayoutSubviews() {
        self.topSafeArea = view.safeAreaInsets.top
        self.closeFullscreenButton.frame = CGRect(x: UIScreen.main.bounds.width - 60, y: self.topSafeArea + 20, width: 40, height: 40)
    }

    @objc func buttonAction(sender: UIButton!) {
        plugin.toggleFullscreen()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentUrl = webView.url
        view.isHidden = plugin.hidden
        if (plugin.hidden) {
            plugin.notifyListeners("updateSnapshot", data: [:])
        }
        if (self.loadUrlCall != nil) {
            self.loadUrlCall?.resolve()
            self.loadUrlCall = nil
        }
        plugin.notifyListeners("pageLoaded", data: [:])

        // Remove tap highlight
        let script = "function addStyleString(str) {" +
            "var node = document.createElement('style');" +
            "node.innerHTML = str;" +
            "document.body.appendChild(node);" +
            "}" +
        "addStyleString('html, body {-webkit-tap-highlight-color: transparent;}');"
        webView.evaluateJavaScript(script)
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if (plugin.hasListeners("navigationHandler")) {
                self.openNewWindow = true
            }
            self.loadUrl(url)
        }
        return nil
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.clearDecisionHandler()
    }

    func clearDecisionHandler() {
        if (self.currentDecisionHandler != nil) {
            self.currentDecisionHandler!(.allow)
            self.currentDecisionHandler = nil
        }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if (self.currentDecisionHandler != nil) {
            self.clearDecisionHandler()
        }
//        if (plugin.hasListeners("navigationHandler")) {
//            self.currentDecisionHandler = decisionHandler
//            plugin.notifyListeners("navigationHandler", data: [
//                "url": navigationResponse.response.url?.absoluteString ?? "",
//                "newWindow": self.openNewWindow,
//                "sameHost": currentUrl?.host == navigationResponse.response.url?.host
//            ])
//            self.openNewWindow = false
//        }
        else {
            decisionHandler(.allow)
            return
        }
    }

    public func clearWebServer() {
        if (self.webServer != nil) {
            if (self.webServer?.isRunning == true) {
                self.webServer?.stop()
            }
            self.webServer = nil
        }
    }

    public func loadUrl(_ url: URL) {
        if url.absoluteString.hasPrefix("file") {
            self.clearWebServer()
            self.webServer = GCDWebServer()
            self.webServer?.addGETHandler(forBasePath: "/", directoryPath: url.deletingLastPathComponent().path, indexFilename: nil, cacheAge: 3600, allowRangeRequests: true)
            do {
                try self.webServer?.start(options: [
                    GCDWebServerOption_BindToLocalhost: true
                ])
            } catch {
                print(error)
            }
            self.webview?.load(URLRequest(url: (self.webServer?.serverURL?.appendingPathComponent(url.lastPathComponent))!))
        }
        else {
            self.webview?.load(URLRequest(url: url))
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if (keyPath == "estimatedProgress") {
            plugin.notifyListeners("progress", data: ["value":self.webview?.estimatedProgress ?? 1])
        }
    }

}

@objc(WebviewOverlayPlugin)
public class WebviewOverlayPlugin: CAPPlugin {

    var width: CGFloat!
    var height: CGFloat!
    var x: CGFloat!
    var y: CGFloat!

    var hidden: Bool = false

    var fullscreen: Bool = false

    var webviewOverlay: WebviewOverlay!

    /**
     * Capacitor Plugin load
     */
    override public func load() {}

    @objc func open(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let webConfiguration = WKWebViewConfiguration()
            webConfiguration.allowsInlineMediaPlayback = true
            webConfiguration.mediaTypesRequiringUserActionForPlayback = []
            webConfiguration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            let userAgent = call.getString("userAgent");
            if (userAgent != nil) {
                webConfiguration.applicationNameForUserAgent = "\(webConfiguration.applicationNameForUserAgent), \(userAgent)";
            }

            // Content controller
            let javascript = call.getString("javascript") ?? ""
            if (javascript != "") {
                var injectionTime: WKUserScriptInjectionTime!
                switch(call.getInt("injectionTime")){
                case 0:
                    injectionTime = .atDocumentStart
                    break;
                case 1:
                    injectionTime = .atDocumentEnd
                    break;
                default:
                    injectionTime = .atDocumentStart
                    break;
                }
                let contentController = WKUserContentController()
                let script = WKUserScript(source: String(javascript), injectionTime: injectionTime, forMainFrameOnly: true)
                contentController.addUserScript(script)
                webConfiguration.userContentController = contentController
            }

            self.webviewOverlay = WebviewOverlay(self, configuration: webConfiguration)

            guard let urlString = call.getString("url") else {
                call.reject("Must provide a URL to open")
                return
            }

            let url = URL(string: urlString)

            self.hidden = false

            self.width = CGFloat(call.getFloat("width") ?? 0)
            self.height = CGFloat(call.getFloat("height") ?? 0)
            self.x = CGFloat(call.getFloat("x") ?? 0)
            self.y = CGFloat(call.getFloat("y") ?? 0)

            self.webviewOverlay.view.isHidden = true
            self.bridge?.viewController?.addChild(self.webviewOverlay)
            self.bridge?.viewController?.view.addSubview(self.webviewOverlay.view)
            self.webviewOverlay.view.frame = CGRect(x: self.x, y: self.y, width: self.width, height: self.height)
            self.webviewOverlay.didMove(toParent: self.bridge?.viewController)

            self.webviewOverlay.loadUrl(url!)
        }
    }

    @objc func close(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if (self.webviewOverlay != nil) {
                self.webviewOverlay.view.removeFromSuperview()
                self.webviewOverlay.removeFromParent()
                self.webviewOverlay.clearWebServer()
                self.webviewOverlay = nil
                self.hidden = false
            }
        }
    }

    @objc func getSnapshot(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if (self.webviewOverlay != nil) {
                if (self.webviewOverlay.webview != nil) {
                    let offset: CGPoint = (self.webviewOverlay.webview?.scrollView.contentOffset)!
                    self.webviewOverlay.webview?.scrollView.setContentOffset(offset, animated: false)

                    self.webviewOverlay.webview?.takeSnapshot(with: nil) {image, error in
                        if let image = image {
                            guard let jpeg = image.jpegData(compressionQuality: 1) else {
                                return
                            }
                            let base64String = jpeg.base64EncodedString()
                            call.resolve(["src": base64String])
                        } else {
                            call.resolve(["src": ""])
                        }
                    }
                }
                else {
                    call.resolve(["src": ""])
                }
            }
            else {
                call.resolve(["src": ""])
            }
        }
    }

    @objc func updateDimensions(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.width = CGFloat(call.getFloat("width") ?? 0)
            self.height = CGFloat(call.getFloat("height") ?? 0)
            self.x = CGFloat(call.getFloat("x") ?? 0)
            self.y = CGFloat(call.getFloat("y") ?? 0)

            if (!self.fullscreen) {
                if let overlay = self.webviewOverlay {
                    let rect = CGRect(x: self.x, y: self.y, width: self.width, height: self.height)
                    overlay.view.frame = rect
                } else {
                    // Handle the case when webviewOverlay is nil
                    print("Warning: webviewOverlay is nil")
                    // You might want to initialize it here or take some other action
                }
            }
            else {
                let width = UIScreen.main.bounds.width
                let height = UIScreen.main.bounds.height
                let rect = CGRect(x: 0, y: 0, width: width, height: height)
                self.webviewOverlay.view.frame = rect
            }

            if let overlay = self.webviewOverlay {
                if let topSafeArea = overlay.topSafeArea,
                   let closeButton = overlay.closeFullscreenButton {
                    closeButton.frame = CGRect(
                        x: UIScreen.main.bounds.width - 60,
                        y: topSafeArea + 20,
                        width: 40,
                        height: 40
                    )
                }
            }
            
            if (self.hidden) {
                self.notifyListeners("updateSnapshot", data: [:])
            }
            call.resolve()
        }
    }

    @objc func show(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.hidden = false
            if (self.webviewOverlay != nil) {
                self.webviewOverlay.view.isHidden = false
            }
            call.resolve()
        }
    }

    @objc func hide(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.hidden = true
            if (self.webviewOverlay != nil) {
                self.webviewOverlay.view.isHidden = true
            }
            call.resolve()
        }
    }

    @objc func evaluateJavaScript(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let javascript = call.getString("javascript") else {
                call.reject("Must provide javascript string")
                return
            }
            if (self.webviewOverlay != nil) {
                if (self.webviewOverlay.webview != nil) {
                    func eval(completionHandler: @escaping (_ response: String?) -> Void) {
                        self.webviewOverlay.webview?.evaluateJavaScript(String(javascript)) { (value, error) in
                            if error != nil {
                                call.reject(error?.localizedDescription ?? "unknown error")
                            }
                            else if let valueName = value as? String {
                                completionHandler(valueName)
                            }
                        }
                    }

                    eval(completionHandler: { response in
                        call.resolve(["result": response as Any])
                    })
                }
                else {
                    call.resolve(["result": ""])
                }
            }
            else {
                call.resolve(["result": ""])
            }
        }
    }

    @objc func toggleFullscreen(_ call: CAPPluginCall? = nil) {
        DispatchQueue.main.async {
            if (self.webviewOverlay != nil) {
                if (self.fullscreen) {
                    let rect = CGRect(x: self.x, y: self.y, width: self.width, height: self.height)
                    self.webviewOverlay.view.frame = rect
                    self.fullscreen = false
                    self.webviewOverlay.closeFullscreenButton.isHidden = true
                }
                else {
                    let width = UIScreen.main.bounds.width
                    let height = UIScreen.main.bounds.height
                    let rect = CGRect(x: 0, y: 0, width: width, height: height)
                    self.webviewOverlay.view.frame = rect
                    self.fullscreen = true
                    self.webviewOverlay.closeFullscreenButton.isHidden = false
                }
                if (call != nil) {
                    call!.resolve()
                }
            }
        }
    }

    @objc func goBack(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if (self.webviewOverlay != nil) {
                self.webviewOverlay.webview?.goBack()
                call.resolve()
            }
        }
    }

    @objc func goForward(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if (self.webviewOverlay != nil) {
                self.webviewOverlay.webview?.goForward()
                call.resolve()
            }
        }
    }

    @objc func reload(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if (self.webviewOverlay != nil) {
                self.webviewOverlay.webview?.reload()
                call.resolve()
            }
        }
    }

    @objc func loadUrl(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if (self.webviewOverlay != nil) {
                let url = call.getString("url") ?? ""
                self.webviewOverlay.loadUrlCall = call
                self.webviewOverlay.loadUrl(URL(string: url)!)
            }
        }
    }

    @objc func handleNavigationEvent(_ call: CAPPluginCall) {
        if (self.webviewOverlay != nil && self.webviewOverlay.currentDecisionHandler != nil) {
            if (call.getBool("allow") ?? true) {
                self.webviewOverlay.currentDecisionHandler!(.allow)
            }
            else {
                self.webviewOverlay.currentDecisionHandler!(.cancel)
                self.notifyListeners("pageLoaded", data: [:])
            }
            self.webviewOverlay.currentDecisionHandler = nil
            call.resolve()
        }
    }
    
}
