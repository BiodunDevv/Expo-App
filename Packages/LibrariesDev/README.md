# Libraries.dev kits

Copied from <https://github.com/Jakubantalik/Libraries.dev> at commit
`4604afe95443d6f0e4bd7c513f99829328a8cc1e` (2026-11-24): `BotAvatarsKit` and
`ThinkingOrbsKit`, both MIT (`LICENSE`).

They are copied rather than added as a remote package because upstream
`BotAvatarsKit` does not compile for macOS. Changes made here:

- `BotAvatarColor.swift`: reads a SwiftUI colour through `NSColor`.
- `BotAvatarClock.swift`: a 24 fps timer replaces the iOS `CADisplayLink`, and
  it idles while the app has nothing visible.
