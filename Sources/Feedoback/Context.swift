import Foundation

/// What a host app attaches to every thread it opens from now on: a plan, a
/// tier, a feature flag — whatever the owner will want to read beside the
/// words. The web SDK's `setContext` and this are the same thing.
///
/// The bounds mirror `customContextSchema` on the server exactly, and follow
/// its rule: keep what is valid and drop what is not, rather than refusing the
/// lot. A mistake in one key should not cost the visitor their feedback, and
/// applying the bounds here as well means a thread is never turned away for
/// something the SDK could see on the device.
public enum FeedobackCustomContext {
    public static let maxKeys = 30
    public static let maxKeyLength = 80
    public static let maxValueLength = 500

    /// What a bridge sends, turned into values the SDK stores and bounded on
    /// the way in.
    ///
    /// React Native and Flutter both arrive with a dictionary of whatever
    /// JavaScript or Dart had, so the reading of it lives here rather than in
    /// each of them.
    public static func from(_ dictionary: [String: Any]) -> [String: FeedobackValue] {
        var values: [String: FeedobackValue] = [:]
        for (key, raw) in dictionary {
            guard let value = FeedobackValue(any: raw) else { continue }
            values[key] = value
        }
        return bounded(values)
    }

    /// Drops what the server would refuse and keeps the rest.
    ///
    /// Keys are considered in sorted order, so which thirty survive is the
    /// same on every launch. Dictionary order in Swift is not stable, and a
    /// context that lost a different key each time would be a bug nobody
    /// could reproduce.
    public static func bounded(_ context: [String: FeedobackValue]) -> [String: FeedobackValue] {
        var kept: [String: FeedobackValue] = [:]
        for key in context.keys.sorted() {
            guard kept.count < maxKeys else { break }
            guard !key.isEmpty, key.utf16.count <= maxKeyLength else { continue }
            guard let value = context[key], let bounded = bound(value) else { continue }
            kept[key] = bounded
        }
        return kept
    }

    private static func bound(_ value: FeedobackValue) -> FeedobackValue? {
        switch value {
        case .string(let text):
            return .string(truncate(text))
        case .number(let number):
            // The server takes finite numbers only. An infinity is a fault in
            // the app's own arithmetic, not something to file feedback under.
            return number.isFinite ? .number(number) : nil
        case .bool, .null:
            return value
        }
    }

    /// Zod measures a string in UTF-16 units, so a line of emoji is twice as
    /// long to the server as `count` says here. Trimmed by character and
    /// measured the way the server measures, so it is never cut through the
    /// middle of a surrogate pair.
    private static func truncate(_ text: String) -> String {
        guard text.utf16.count > maxValueLength else { return text }
        var kept = ""
        for character in text {
            guard kept.utf16.count + character.utf16.count <= maxValueLength else { break }
            kept.append(character)
        }
        return kept
    }
}

extension FeedobackValue {
    /// One value out of what a bridge boxed it as.
    ///
    /// A JSON number reaches here as an NSNumber, and so does a boolean: the
    /// only way to tell `true` from `1` is the CFNumber type it was boxed as.
    /// Getting that wrong would file `plan: 1` as `plan: true`.
    init?(any raw: Any) {
        if raw is NSNull {
            self = .null
        } else if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if number.doubleValue.isFinite {
                self = .number(number.doubleValue)
            } else {
                return nil
            }
        } else if let text = raw as? String {
            self = .string(text)
        } else {
            // A list, a map, an object of the app's own — nothing the server
            // stores, and stringifying it would file a description under
            // somebody's feedback.
            return nil
        }
    }
}
