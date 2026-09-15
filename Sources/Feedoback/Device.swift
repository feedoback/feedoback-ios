import Foundation

#if canImport(UIKit)
import UIKit

/// What the SDK can read about where the visitor is, and nothing more.
///
/// Every value here is either something the app declares about itself or
/// something the OS will tell any app. No advertising id, no vendor id, no
/// fingerprint: the only identifier this SDK mints is the random install id
/// in the store, which dies with the app.
@MainActor
public enum FeedobackDevice {
    /// The bundle id, read from the OS rather than typed into a config, so a
    /// developer cannot get it wrong and wonder why nothing arrives.
    public static var bundleId: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    public static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// "iPhone17,1" rather than "iPhone 16 Pro": the marketing name needs a
    /// lookup table that goes stale with every autumn, and the identifier is
    /// what a bug report is actually searched by.
    public static var model: String {
        // A simulator reports the Mac's architecture, which tells a developer
        // nothing. The device being simulated is the answer they wanted.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulated.isEmpty {
            return simulated
        }

        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let identifier = mirror.children.reduce(into: "") { name, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            name.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    public static var osVersion: String {
        UIDevice.current.systemVersion
    }

    public static var locale: String {
        Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    public static var timezone: String {
        TimeZone.current.identifier
    }

    /// Points, not pixels: the same units a developer lays out in.
    public static func viewport(in scene: UIWindowScene?) -> FeedobackViewport {
        let size = scene?.screen.bounds.size ?? UIScreen.main.bounds.size
        return FeedobackViewport(width: Int(size.width), height: Int(size.height))
    }

    public static func scale(in scene: UIWindowScene?) -> Double {
        Double(scene?.screen.scale ?? UIScreen.main.scale)
    }

    public static func orientation(in scene: UIWindowScene?) -> FeedobackOrientation {
        let size = scene?.screen.bounds.size ?? UIScreen.main.bounds.size
        return size.width > size.height ? .landscape : .portrait
    }

    /// Everything the server's app context asks for, gathered on the main
    /// actor because most of it comes from UIKit.
    public static func screenContext(route: String, title: String) -> FeedobackScreenContext {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        return FeedobackScreenContext(
            route: route,
            title: title.isEmpty ? route : title,
            bundleId: bundleId,
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: model,
            locale: locale,
            timezone: timezone,
            viewport: viewport(in: scene),
            scale: scale(in: scene),
            orientation: orientation(in: scene))
    }
}
#endif
