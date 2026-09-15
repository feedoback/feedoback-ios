// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Feedoback",
    // macOS is here so the layers that are not UI — the wire types, the
    // transport, the store — can be tested with `swift test` and no simulator.
    // Everything that touches UIKit sits behind `#if canImport(UIKit)`.
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "Feedoback", targets: ["Feedoback"])
    ],
    targets: [
        // No dependencies, deliberately: this ships inside someone else's app.
        // The privacy manifest ships with it: an SDK without one is what
        // gets a customer's App Store submission rejected, not ours.
        .target(name: "Feedoback", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "FeedobackTests", dependencies: ["Feedoback"]),
    ]
)
