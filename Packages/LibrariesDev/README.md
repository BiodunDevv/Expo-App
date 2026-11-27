# Libraries.dev kits

Copied from <https://github.com/Jakubantalik/Libraries.dev> at commit
`4604afe95443d6f0e4bd7c513f99829328a8cc1e` (2026-11-24): `BotAvatarsKit` and
`ThinkingOrbsKit`, both MIT (`LICENSE`).

They are copied rather than added as a remote package because upstream
`BotAvatarsKit` does not compile for macOS. Changes made here:

- `BotAvatarColor.swift`: reads a SwiftUI colour through `NSColor`.
- `BotAvatarClock.swift`: a 24 fps timer replaces the iOS `CADisplayLink`, and
  it idles while the app has nothing visible.

`BorderBeamKit`, `VoiceCore` and `VoiceRingKit` were copied from commit
`d058179` (2026-11-26), all MIT. One change: `VoiceCanvas.swift` and
`RotateBeamLayers.swift` draw at 30 frames a second rather than at the display
rate, to spare the processor during a meeting. Their shaders need Apple's Metal
Toolchain, installed once with:

```bash
xcodebuild -downloadComponent MetalToolchain
```

The gooey effect in the app is Expo's own SwiftUI drawing: Libraries.dev's
`liquid-gooey` is a React package.
