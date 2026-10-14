# JPortal for iOS

The JIIT webportal, as an iPhone app. A native Swift and SwiftUI port of [JPortal for Android](https://github.com/codelif/jportal-android), which is itself a remake of [JPortal](https://github.com/codeblech/jportal).

Unofficial. Not affiliated with or endorsed by JIIT.

## What's in it

- attendance per subject, counted class by class, with the portal's own percentage
- how many classes you can skip, or need to attend, against a goal you set
- a calendar of every class, a trend line, and the full class list per subject
- exam date sheet with rooms, seats, clashes, free days and a countdown, plus Add to Calendar
- marks read straight from the portal's marks PDF
- SGPA, CGPA, grade cards, and a CGPA what-if you drag on the chart
- every subject you've ever registered, searchable, with subject choices and MOOC status
- profile, fees, bank details (masked), hostel
- works offline from the last good answer, light and dark
- a demo student, behind the Demo button, so you can look around without an account

## Building

Needs Xcode 26 or newer (iOS 17+ deployment target).

1. Open `JPortal.xcodeproj`.
2. Under Signing & Capabilities, pick your team and change the bundle id (`app.jportal.ios`) to one you own.
3. Run the `JPortal` scheme.

From the command line:

```sh
xcodebuild -project JPortal.xcodeproj -scheme JPortal -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Tests

The portal client lives in `JPortalKit`, a Swift package with no app dependencies. Its tests reuse ktjiit's fixtures: the crypto vectors, real portal responses with identities scrubbed, and all 14 marks PDFs with their golden outputs.

```sh
cd JPortalKit && swift test
```

The same suite runs on the iOS Simulator through the `JPortalKit` scheme.

## Layout

```
JPortalKit/          the portal client, a port of ktjiit
  Crypto/            daily rotating AES key, LocalName header
  HTTP/              transport, server clock skew, retries, error mapping
  Auth/              Google token exchange, session, JWT expiry
  Model/             lenient decoding of every portal response
  Marks/             tiny PDF reader + table rebuilt from cell geometry
  API/Portal.swift   one typed call per endpoint
JPortal/             the app
  App/               cache (one JSON file per key), stores, session manager (keychain), repository
  Domain/            attendance math, exam plan, GPA projection, formatting
  Features/          sign-in, attendance, academics, subjects, me
  UI/                palette, the wavy attendance ring, charts, shared components
  Demo/              the made-up student
```

## How sign-in works on iOS

The portal moved students to Google sign-in. Google won't sign anyone in from a web view it recognises as embedded, and the portal's Google client ID only trusts the portal's own origin. The Android app gets around both, and this port does the same thing with iOS APIs:

- `WKWebView.loadSimulatedRequest` serves a tiny Google Identity Services page as if it came from `https://webportal.jiit.ac.in:6011`. This is the iOS counterpart of Android's request intercept.
- The web view sends Mobile Safari's own user agent.
- Google's account chooser opens as a popup and gets its own sheet. The credential comes back to Swift through a script message handler, which only accepts messages from the portal origin, and the app trades it for a portal session.
- "Use the portal page" loads the real portal login page and reads the login response off its own XHR, for when the button route breaks.
- "I have a session code" takes a base64url session from another device.

Tokens last 2 hours. When one expires, the app tries a silent Google re-auth in a hidden web view, then falls back to a sign-in sheet over the cached data.

## Status

Verified in the iOS 27 Simulator:

- the protocol port: the real portal answers the config call, and Google renders its button and opens its sign-in page for jiit.ac.in
- every screen, end to end, with the demo student

Not verified, because it needs a JIIT Google account:

- the token exchange, every authenticated endpoint against live data, and silent re-auth. The request shapes are ported line for line from ktjiit and tested against its captured responses.

Not ported from Android yet:

- submitting teacher feedback. Feedback windows are listed, but submitting writes to the portal and couldn't be tested.
- background calendar sync. There's a per-paper Add to Calendar instead.
- GitHub update checks, Material You palettes, alternate icons, and the debug report.

## Privacy

Your portal session is stored in the keychain, on this device only, and only ever goes to the portal. Cached responses stay in Application Support, excluded from backups. No analytics, no crash reporting.

## License

GPL-3.0-only, the same as the code it's ported from. See LICENSE and NOTICE.
