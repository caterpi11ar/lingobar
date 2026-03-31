import AppKit
import WebKit

@MainActor
enum MenuBarIconLoader {
    private static var activeRenderers: [SVGSnapshotRenderer] = []
    private static let statusItemSize = NSSize(width: 16, height: 16)

    static func load(completion: @escaping (NSImage?) -> Void) {
        load(targetSize: statusItemSize, completion: completion)
    }

    static func load(targetSize: NSSize, completion: @escaping (NSImage?) -> Void) {
        guard let url = iconURL else {
            completion(nil)
            return
        }

        if let directImage = NSImage(contentsOf: url) {
            completion(resizedImage(from: directImage, targetSize: targetSize))
            return
        }

        guard let svgSource = try? String(contentsOf: url, encoding: .utf8) else {
            completion(nil)
            return
        }

        let renderer = SVGSnapshotRenderer(svgSource: svgSource, targetSize: targetSize) { image in
            completion(image)
        }
        activeRenderers.append(renderer)
        renderer.start()
    }

    fileprivate static func release(_ renderer: SVGSnapshotRenderer) {
        activeRenderers.removeAll { $0 === renderer }
    }

    private static var iconURL: URL? {
        if let bundled = Bundle.main.url(forResource: "LingobarMenuIcon", withExtension: "svg") {
            return bundled
        }

        // XcodeGen is not consistently copying loose SVG files into the app bundle
        // during local debug builds. Fall back to the workspace asset so the status
        // item still renders the requested icon while we keep development moving.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("LingobarMenuIcon.svg")
    }

    private static func resizedImage(from image: NSImage, targetSize: NSSize) -> NSImage? {
        let output = NSImage(size: targetSize)
        output.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        output.size = targetSize
        return output
    }
}

@MainActor
private final class SVGSnapshotRenderer: NSObject, WKNavigationDelegate {
    private let svgSource: String
    private let targetSize: NSSize
    private let completion: (NSImage?) -> Void
    private var webView: WKWebView?

    init(svgSource: String, targetSize: NSSize, completion: @escaping (NSImage?) -> Void) {
        self.svgSource = svgSource
        self.targetSize = targetSize
        self.completion = completion
        super.init()
    }

    func start() {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: NSRect(origin: .zero, size: targetSize),
            configuration: configuration
        )
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        self.webView = webView
        webView.loadHTMLString(htmlDocument, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let snapshotConfiguration = WKSnapshotConfiguration()
        snapshotConfiguration.rect = NSRect(origin: .zero, size: targetSize)
        webView.takeSnapshot(with: snapshotConfiguration) { [weak self] image, _ in
            guard let self else { return }
            self.finish(image)
        }
    }

    private var htmlDocument: String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <style>
        html, body {
          margin: 0;
          padding: 0;
          width: \(Int(targetSize.width))px;
          height: \(Int(targetSize.height))px;
          overflow: hidden;
          background: transparent;
        }
        svg {
          width: 100%;
          height: 100%;
          display: block;
        }
        </style>
        </head>
        <body>\(svgSource)</body>
        </html>
        """
    }

    private func finish(_ image: NSImage?) {
        webView?.navigationDelegate = nil
        webView = nil
        completion(image)
        MenuBarIconLoader.release(self)
    }
}
