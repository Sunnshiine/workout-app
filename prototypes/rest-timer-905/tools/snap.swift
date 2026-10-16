import AppKit
import WebKit

// usage: snap <url> <width> <height> <out.png> [jsBeforeShot] [delayMs]
let a = CommandLine.arguments
let url = URL(string: a[1])!, w = Double(a[2])!, h = Double(a[3])!, out = a[4]
let js = a.count > 5 ? a[5] : ""
let delay = a.count > 6 ? Double(a[6])! / 1000 : 0
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h))
win.contentView = web
win.orderFrontRegardless()

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            webView.evaluateJavaScript(js.isEmpty ? "0" : js) { _, err in
                if let err { FileHandle.standardError.write("js: \(err)\n".data(using: .utf8)!) }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.05) {
                    let cfg = WKSnapshotConfiguration()
                    cfg.snapshotWidth = NSNumber(value: w * 3)
                    webView.takeSnapshot(with: cfg) { img, err in
                        guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                              let png = rep.representation(using: .png, properties: [:]) else {
                            print("snapshot failed: \(String(describing: err))"); exit(1)
                        }
                        try! png.write(to: URL(fileURLWithPath: out))
                        webView.evaluateJavaScript("document.getElementById('readout').innerText") { v, _ in
                            print(v as? String ?? "")
                            exit(0)
                        }
                    }
                }
            }
        }
    }
}
let nav = Nav()
web.navigationDelegate = nav
web.load(URLRequest(url: url))
app.run()
