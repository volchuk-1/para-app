import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// «Поділитися → DaVincit» from TikTok, YouTube, Safari, shops.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0xF9 / 255, green: 0xF6 / 255, blue: 0xEE / 255, alpha: 1)
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { @MainActor in
            let safari = await ShareExtractor.safariPage(from: items)
            let url: URL?
            if let safari { url = safari.url } else { url = await ShareExtractor.url(from: items) }
            let root: AnyView
            if let url {
                root = AnyView(ShareFlowView(url: url, page: safari?.page) { [weak self] in self?.done() })
            } else {
                root = AnyView(
                    VStack(spacing: 16) {
                        Text("Не бачу посилання в тому, чим поділились.").font(.system(size: 17, weight: .medium))
                        Button("Закрити") { [weak self] in self?.done() }
                    }
                    .padding()
                )
            }
            let host = UIHostingController(rootView: root)
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

enum ShareExtractor {
    /// Safari runs Share/Preprocess.js on the open page and hands back its results as a property list.
    static func safariPage(from items: [NSExtensionItem]) async -> (url: URL, page: String?)? {
        for item in items {
            for p in item.attachments ?? [] where p.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                guard let dict = try? await p.loadItem(forTypeIdentifier: UTType.propertyList.identifier) as? [String: Any] else { continue }
                if let r = ShareRouting.fromSafari(dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]) { return r }
            }
        }
        return nil
    }

    /// A web URL attachment, or the first link inside shared text (TikTok shares text + link).
    static func url(from items: [NSExtensionItem]) async -> URL? {
        for item in items {
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    return u
                }
                if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let t = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let u = ShareRouting.firstURL(in: t) {
                    return u
                }
            }
            if let t = item.attributedContentText?.string, let u = ShareRouting.firstURL(in: t) { return u }
        }
        return nil
    }
}
