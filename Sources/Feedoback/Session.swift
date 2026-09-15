import Foundation

/// What a visitor has written but not yet sent.
public struct FeedobackDraft: Equatable, Sendable {
    public var category: FeedobackCategory
    public var body: String
    /// One to five stars, when the project asks for them.
    public var rating: Int?
    /// Typed into the sheet when the app never named anybody.
    public var email: String?
    /// Encoded bytes of the screen, if the visitor kept the picture.
    public var screenshot: Data?
    public var screenshotContentType: String

    public init(
        category: FeedobackCategory = .feedback,
        body: String = "",
        rating: Int? = nil,
        email: String? = nil,
        screenshot: Data? = nil,
        screenshotContentType: String = "image/jpeg"
    ) {
        self.category = category
        self.body = body
        self.rating = rating
        self.email = email
        self.screenshot = screenshot
        self.screenshotContentType = screenshotContentType
    }

    /// A rating on its own is still feedback; an empty form is not.
    public var hasSomethingToSay: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rating != nil
    }
}

public enum FeedobackSendOutcome: Equatable, Sendable {
    /// It reached the server.
    case sent(threadId: String)
    /// Nothing reached the server, so it is written down for the next launch.
    case queued
    /// The server said no, and will keep saying no. Never queued: retrying
    /// something that cannot succeed only wastes a device's battery.
    case refused(FeedobackRefusal?)
    /// Everything else: a bad request, a server fault. Reported, not retried.
    case failed
}

/// Everything between a visitor finishing a sentence and it arriving.
///
/// No UIKit: it takes a draft and returns an outcome, which is what lets the
/// whole path be tested without a phone.
public actor FeedobackSession {
    private let transport: FeedobackTransport
    private let store: FeedobackStore
    private let context: @Sendable () async -> FeedobackScreenContext
    private let metadata: @Sendable () async -> [String: FeedobackValue]
    private let log: FeedobackLog

    public init(
        transport: FeedobackTransport,
        store: FeedobackStore,
        context: @escaping @Sendable () async -> FeedobackScreenContext,
        metadata: @escaping @Sendable () async -> [String: FeedobackValue] = { [:] },
        log: FeedobackLog = FeedobackLog(level: .warning)
    ) {
        self.transport = transport
        self.store = store
        self.context = context
        self.metadata = metadata
        self.log = log
    }

    /// Sends what the visitor wrote, or keeps it.
    public func send(_ draft: FeedobackDraft) async -> FeedobackSendOutcome {
        guard draft.hasSomethingToSay else { return .failed }

        let screen = await context()
        // Read when the visitor finishes writing, not when it is sent: a
        // thread queued on the checkout screen should not flush carrying the
        // context of wherever they happen to be three days later.
        let custom = await metadata()
        var visitor = await store.visitor()

        // An address typed into the sheet is the visitor's own word about
        // themselves, and the only way to answer someone the app never named.
        if let email = draft.email?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty, visitor?.email?.isEmpty ?? true {
            visitor = FeedobackVisitor(
                id: visitor?.id, email: email, name: visitor?.name, userHash: visitor?.userHash)
        }

        // The picture goes first, because the thread has to name it. Losing it
        // must not cost the words, so a failure here carries on without it.
        var attachments: [FeedobackAttachment] = []
        if let bytes = draft.screenshot {
            do {
                attachments.append(
                    try await transport.upload(
                        bytes, kind: "screenshot", contentType: draft.screenshotContentType))
            } catch {
                log.warning("the screenshot could not be uploaded; sending the message without it")
            }
        }

        let request = FeedobackThreadRequest(
            category: draft.category,
            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
            rating: draft.rating,
            pageContext: screen,
            visitor: visitor,
            metadata: custom.isEmpty ? nil : custom,
            attachments: attachments.isEmpty ? nil : attachments,
            appVersion: screen.appVersion)

        return await post(request, queueIfUnreachable: true)
    }

    /// Tries everything written down earlier. Called on the next foreground.
    @discardableResult
    public func flushQueue() async -> Int {
        var sent = 0
        for queued in await store.queued() {
            // The identity travelled with it; nothing here re-stamps it.
            let outcome = await post(queued.request, queueIfUnreachable: false)
            switch outcome {
            case .sent:
                await store.remove(queued)
                sent += 1
            case .refused, .failed:
                // It will not start working. Keeping it would mean trying
                // again on every launch, forever.
                await store.remove(queued)
            case .queued:
                // Still no network. Stop: the rest will fare no better, and a
                // burst of doomed requests costs the device more than waiting.
                return sent
            }
        }
        return sent
    }

    private func post(
        _ request: FeedobackThreadRequest,
        queueIfUnreachable: Bool
    ) async -> FeedobackSendOutcome {
        do {
            let id = try await transport.createThread(request)
            return .sent(threadId: id)
        } catch FeedobackTransportError.unreachable {
            guard queueIfUnreachable else { return .queued }
            await store.enqueue(request)
            log.debug("no network; kept this one for the next launch")
            return .queued
        } catch FeedobackTransportError.rateLimited(let retryAfter) {
            // Also worth keeping: it is a "later", not a "no".
            guard queueIfUnreachable else { return .queued }
            await store.enqueue(request)
            log.warning("sending too fast; retry after \(retryAfter ?? 60)s")
            return .queued
        } catch FeedobackTransportError.refused(let reason) {
            log.warning(reason?.advice ?? "this project would not take the feedback")
            return .refused(reason)
        } catch {
            log.error("the feedback could not be sent: \(error)")
            return .failed
        }
    }
}

/// The console, quietly. This runs inside somebody else's product, so it says
/// nothing in a release build unless the host app asked it to.
public struct FeedobackLog: Sendable {
    public var level: FeedobackLogLevel

    public init(level: FeedobackLogLevel) { self.level = level }

    public func error(_ message: @autoclosure () -> String) { write(.error, message()) }
    public func warning(_ message: @autoclosure () -> String) { write(.warning, message()) }
    public func debug(_ message: @autoclosure () -> String) { write(.debug, message()) }

    private func write(_ at: FeedobackLogLevel, _ message: String) {
        guard level >= at else { return }
        print("[Feedoback] \(message)")
    }
}
