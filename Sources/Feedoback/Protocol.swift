import Foundation

/// The wire, and nothing else.
///
/// Every type here matches a fixture in `packages/protocol/fixtures`, which is
/// the only thing this SDK and the server both read. A field added on one side
/// and not the other fails a test rather than a customer.

// MARK: - Categories

/// What a thread is. Support was retired when the widget stopped offering it;
/// the server refuses one, so it is not here either.
public enum FeedobackCategory: String, Codable, Sendable, CaseIterable {
    case feedback
    case bug
    case idea
}

// MARK: - Identity

/// Who the host app says this is.
///
/// Declared, never authoritative — it is the customer's own code asserting a
/// user id. `userHash` is the exception: their server signs the id with the
/// project's key, so a thread can only be opened for an account they vouched
/// for. See the Verified identity section of the project's settings.
public struct FeedobackVisitor: Codable, Equatable, Sendable {
    public var id: String?
    public var email: String?
    public var name: String?
    /// Hex HMAC-SHA256 of the id (or the email, when there is no id).
    public var userHash: String?

    public init(id: String? = nil, email: String? = nil, name: String? = nil, userHash: String? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.userHash = userHash
    }

    /// Whether this names anybody at all. A name on its own does not.
    public var isNamed: Bool {
        !(id?.isEmpty ?? true) || !(email?.isEmpty ?? true)
    }
}

// MARK: - Custom context

/// A value a host app may attach to a thread.
///
/// The server takes a string, a finite number, a boolean or null, and nothing
/// nested. Swift has no `Any` that is `Codable`, so the shape is spelled out.
public enum FeedobackValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Where the visitor was

public struct FeedobackViewport: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum FeedobackOrientation: String, Codable, Sendable {
    case portrait
    case landscape
}

/// Coarse on purpose: whether they were online, never the carrier.
public enum FeedobackNetwork: String, Codable, Sendable {
    case wifi
    case cellular
    case none
}

/// A screen of an app, as the server's `appContextSchema` takes it.
public struct FeedobackScreenContext: Codable, Equatable, Sendable {
    public var platform: String = "ios"
    /// Where the visitor was, as the host app named it: "checkout/payment".
    public var route: String
    /// What to call it in the list. Falls back to the route.
    public var title: String
    public var bundleId: String
    public var appVersion: String
    public var buildNumber: String
    public var osVersion: String
    public var deviceModel: String
    public var locale: String
    public var timezone: String
    public var viewport: FeedobackViewport
    public var scale: Double
    public var orientation: FeedobackOrientation
    public var network: FeedobackNetwork?

    public init(
        platform: String = "ios",
        route: String,
        title: String,
        bundleId: String,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceModel: String,
        locale: String,
        timezone: String,
        viewport: FeedobackViewport,
        scale: Double,
        orientation: FeedobackOrientation,
        network: FeedobackNetwork? = nil
    ) {
        self.platform = platform
        self.route = route
        self.title = title
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.locale = locale
        self.timezone = timezone
        self.viewport = viewport
        self.scale = scale
        self.orientation = orientation
        self.network = network
    }
}

// MARK: - Attachments

public struct FeedobackAttachment: Codable, Equatable, Sendable {
    public var kind: String
    public var storageKey: String
    public var contentType: String
    public var sizeBytes: Int

    public init(kind: String, storageKey: String, contentType: String, sizeBytes: Int) {
        self.kind = kind
        self.storageKey = storageKey
        self.contentType = contentType
        self.sizeBytes = sizeBytes
    }
}

// MARK: - Opening a thread

public struct FeedobackThreadRequest: Codable, Equatable, Sendable {
    public var category: FeedobackCategory
    public var body: String
    /// One to five stars, when the project asks and the visitor answered.
    public var rating: Int?
    public var pageContext: FeedobackScreenContext
    public var visitor: FeedobackVisitor?
    public var metadata: [String: FeedobackValue]?
    public var attachments: [FeedobackAttachment]?
    /// The customer's own release, so feedback can be read per build.
    public var appVersion: String?

    public init(
        category: FeedobackCategory,
        body: String,
        rating: Int? = nil,
        pageContext: FeedobackScreenContext,
        visitor: FeedobackVisitor? = nil,
        metadata: [String: FeedobackValue]? = nil,
        attachments: [FeedobackAttachment]? = nil,
        appVersion: String? = nil
    ) {
        self.category = category
        self.body = body
        self.rating = rating
        self.pageContext = pageContext
        self.visitor = visitor
        self.metadata = metadata
        self.attachments = attachments
        self.appVersion = appVersion
    }
}

// MARK: - What the server answers

/// Why a client was turned away. Logged once in a debug build and never shown
/// to the person holding the phone, who misconfigured nothing.
public enum FeedobackRefusal: String, Codable, Sendable {
    case notAnApp = "not-an-app"
    case mobileNotEnabled = "mobile-not-enabled"
    case appNotAllowed = "app-not-allowed"
    case visitorNotIdentified = "visitor-not-identified"
    case visitorNotVerified = "visitor-not-verified"
    case visitorNotListed = "visitor-not-listed"

    /// What a developer reading the console needs to do about it.
    public var advice: String {
        switch self {
        case .notAnApp:
            return "The request did not declare itself an app."
        case .mobileNotEnabled:
            return "This project takes no mobile feedback yet. Add the app under Mobile apps."
        case .appNotAllowed:
            return "This bundle id is not on the project's list of apps."
        case .visitorNotIdentified:
            return "This project only takes feedback from identified people. Call identify() first."
        case .visitorNotVerified:
            return "This project requires a signature. Have your server sign the id and pass it as userHash."
        case .visitorNotListed:
            return "This visitor is not on the project's allow list."
        }
    }
}

/// Which ways in the panel offers. An app is given one; the others have no
/// native equivalent yet, and the server reduces them before answering.
public struct FeedobackActions: Codable, Equatable, Sendable {
    public var point: Bool
    public var record: Bool
    public var feedback: Bool
}

/// How the owner wants the widget to look. Light and dark is deliberately not
/// here: the sheet is native UI inside someone else's app, so that is the
/// device's call and the host app's, never a dashboard's.
public struct FeedobackAppearance: Codable, Equatable, Sendable {
    public var color: String
    public var size: String
    public var position: String
    public var rating: Bool
    public var welcome: String
    public var label: String
    public var icon: String
    public var actions: FeedobackActions
    public var bubble: Bool
    public var bubbleSeconds: Int
}

public struct FeedobackConfigResponse: Codable, Equatable, Sendable {
    public var projectName: String
    /// False when this client may not run the widget. Never an error.
    public var enabled: Bool
    public var reason: FeedobackRefusal?
    public var appearance: FeedobackAppearance
}

// MARK: - Coding

extension JSONEncoder {
    /// What the SDK posts. Keys are written as declared, and a nil field is
    /// left out rather than sent as null, which is what the server's schema
    /// treats as absent.
    static var feedoback: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var feedoback: JSONDecoder { JSONDecoder() }
}
