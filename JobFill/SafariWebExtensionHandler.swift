import SafariServices

// The extension's JavaScript can't keep the worker key in its own files (they're in git), so the
// background script asks this native side for it. Only the extension can send these messages.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        var reply: [String: Any] = ["error": "unknown request"]
        if message?["type"] as? String == "appKey" {
            reply = ["key": Secrets.appKey]
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
