import Foundation

#if canImport(UIKit)
import UIKit

/// A window, not a view in somebody's hierarchy.
///
/// That is the whole point: it survives every navigation, sits above presented
/// controllers, and does not have to be added to each screen. It is also why
/// hit-testing matters — a window that swallowed touches would break the app
/// it floats over, so everything outside the button falls straight through.
///
/// Deliberately not `TYPE_APPLICATION_OVERLAY`'s iOS cousin: nothing here asks
/// the host app for a permission, and nothing draws over other apps.
@MainActor
final class FeedobackLauncherWindow: UIWindow {
    private let button = UIButton(type: .system)
    private let options: FeedobackLauncherOptions
    private let onTap: () -> Void
    private var dragOrigin: CGPoint = .zero

    init(
        scene: UIWindowScene,
        options: FeedobackLauncherOptions,
        appearance: FeedobackAppearance,
        theme: FeedobackTheme,
        onTap: @escaping () -> Void
    ) {
        self.options = options
        self.onTap = onTap
        super.init(windowScene: scene)

        // Above the app, below an alert: a launcher must never cover a system
        // prompt the visitor has to answer.
        windowLevel = .alert - 1
        backgroundColor = .clear
        isHidden = false
        overrideUserInterfaceStyle = theme.interfaceStyle

        // A window needs a root, and an empty one keeps the launcher the only
        // thing that can be touched.
        let root = UIViewController()
        root.view.backgroundColor = .clear
        rootViewController = root

        build(appearance: appearance, in: root.view)
        if options.hidesWithKeyboard { watchTheKeyboard() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    private func build(appearance: FeedobackAppearance, in container: UIView) {
        let accent = FeedobackPalette.accent(appearance.color)

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = accent
        configuration.baseForegroundColor = FeedobackPalette.onAccent(accent)
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: "bubble.left.and.text.bubble.right")
        if options.style == .labelled {
            configuration.title = appearance.label.isEmpty ? "Feedback" : appearance.label
            configuration.imagePadding = 8
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 14, leading: 18, bottom: 14, trailing: 18)
        } else {
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 16, leading: 16, bottom: 16, trailing: 16)
        }

        button.configuration = configuration
        button.translatesAutoresizingMaskIntoConstraints = false
        // The word is the accessible name whether or not it is drawn, so what
        // a voice-control user says matches what an owner chose.
        button.accessibilityLabel = appearance.label.isEmpty ? "Feedback" : appearance.label
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowRadius = 8
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        container.addSubview(button)

        let guide = container.safeAreaLayoutGuide
        let x = options.offset.width
        let y = options.offset.height

        // From the safe area, never the raw edge: a launcher under the home
        // indicator is one nobody can press.
        switch options.corner {
        case .topLeading:
            button.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: x).isActive = true
            button.topAnchor.constraint(equalTo: guide.topAnchor, constant: y).isActive = true
        case .topTrailing:
            button.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -x).isActive = true
            button.topAnchor.constraint(equalTo: guide.topAnchor, constant: y).isActive = true
        case .bottomLeading:
            button.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: x).isActive = true
            button.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -y).isActive = true
        case .bottomTrailing:
            button.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -x).isActive = true
            button.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -y).isActive = true
        }

        if options.draggable {
            button.addGestureRecognizer(
                UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        }
    }

    /// Everything but the button falls through to the app underneath. Without
    /// this the window would eat every touch on the screen.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === button || hit?.isDescendant(of: button) == true ? hit : nil
    }

    @objc private func tapped() { onTap() }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let container = rootViewController?.view else { return }
        switch gesture.state {
        case .began:
            dragOrigin = button.center
        case .changed:
            let move = gesture.translation(in: container)
            button.center = CGPoint(x: dragOrigin.x + move.x, y: dragOrigin.y + move.y)
        case .ended, .cancelled:
            snapToNearestEdge(in: container)
        default:
            break
        }
    }

    /// Released mid-screen, it goes back to an edge: a button floating in the
    /// middle of someone's app is in the way of it.
    private func snapToNearestEdge(in container: UIView) {
        let insets = container.safeAreaInsets
        let half = button.bounds.width / 2
        let left = insets.left + half + options.offset.width
        let right = container.bounds.width - insets.right - half - options.offset.width
        let target = button.center.x < container.bounds.midX ? left : right

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.button.center = CGPoint(x: target, y: self.button.center.y)
        }
    }

    private func watchTheKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(keyboardUp), name: UIResponder.keyboardWillShowNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(keyboardDown), name: UIResponder.keyboardWillHideNotification,
            object: nil)
    }

    @objc private func keyboardUp() { keyboardIsUp = true; applyVisibility() }
    @objc private func keyboardDown() { keyboardIsUp = false; applyVisibility() }

    /// Two things hide the button and they must not fight: the sheet being up
    /// outlasts a keyboard that closes underneath it, so each is remembered
    /// and the button is shown only when neither applies.
    private var keyboardIsUp = false
    private var hiddenByHost = false

    func setButtonHidden(_ hidden: Bool) {
        hiddenByHost = hidden
        applyVisibility()
    }

    private func applyVisibility() {
        let hidden = hiddenByHost || keyboardIsUp
        UIView.animate(withDuration: 0.15) {
            self.button.alpha = hidden ? 0 : 1
        }
        button.isUserInteractionEnabled = !hidden
        button.isAccessibilityElement = !hidden
    }
}
#endif
