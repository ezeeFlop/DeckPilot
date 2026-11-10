import SwiftUI
import WebKit

/// La page de réglage d'une extension : une page web de l'extension, connectée à l'hôte comme le fait Stream Deck.
struct PropertyInspectorView: NSViewRepresentable {
    let url: URL
    let folder: URL
    let port: UInt16
    let context: String
    let info: String
    let actionInfo: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.loadFileURL(url, allowingReadAccessTo: folder)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: PropertyInspectorView

        init(_ parent: PropertyInspectorView) {
            self.parent = parent
        }

        /// Une fois la page chargée, on appelle la fonction d'entrée que toute page de réglage Stream Deck définit.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let arguments = [String(parent.port), parent.context, "registerPropertyInspector", parent.info, parent.actionInfo]
            guard let data = try? JSONSerialization.data(withJSONObject: arguments),
                  let list = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("connectElgatoStreamDeckSocket.apply(null, \(list));")
        }
    }
}
