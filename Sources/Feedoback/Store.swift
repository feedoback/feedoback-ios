import Foundation

/// What survives a launch.
///
/// Three things, and nothing else: a random install id, the identity the app
/// last declared, and threads that could not be sent yet. No advertising id,
/// no vendor id, no device fingerprint — the only identifier minted here is a
/// UUID that dies with the app.
///
/// `UserDefaults` rather than the Keychain, deliberately: the Keychain
/// survives the app being deleted, which is the wrong behaviour for something
/// whose whole purpose is to be forgettable.
public protocol FeedobackDefaults: AnyObject {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: FeedobackDefaults {}

/// A thread written down because it could not be sent.
public struct FeedobackQueuedThread: Codable, Equatable, Sendable {
    public var request: FeedobackThreadRequest
    public var queuedAt: Date

    public init(request: FeedobackThreadRequest, queuedAt: Date = Date()) {
        self.request = request
        self.queuedAt = queuedAt
    }
}

public actor FeedobackStore {
    /// An unbounded queue on somebody else's device is a bug, so it is capped
    /// three ways: how many, how old, and how much.
    public static let maxQueuedThreads = 20
    public static let maxQueueAge: TimeInterval = 7 * 24 * 60 * 60
    public static let maxQueueBytes = 20 * 1024 * 1024

    private enum Key {
        static let install = "com.feedoback.installId"
        static let visitor = "com.feedoback.visitor"
        static let queue = "com.feedoback.queue"
    }

    private let defaults: FeedobackDefaults
    private let now: @Sendable () -> Date

    public init(defaults: FeedobackDefaults = UserDefaults.standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    // MARK: - The install

    /// Minted on first launch and kept. Not an identity and not a secret: it
    /// is a rate-limit bucket, so one device in a loop can be told to stop
    /// without stopping everyone behind the same carrier address.
    public func installId() -> String {
        if let existing = defaults.string(forKey: Key.install), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Key.install)
        return fresh
    }

    // MARK: - Who the app says this is

    public func visitor() -> FeedobackVisitor? {
        guard let data = defaults.data(forKey: Key.visitor) else { return nil }
        return try? JSONDecoder.feedoback.decode(FeedobackVisitor.self, from: data)
    }

    public func setVisitor(_ visitor: FeedobackVisitor?) {
        guard let visitor, visitor.isNamed else {
            defaults.removeObject(forKey: Key.visitor)
            return
        }
        guard let data = try? JSONEncoder.feedoback.encode(visitor) else { return }
        defaults.set(data, forKey: Key.visitor)
    }

    /// What an app calls on sign-out. The install id stays: it is the same
    /// device, and it identifies nobody.
    public func reset() {
        defaults.removeObject(forKey: Key.visitor)
    }

    // MARK: - The queue

    public func queued() -> [FeedobackQueuedThread] {
        guard let data = defaults.data(forKey: Key.queue) else { return [] }
        let all = (try? JSONDecoder.feedoback.decode([FeedobackQueuedThread].self, from: data)) ?? []
        return all.filter { now().timeIntervalSince($0.queuedAt) < Self.maxQueueAge }
    }

    /// Keeps what the visitor wrote when the network would not take it.
    ///
    /// The identity is stamped in by the caller before this is reached, and
    /// never at flush time: feedback written by one signed-in person must not
    /// go out attributed to whoever signed in after them.
    public func enqueue(_ request: FeedobackThreadRequest) {
        var all = queued()
        all.append(FeedobackQueuedThread(request: request, queuedAt: now()))

        // Oldest out first: the newest complaint is the one still worth having.
        while all.count > Self.maxQueuedThreads { all.removeFirst() }
        while let data = try? JSONEncoder.feedoback.encode(all),
              data.count > Self.maxQueueBytes,
              all.count > 1 {
            all.removeFirst()
        }

        write(all)
    }

    public func remove(_ thread: FeedobackQueuedThread) {
        write(queued().filter { $0 != thread })
    }

    public func clearQueue() {
        defaults.removeObject(forKey: Key.queue)
    }

    private func write(_ threads: [FeedobackQueuedThread]) {
        guard let data = try? JSONEncoder.feedoback.encode(threads) else { return }
        defaults.set(data, forKey: Key.queue)
    }
}
