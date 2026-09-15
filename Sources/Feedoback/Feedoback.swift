import Foundation

#if canImport(UIKit)
import UIKit

/// The whole SDK, from an app's point of view.
///
/// Four calls: `start` once at launch, `present` from a control the app
/// already owns, `identify` when the app knows who this is, and `reset` on
/// sign-out. Everything else is the owner's, and arrives from the server.
///
/// Every entry point is total. A bad key, no network, a project that has not
/// opened its mobile channel — none of it throws into someone's
/// `didFinishLaunching`. It logs once and goes quiet, which is the native
/// reading of a misconfigured widget removing itself.
@MainActor
public final class Feedoback {
    public static let shared = Feedoback()
    public static let version = "0.1.0"

    private var configuration: FeedobackConfiguration?
    private var transport: FeedobackTransport?
    private var store: FeedobackStore?
    private var session: FeedobackSession?
    private var log = FeedobackLog(level: .warning)

    /// What the server last said. Nothing is drawn until this arrives enabled.
    private var config: FeedobackConfigResponse?
    private var launcherWindow: FeedobackLauncherWindow?
    private var sheetIsUp = false
    private var observers: [NSObjectProtocol] = []


    /// Where the visitor is, as the app says. Set it when a screen appears.
    private var route = "/"
    private var screenTitle = ""

    /// What the app attaches to every thread from now on. Bounded on the way
    /// in rather than on the way out, so an app that sets it once does not pay
    /// for the check on every send.
    private var context: [String: FeedobackValue] = [:]

    private init() {}

    // MARK: - Starting

    /// Call once, at launch. Calling it twice does not stack two launchers,
    /// the way a snippet pasted twice must not stack two on a page.
    public func start(_ configuration: FeedobackConfiguration) {
        guard self.configuration == nil else {
            log.debug("already started; ignoring the second call")
            return
        }
        guard configuration.projectKey.hasPrefix("pk_") else {
            log.error("that does not look like a project key; Feedoback is off")
            return
        }

        self.configuration = configuration
        self.log = FeedobackLog(level: configuration.logLevel)

        let store = FeedobackStore()
        self.store = store

        Task { @MainActor in
            let identity = FeedobackClientIdentity(
                bundleId: FeedobackDevice.bundleId,
                installId: await store.installId(),
                sdkVersion: Self.version)

            let transport = FeedobackTransport(
                host: configuration.host,
                projectKey: configuration.projectKey,
                identity: identity,
                session: .shared)
            self.transport = transport

            let log = self.log
            self.session = FeedobackSession(
                transport: transport,
                store: store,
                context: { await FeedobackDevice.screenContext(route: self.route, title: self.screenTitle) },
                metadata: { await self.context },
                log: log)

            self.watchLifecycle()
            await self.refreshConfig()
            await self.session?.flushQueue()
        }
    }

    /// Asks whether this client may run at all, and how the owner wants it to
    /// look. A refusal is not an error: the launcher simply does not appear.
    private func refreshConfig() async {
        guard let transport, let store else { return }
        let visitor = await store.visitor()

        knowsTheVisitor = !(visitor?.email?.isEmpty ?? true)

        do {
            let answer = try await transport.config(for: visitor)
            config = answer
            if answer.enabled {
                showLauncherIfAsked()
            } else {
                hideLauncher()
                if let reason = answer.reason { log.warning(reason.advice) }
            }
        } catch FeedobackTransportError.unknownProject {
            log.error("that project key is not one this server knows; Feedoback is off")
        } catch {
            // No network at launch is ordinary. Try again on the next
            // foreground rather than saying anything alarming.
            log.debug("could not reach the server yet")
        }
    }

    // MARK: - Who this is

    /// Who the app says the visitor is.
    ///
    /// Declared, never authoritative — it is the app's own word. Pass
    /// `userHash` when the project asks for signatures and your server has
    /// computed one; that is the only part of it the server can check.
    ///
    /// Calling this after launch asks the server again, so someone who signs
    /// in a minute later gets the launcher a project only offers to named
    /// people.
    public func identify(_ visitor: FeedobackVisitor) {
        guard let store else {
            log.warning("identify() before start(); it was ignored")
            return
        }
        Task { @MainActor in
            await store.setVisitor(visitor)
            await refreshConfig()
        }
    }

    /// What an app calls on sign-out. Forgets the person and anything the app
    /// attached about them; keeps the device. Threads already queued keep the
    /// identity and context they were written with — the visitor did ask to
    /// send those.
    public func reset() {
        guard let store else { return }
        context = [:]
        Task { @MainActor in
            await store.reset()
            await refreshConfig()
        }
    }

    // MARK: - Where they are

    /// Names the screen the visitor is on, which is what feedback is filed
    /// under. A path reads best — "checkout/payment" — because the dashboard
    /// folds identifiers out of it the way it does a website's.
    public func setScreen(_ route: String, title: String = "") {
        self.route = route
        self.screenTitle = title
    }

    /// Attaches custom context to every thread opened from now on: the plan
    /// someone is on, the flag they have, the tier they bought. The same call
    /// as the web SDK's, and the same limits — at most thirty keys, and what
    /// exceeds them is dropped rather than costing the visitor their feedback.
    ///
    /// It is not persisted. An app sets this from state it already holds, and
    /// carrying a stale plan across a launch would be worse than carrying
    /// none.
    public func setContext(_ context: [String: FeedobackValue]) {
        self.context = FeedobackCustomContext.bounded(context)
    }

    // MARK: - Opening the sheet

    /// Opens the sheet from a control the app already owns: a Settings row, a
    /// menu item. Does nothing, loudly in a debug build, when the project has
    /// not allowed this client.
    public func present(category: FeedobackCategory = .feedback) {
        guard let configuration, let session else {
            log.warning("present() before start(); nothing to show")
            return
        }
        guard let config, config.enabled else {
            log.warning(config?.reason?.advice ?? "this client may not send feedback yet")
            return
        }
        guard !sheetIsUp else { return }
        guard let presenter = topViewController() else {
            log.warning("no view controller to present from")
            return
        }

        // Taken before the sheet is up, so the picture is the screen the
        // visitor is complaining about rather than the sheet covering it.
        let screenshot = configuration.screenshots == .automatic
            ? FeedobackScreenshot.capture(keyWindow(), hiding: launcherButtons())
            : nil

        let sheet = FeedbackSheetController(
            appearance: config.appearance,
            categories: configuration.categories,
            category: category,
            knowsTheVisitor: knowsTheVisitor,
            theme: configuration.theme,
            screenshot: screenshot,
            onSend: { draft in await session.send(draft) },
            onClose: { [weak self] in
                self?.sheetIsUp = false
                self?.launcherWindow?.setButtonHidden(false)
            })

        let navigation = UINavigationController(rootViewController: sheet)
        navigation.overrideUserInterfaceStyle = configuration.theme.interfaceStyle
        if let presentation = navigation.sheetPresentationController {
            presentation.prefersGrabberVisible = true
            if #available(iOS 16.0, *) {
                // Stop at the height of the form. A sheet that fills the
                // screen for four controls reads as a screen that failed to
                // fill, not as a sheet.
                presentation.detents = [
                    .custom { [weak sheet, weak navigation] context in
                        guard let sheet, let navigation else { return context.maximumDetentValue }
                        let bar = navigation.navigationBar.frame.height
                        return min(sheet.contentHeight + bar, context.maximumDetentValue)
                    },
                    .large(),
                ]
            } else {
                // Custom detents arrived in iOS 16. Half the screen is the
                // closest thing before that, and it drags up the same way.
                presentation.detents = [.medium(), .large()]
            }
        }
        sheetIsUp = true
        launcherWindow?.setButtonHidden(true)
        presenter.present(navigation, animated: true)
    }

    /// Whether the app already gave an address, which is the only thing the
    /// sheet needs to know: with one it does not ask, without one a visitor
    /// who wants an answer has to be able to leave it.
    ///
    /// Kept here rather than read at present time because the store is an
    /// actor and a sheet cannot wait; it is refreshed wherever it can change.
    private var knowsTheVisitor = false

    // MARK: - The launcher

    private func showLauncherIfAsked() {
        guard let configuration, configuration.launcher.enabled, let config else { return }
        guard launcherWindow == nil else { return }
        guard let scene = activeScene() else { return }

        launcherWindow = FeedobackLauncherWindow(
            scene: scene,
            options: configuration.launcher,
            appearance: config.appearance,
            theme: configuration.theme,
            onTap: { [weak self] in self?.present() })
    }

    private func hideLauncher() {
        launcherWindow?.isHidden = true
        launcherWindow = nil
    }

    /// Marks a view whose contents must never leave the device.
    ///
    /// Secure text fields need no marking — they are found on their own,
    /// because forgetting one of those is the expensive mistake. This is for
    /// everything else: a card number, an address, a medical record.
    public func redact(_ view: UIView) {
        FeedobackScreenshot.redact(view)
    }

    /// Undoes it, for a view that is only sometimes sensitive.
    public func unredact(_ view: UIView) {
        FeedobackScreenshot.unredact(view)
    }

    /// Marks regions of the screen rather than views, for an interface that
    /// has no view to hand over: a canvas, a game, or Flutter, which draws
    /// everything it has into one.
    ///
    /// In the key window's coordinates, and replacing whatever was marked
    /// before — the caller is the only thing that knows where all of them are.
    public func setRedactedRegions(_ regions: [CGRect]) {
        FeedobackScreenshot.setRedactedRegions(regions)
    }

    /// Takes the launcher out of the way for a screen that wants none: a video
    /// player, a camera.
    public func setLauncherHidden(_ hidden: Bool) {
        launcherWindow?.setButtonHidden(hidden)
    }

    // MARK: - Lifecycle

    private func watchLifecycle() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    // Anything written in a tunnel goes out now.
                    await self?.session?.flushQueue()
                }
            })
    }

    /// Shaking, and the visitor taking a screenshot themselves — which on iOS
    /// is what people already do when something looks wrong.
    public func handleShake() {
        guard configuration?.triggers.contains(.shake) == true else { return }
        present()
    }

    // MARK: - Finding the screen

    private func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func keyWindow() -> UIWindow? {
        activeScene()?.windows.first { $0.isKeyWindow && $0 !== launcherWindow }
            ?? activeScene()?.windows.first { $0 !== launcherWindow }
    }

    /// The launcher's own button is left out of the picture: a screenshot of
    /// the app should not include the thing used to complain about it.
    private func launcherButtons() -> [UIView] {
        guard let root = launcherWindow?.rootViewController?.view else { return [] }
        return root.subviews
    }

    private func topViewController() -> UIViewController? {
        var top = keyWindow()?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}


#endif
