import Foundation

/// A value a test changes after handing something a closure that reads it.
///
/// Swift 6 will not let a closure crossing a concurrency boundary capture a
/// `var`, and two tests here depend on exactly that: one moves the clock the
/// store reads, the other changes the plan after the thread that recorded it
/// was queued. A reference sidesteps the rule honestly rather than silencing
/// it — XCTest drives these on one thread, and the closures only read.
final class Mutable<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
