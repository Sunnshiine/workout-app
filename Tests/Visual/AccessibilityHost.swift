import SwiftUI
import Testing
import UIKit

/// Shows a view in a window of the test host and reads it as an accessibility client, so a test
/// sees the frames VoiceOver and the UI tests see.
@MainActor
enum AccessibilityHost {
    static func read<Content: View, Result>(
        _ content: Content,
        in size: CGSize,
        _ body: (UIWindow) throws -> Result
    ) throws -> Result {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return try asAccessibilityClient {
            let controller = UIHostingController(rootView: content)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            #expect(!controller.view.layer.needsLayout(), "the view settles in one layout")
            return try body(window)
        }
    }

    /// SwiftUI builds its accessibility tree only for an accessibility client. This makes the test
    /// process one for the length of `body`, as XCUITest does for the app it drives, then puts the
    /// simulator-wide flag back.
    private static func asAccessibilityClient<Result>(_ body: () throws -> Result) throws -> Result {
        let library = try #require(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        let isEnabled = unsafeBitCast(
            try #require(dlsym(library, "_AXSAutomationEnabled")),
            to: (@convention(c) () -> Bool).self
        )
        let setEnabled = unsafeBitCast(
            try #require(dlsym(library, "_AXSSetAutomationEnabled")),
            to: (@convention(c) (Bool) -> Void).self
        )
        let wasEnabled = isEnabled()
        setEnabled(true)
        defer { setEnabled(wasEnabled) }
        return try body()
    }
}

extension NSObject {
    /// The frames VoiceOver and the UI tests read for every element that `matches`, in tree order.
    /// An element reached both as a child element and as a subview counts once.
    func accessibilityFrames(where matches: (NSObject) -> Bool) -> [CGRect] {
        var visited: Set<ObjectIdentifier> = []
        var frames: [CGRect] = []
        func visit(_ object: NSObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            if matches(object) {
                frames.append(object.accessibilityFrame)
            }
            object.accessibilityChildren.forEach(visit)
        }
        visit(self)
        return frames
    }

    /// The element's accessibility identifier. UIKit declares that property only on
    /// `UIAccessibilityIdentification` conformers, so this reads it from any element that answers it.
    var elementIdentifier: String? {
        let isIdentifiable = responds(to: #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier))
        return isIdentifiable ? value(forKey: "accessibilityIdentifier") as? String : nil
    }

    private var accessibilityChildren: [NSObject] {
        let elements = accessibilityElements?.compactMap { $0 as? NSObject } ?? []
        let subviews = (self as? UIView)?.subviews ?? []
        return elements + subviews
    }
}
