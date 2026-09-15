# Feedoback for iOS

Feedback from inside your app, filed next to the feedback from your website.

```swift
import Feedoback

Feedoback.shared.start(FeedobackConfiguration(projectKey: "pk_…"))
```

That is the whole setup. Everything the owner controls — the accent, the word
on the launcher, whether stars are asked for, who may send — comes from the
dashboard, so it changes without an app release.

Requires iOS 15. No dependencies, and there will not be any.

## Install

Swift Package Manager, from Xcode's **Add Package Dependencies**, or:

```swift
.package(url: "https://github.com/feedoback/feedoback-ios", from: "0.1.0")
```

## Opening the sheet

From a control you already own — a Settings row, a menu item:

```swift
Feedoback.shared.present()                 // "Send feedback"
Feedoback.shared.present(category: .bug)   // "Report a problem"
```

Or let the SDK draw a floating button. It is off unless you ask, because an
app that did not ask for one should not get a button over its own interface:

```swift
Feedoback.shared.start(FeedobackConfiguration(
    projectKey: "pk_…",
    launcher: FeedobackLauncherOptions(enabled: true, corner: .bottomTrailing)))
```

`setLauncherHidden(true)` takes it out of the way of a screen that wants none.

## Naming the screen

Feedback is filed under the screen it came from, the way a website's is filed
under a page. Tell the SDK where the visitor is:

```swift
Feedoback.shared.setScreen("checkout/payment", title: "Payment")
```

A path reads best. Identifiers are folded out of it on the way in, so
`orders/12345` and `orders/67890` are one screen, not two thousand.

## Who the visitor is

```swift
Feedoback.shared.identify(FeedobackVisitor(
    id: user.id, email: user.email, name: user.name))

Feedoback.shared.reset()   // on sign-out
```

This is your app's word about who someone is, which is all it can be. If the
project asks for verified identity, have your **server** sign the id with the
project's key and pass the result:

```swift
FeedobackVisitor(id: user.id, email: user.email, userHash: signatureFromYourServer)
```

```
userHash = HMAC-SHA256(projectIdentitySecret, userId)   // hex, on your server
```

The key never belongs in the app: anything the app holds, the app can forge.

## What else is worth knowing about them

Whatever you will want to read beside the words — the plan they are on, the
flag they have, the tier they bought:

```swift
Feedoback.shared.setContext(["plan": .string("pro"), "seats": .number(12)])
```

It rides on every thread opened from then on, and is stamped when the visitor
finishes writing rather than when it is sent, so something written offline
arrives under what was true at the time. At most thirty keys; anything past
that is dropped rather than costing the visitor their feedback. `reset()`
clears it along with the identity.

## Screenshots

A picture of the screen rides along, and the visitor sees it before it goes
and can take it off. Nothing is sent that the person looking at it did not
look at first.

Secure text fields are hidden without being asked. Mark anything else:

```swift
Feedoback.shared.redact(cardNumberLabel)
```

Sensitive views are painted over before the bitmap exists, so the real pixels
never sit in memory on the way out. Turn the whole thing off per project with
`screenshots: .off` — your app knows which of its screens are sensitive, which
is why that decision lives here and not in a dashboard.

## Light and dark

Follows the device. Set `theme: .light` or `.dark` only if your app forces its
own appearance — the server is never asked and never tells.

## Offline

A thread that cannot be sent is written to disk and goes out on the next
launch, with the identity it was written under. Bounded at 20 threads, 20 MB
and 7 days, because an unbounded queue on someone else's device is a bug.

## What it collects

Only what you hand it, plus what any app can read about itself:

- the identity you pass to `identify()` and the context you pass to `setContext()`
- the message, the rating, and the screenshot the visitor kept
- your bundle id, version and build
- the device model, OS version, locale, time zone, screen size and orientation
- a random install id, minted here and stored in `UserDefaults`

**Not** collected: the advertising identifier, the vendor identifier, location,
contacts, crashes, network traffic, or anything at all about other apps.
Nothing is swizzled and nothing is intercepted.

`PrivacyInfo.xcprivacy` ships in the package, so your App Store submission does
not break on ours.

## Running the example

```bash
./Example/run.sh                    # builds and installs on a booted iPhone simulator
```

## Tests

```bash
./ci.sh                             # everything continuous integration runs
```

Or one at a time:

```bash
swift test                          # the wire, transport, store and session — no simulator
xcodebuild test -scheme Feedoback \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro'
./size.sh                           # what it costs a customer's binary
```

The second is not a repeat of the first. Redaction and the theme are behind
`canImport(UIKit)`, so on a Mac they are compiled out: 65 tests run there and
75 on a simulator, and the ten in the gap include what a screenshot paints
over. Only the simulator run is the whole suite.

The wire tests read the fixtures the server reads too. A field added on one
side and not the other fails a build rather than a customer.

## Issues

This repository is published from the one the SDKs are developed in, so it
takes no pull requests. Report anything here:
<https://github.com/feedoback/feedoback-sdks/issues>.
