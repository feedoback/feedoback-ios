import Foundation

/// Every call the SDK makes to the app, and nothing about how it looks.
///
/// A native client sends no Origin — there is nothing for a browser to set —
/// so it declares itself instead, and the project's owner decides which apps
/// are allowed. The headers here are what that gate reads.
public enum FeedobackHeader {
    /// Which gate the request goes through.
    public static let platform = "X-Feedoback-Platform"
    /// The bundle id, read from the OS. Declared, never verified.
    public static let app = "X-Feedoback-App"
    /// A random id stored on first launch. A rate-limit bucket only: one
    /// device in a loop is stopped without taking a whole carrier's worth of
    /// visitors with it, because one address is thousands of people.
    public static let install = "X-Feedoback-Install"
    /// Which SDK and version. Diagnostic.
    public static let sdk = "X-Feedoback-SDK"
}

public enum FeedobackTransportError: Error, Equatable {
    /// The project does not exist, or the key is wrong.
    case unknownProject
    /// The gate turned this client away. Never shown to a visitor.
    case refused(FeedobackRefusal?)
    case rateLimited(retryAfter: TimeInterval?)
    /// Anything else the server said, with its status.
    case server(status: Int)
    /// No network, a timeout, a cancelled task. Worth retrying later.
    case unreachable
    case malformedResponse
}

/// What the transport needs to know about the device it is running on.
/// Passed in rather than read, which is what makes it testable off a phone.
public struct FeedobackClientIdentity: Sendable {
    public var bundleId: String
    public var installId: String
    public var sdkVersion: String

    public init(bundleId: String, installId: String, sdkVersion: String) {
        self.bundleId = bundleId
        self.installId = installId
        self.sdkVersion = sdkVersion
    }
}

/// A single upload, minted by the app and bound by an HMAC to the exact bytes
/// it was signed for.
struct FeedobackUploadTicket: Codable, Equatable {
    var uploadUrl: String
    var storageKey: String
}

struct FeedobackThreadCreated: Codable, Equatable {
    var threadId: String
}

public actor FeedobackTransport {
    private let host: URL
    private let projectKey: String
    private let identity: FeedobackClientIdentity
    private let session: URLSession

    public init(
        host: URL,
        projectKey: String,
        identity: FeedobackClientIdentity,
        session: URLSession = .shared
    ) {
        self.host = host
        self.projectKey = projectKey
        self.identity = identity
        self.session = session
    }

    private func url(_ path: String) -> URL {
        let key = projectKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectKey
        return host
            .appendingPathComponent("api")
            .appendingPathComponent("widget")
            .appendingPathComponent(key)
            .appendingPathComponent(path)
    }

    private func request(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("ios", forHTTPHeaderField: FeedobackHeader.platform)
        request.setValue(identity.bundleId, forHTTPHeaderField: FeedobackHeader.app)
        request.setValue(identity.installId, forHTTPHeaderField: FeedobackHeader.install)
        request.setValue("ios/\(identity.sdkVersion)", forHTTPHeaderField: FeedobackHeader.sdk)
        return request
    }

    /// Whether this client may run the widget, and how the owner wants it to
    /// look. A refusal comes back as a dormant config, not an error.
    public func config(for visitor: FeedobackVisitor?) async throws -> FeedobackConfigResponse {
        var components = URLComponents(url: url("config"), resolvingAgainstBaseURL: false)
        var query: [URLQueryItem] = []
        if let id = visitor?.id, !id.isEmpty { query.append(URLQueryItem(name: "id", value: id)) }
        if let email = visitor?.email, !email.isEmpty {
            query.append(URLQueryItem(name: "email", value: email))
        }
        if let name = visitor?.name, !name.isEmpty {
            query.append(URLQueryItem(name: "name", value: name))
        }
        if let hash = visitor?.userHash, !hash.isEmpty {
            query.append(URLQueryItem(name: "hash", value: hash))
        }
        components?.queryItems = query.isEmpty ? nil : query

        guard let target = components?.url else { throw FeedobackTransportError.malformedResponse }

        let (data, response) = try await send(request(target, method: "GET"))
        try check(response, data: data)

        guard let config = try? JSONDecoder.feedoback.decode(FeedobackConfigResponse.self, from: data)
        else { throw FeedobackTransportError.malformedResponse }
        return config
    }

    /// Opens a thread. The id it returns is only useful for a log.
    @discardableResult
    public func createThread(_ input: FeedobackThreadRequest) async throws -> String {
        var post = request(url("threads"), method: "POST")
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.httpBody = try JSONEncoder.feedoback.encode(input)

        let (data, response) = try await send(post)
        try check(response, data: data)

        guard let created = try? JSONDecoder.feedoback.decode(FeedobackThreadCreated.self, from: data)
        else { throw FeedobackTransportError.malformedResponse }
        return created.threadId
    }

    /// Bytes go through the app's own route, never straight to storage: that
    /// is where the ticket, the size cap and the byte-metered limit are, and
    /// it keeps bucket credentials out of anybody's app.
    public func upload(
        _ bytes: Data,
        kind: String,
        contentType: String
    ) async throws -> FeedobackAttachment {
        var ask = request(url("uploads"), method: "POST")
        ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ask.httpBody = try JSONSerialization.data(withJSONObject: [
            "kind": kind, "contentType": contentType, "sizeBytes": bytes.count,
        ])

        let (ticketData, ticketResponse) = try await send(ask)
        try check(ticketResponse, data: ticketData)

        guard let ticket = try? JSONDecoder.feedoback.decode(
            FeedobackUploadTicket.self, from: ticketData)
        else { throw FeedobackTransportError.malformedResponse }

        // The ticket's URL is a path on the app the SDK was pointed at.
        guard let target = URL(string: ticket.uploadUrl, relativeTo: host)?.absoluteURL else {
            throw FeedobackTransportError.malformedResponse
        }

        var put = URLRequest(url: target)
        put.httpMethod = "PUT"
        put.setValue(contentType, forHTTPHeaderField: "Content-Type")
        put.httpBody = bytes

        let (putData, putResponse) = try await send(put)
        try check(putResponse, data: putData)

        return FeedobackAttachment(
            kind: kind,
            storageKey: ticket.storageKey,
            contentType: contentType,
            sizeBytes: bytes.count)
    }

    // MARK: - Plumbing

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            // A timeout, a dropped connection, a tunnel: worth queueing for
            // later rather than telling the visitor their words are gone.
            throw FeedobackTransportError.unreachable
        }
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FeedobackTransportError.malformedResponse
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 404:
            throw FeedobackTransportError.unknownProject
        case 403:
            throw FeedobackTransportError.refused(refusal(in: data))
        case 429:
            let header = http.value(forHTTPHeaderField: "Retry-After")
            throw FeedobackTransportError.rateLimited(retryAfter: header.flatMap(TimeInterval.init))
        default:
            throw FeedobackTransportError.server(status: http.statusCode)
        }
    }

    private func refusal(in data: Data) -> FeedobackRefusal? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let reason = object["reason"] as? String
        else { return nil }
        return FeedobackRefusal(rawValue: reason)
    }
}
