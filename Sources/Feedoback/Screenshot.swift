import Foundation

#if canImport(UIKit)
import UIKit

/// A picture of the screen the visitor is complaining about.
///
/// The strongest guarantee here costs nothing: the visitor always sees the
/// picture before it goes, and can take it off. Nothing is sent that the
/// person looking at it did not look at first.
@MainActor
public enum FeedobackScreenshot {
    /// Quality that keeps text legible without sending a photograph's worth of
    /// bytes over someone's cellular data.
    public static let compression: CGFloat = 0.8
    public static let contentType = "image/jpeg"

    /// Views the host app marked as not for us.
    private static var redacted = NSHashTable<UIView>.weakObjects()

    /// Regions the host app marked, in the window's own coordinates.
    ///
    /// A view is the right thing to mark when there is one. Flutter draws its
    /// entire interface into a single view, so there is no view to hand over
    /// and a rectangle is the only thing that can be said; its SDK keeps these
    /// in step with where its widgets are. The same applies to anything else
    /// drawn rather than laid out — a canvas, a game, a chart.
    private static var regions: [CGRect] = []

    /// What is marked, for a test to read. Nothing else needs it: the capture
    /// is the only caller, and it is in this file.
    static var redactedRegions: [CGRect] { regions }

    /// Marks a view whose contents must never leave the device.
    ///
    /// Held weakly, so marking a cell in a list that is later recycled does not
    /// keep it alive. Secure text fields need no marking: they are found on
    /// their own, because forgetting one of those is the expensive mistake.
    public static func redact(_ view: UIView) {
        redacted.add(view)
    }

    public static func unredact(_ view: UIView) {
        redacted.remove(view)
    }

    /// Replaces the marked regions rather than adding to them: the caller
    /// knows where all of them are, and a set that could only grow would keep
    /// painting over a place nothing sensitive has been for ten screens.
    public static func setRedactedRegions(_ regions: [CGRect]) {
        self.regions = regions.filter { $0.width > 0 && $0.height > 0 }
    }

    /// Captures the window the visitor is looking at, with anything sensitive
    /// painted over before the bitmap exists — never captured and then masked,
    /// which would put the real pixels in memory on the way.
    public static func capture(_ window: UIWindow?, hiding: [UIView] = []) -> Data? {
        guard let window, window.bounds.width > 0, window.bounds.height > 0 else { return nil }

        let hidden = hiding.filter { !$0.isHidden }
        hidden.forEach { $0.isHidden = true }
        defer { hidden.forEach { $0.isHidden = false } }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)

            context.cgContext.setFillColor(UIColor.systemGray3.cgColor)
            for view in sensitiveViews(in: window) {
                let frame = view.convert(view.bounds, to: window)
                guard frame.width > 0, frame.height > 0 else { continue }
                context.cgContext.fill(frame)
            }
            for region in regions {
                context.cgContext.fill(region)
            }
        }

        return image.jpegData(compressionQuality: compression)
    }

    /// Anything the host app marked, plus every secure text field, which is the
    /// one nobody should have to remember.
    static func sensitiveViews(in root: UIView) -> [UIView] {
        var found: [UIView] = []

        func walk(_ view: UIView) {
            if view.isHidden || view.alpha < 0.01 { return }
            if redacted.contains(view) || isSecure(view) {
                found.append(view)
                // No need to walk into something already painted over.
                return
            }
            view.subviews.forEach(walk)
        }

        walk(root)
        return found
    }

    private static func isSecure(_ view: UIView) -> Bool {
        if let field = view as? UITextField, field.isSecureTextEntry { return true }
        if let text = view as? UITextView, text.isSecureTextEntry { return true }
        return false
    }
}
#endif
