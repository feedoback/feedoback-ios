import Foundation

/// What the host app hands `Feedoback.start`.
///
/// Everything the owner controls — the accent, the word on the launcher,
/// whether stars are asked for — comes from the server, so it can change
/// without an app release. Everything only the app can know is here.
public struct FeedobackConfiguration: Sendable {
    /// The project's public key, `pk_…`. Readable by anyone who unzips the
    /// app: it identifies a project and grants nothing.
    public var projectKey: String

    /// Where the app is deployed. Defaults to the hosted service.
    public var host: URL

    /// Light and dark. The sheet is native UI inside someone else's app, so
    /// this is the app's decision — the server is never asked and never tells.
    public var theme: FeedobackTheme

    /// Which categories the sheet offers. With one it shows no picker, because
    /// a control with a single option is not a choice.
    public var categories: [FeedobackCategory]

    /// Whether a picture of the screen rides along. The app knows which of its
    /// screens are sensitive; a dashboard does not, which is why this is here.
    public var screenshots: FeedobackScreenshots

    /// The floating button, off unless asked for: most apps have a place for
    /// this already, and one that did not ask should not get a button over its
    /// own interface.
    public var launcher: FeedobackLauncherOptions

    /// What opens the sheet besides a control the app owns.
    public var triggers: Set<FeedobackTrigger>

    /// How loud the SDK is in the console. Never anything in a release build
    /// unless asked: this runs inside somebody else's product.
    public var logLevel: FeedobackLogLevel

    public init(
        projectKey: String,
        host: URL = FeedobackConfiguration.defaultHost,
        theme: FeedobackTheme = .system,
        categories: [FeedobackCategory] = [.feedback],
        screenshots: FeedobackScreenshots = .automatic,
        launcher: FeedobackLauncherOptions = .init(),
        triggers: Set<FeedobackTrigger> = [],
        logLevel: FeedobackLogLevel = .warning
    ) {
        self.projectKey = projectKey
        self.host = host
        self.theme = theme
        self.categories = categories.isEmpty ? [.feedback] : categories
        self.screenshots = screenshots
        self.launcher = launcher
        self.triggers = triggers
        self.logLevel = logLevel
    }

    public static let defaultHost = URL(string: "https://feedoback.com")!

    /// A configuration out of the loosely-typed dictionary a bridge hands over.
    ///
    /// React Native and Flutter both arrive with one of these, and doing the
    /// mapping in each of them would be doing it twice — and then finding out,
    /// two releases later, that only one of them learned about a new option.
    /// It lives here because this is where the enums are.
    ///
    /// Nothing here invents a default. A key that is absent or unrecognised
    /// leaves the SDK's own default in place, which is the one a plain Swift
    /// app gets. Nil when there is no project key at all, which is the one
    /// thing there is no falling back from.
    public init?(options: [String: Any]) {
        guard let projectKey = options.text("projectKey") else { return nil }
        let defaults = FeedobackConfiguration(projectKey: projectKey)

        let launcher = (options["launcher"] as? [String: Any])
            .map { FeedobackLauncherOptions(options: $0) } ?? defaults.launcher

        self.init(
            projectKey: projectKey,
            host: options.text("host").flatMap(URL.init(string:)) ?? defaults.host,
            theme: FeedobackTheme(name: options["theme"]) ?? defaults.theme,
            categories: FeedobackConfiguration.categories(options["categories"])
                ?? defaults.categories,
            screenshots: FeedobackScreenshots(name: options["screenshots"])
                ?? defaults.screenshots,
            launcher: launcher,
            logLevel: FeedobackLogLevel(name: options["logLevel"]) ?? defaults.logLevel)
    }

    private static func categories(_ value: Any?) -> [FeedobackCategory]? {
        guard let names = value as? [Any] else { return nil }
        var kept: [FeedobackCategory] = []
        for name in names {
            guard let chosen = (name as? String).flatMap(FeedobackCategory.init(rawValue:)),
                  !kept.contains(chosen)
            else { continue }
            kept.append(chosen)
        }
        return kept.isEmpty ? nil : kept
    }
}

extension FeedobackLauncherOptions {
    /// Read from what a bridge sent, with the SDK's own defaults behind every
    /// key it did not carry.
    init(options: [String: Any]) {
        let defaults = FeedobackLauncherOptions()
        let offset = options["offset"] as? [String: Any]
        let x = (offset?["x"] as? NSNumber)?.doubleValue
        let y = (offset?["y"] as? NSNumber)?.doubleValue

        self.init(
            enabled: options["enabled"] as? Bool ?? defaults.enabled,
            corner: FeedobackLauncherCorner(name: options["corner"]) ?? defaults.corner,
            // Both numbers or neither: an offset with one axis missing would
            // put the button somewhere nobody asked for on the other.
            offset: x != nil && y != nil ? CGSize(width: x!, height: y!) : defaults.offset,
            style: FeedobackLauncherStyle(name: options["style"]) ?? defaults.style,
            draggable: options["draggable"] as? Bool ?? defaults.draggable,
            hidesWithKeyboard: options["hidesWithKeyboard"] as? Bool ?? defaults.hidesWithKeyboard)
    }
}

private extension RawRepresentable where RawValue == String {
    /// The case a bridge named, or nothing so the caller falls back.
    init?(name: Any?) {
        guard let name = name as? String, let value = Self(rawValue: name) else { return nil }
        self = value
    }
}

private extension FeedobackLogLevel {
    /// Spelled out rather than read from a raw value: this one's raw values are
    /// the numbers that make it Comparable, and a type gets only one set.
    init?(name: Any?) {
        switch name as? String {
        case "silent": self = .silent
        case "error": self = .error
        case "warning": self = .warning
        case "debug": self = .debug
        default: return nil
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    /// A non-empty string, or nothing so the caller falls back.
    func text(_ key: String) -> String? {
        guard let value = self[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Follows the device unless the app forces its own appearance.
///
/// The raw values are the names the bridges send, which is also what makes a
/// configuration readable out of the map one hands over.
public enum FeedobackTheme: String, Sendable {
    case system
    case light
    case dark
}

public enum FeedobackScreenshots: String, Sendable {
    /// Captured when the sheet opens. The visitor always sees it first.
    case automatic
    /// Only when the visitor asks for one.
    case manual
    /// Never.
    case off
}

public enum FeedobackTrigger: Sendable, Hashable {
    /// The floating button, when it is on.
    case launcher
    /// Shaking the device. Off by default; loved by testers, surprising to
    /// everyone else.
    case shake
    /// The visitor taking a screenshot themselves, which on iOS is what people
    /// already do when something looks wrong.
    case screenshot
}

/// Start and end rather than left and right: the launcher sits on the reading
/// edge, and an Arabic app puts that on the other side. UIKit's leading and
/// trailing already mean exactly that, so only the names a bridge uses differ.
public enum FeedobackLauncherCorner: String, Sendable {
    case topLeading = "top-start"
    case topTrailing = "top-end"
    case bottomLeading = "bottom-start"
    case bottomTrailing = "bottom-end"
}

public enum FeedobackLauncherStyle: String, Sendable {
    /// "icon" to a bridge, which reads better in an app's configuration than
    /// the Swift case name does.
    case iconOnly = "icon"
    case labelled
}

public struct FeedobackLauncherOptions: Sendable {
    public var enabled: Bool
    public var corner: FeedobackLauncherCorner
    /// From the safe area, never the raw edge.
    public var offset: CGSize
    public var style: FeedobackLauncherStyle
    /// Dragging snaps it to the nearest edge on release.
    public var draggable: Bool
    /// Out of the way while somebody is typing.
    public var hidesWithKeyboard: Bool

    public init(
        enabled: Bool = false,
        corner: FeedobackLauncherCorner = .bottomTrailing,
        offset: CGSize = CGSize(width: 16, height: 24),
        style: FeedobackLauncherStyle = .iconOnly,
        draggable: Bool = true,
        hidesWithKeyboard: Bool = true
    ) {
        self.enabled = enabled
        self.corner = corner
        self.offset = offset
        self.style = style
        self.draggable = draggable
        self.hidesWithKeyboard = hidesWithKeyboard
    }
}

public enum FeedobackLogLevel: Int, Sendable, Comparable {
    case silent = 0
    case error = 1
    case warning = 2
    case debug = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

#if canImport(CoreGraphics)
import CoreGraphics
#else
/// Foundation on Linux has no CGSize; the SDK only ever runs on Apple
/// platforms, but the non-UI layers are tested wherever `swift test` runs.
public struct CGSize: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
#endif
