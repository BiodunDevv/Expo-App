# Expo for macOS

Native SwiftUI port of the Electron app in `../expo desktop` (ported up to commit
`1d986de`). macOS 14.2 or newer, Xcode 27.

## Run

```bash
scripts/install.sh --env
```

Then open `Expo.xcodeproj` and press Run. To install a Release build into
`/Applications`:

```bash
scripts/install.sh
```

## Configuration

Read at launch, never compiled into the app. First value found wins, per key:

1. Process environment
2. `~/Library/Application Support/Expo/.env`
3. `Expo/.env` in this folder (Debug builds only)
4. The local backend URL (URL only)

| Key | Meaning |
| --- | --- |
| `EXPO_BACKEND_URL` | HTTPS, or HTTP on localhost |
| `EXPO_API_KEY` | Shared desktop key. Keep it private |

Restart Expo after changing it. `scripts/install.sh --env` replaces the installed copy.

## Layout

```
Expo/
  App/              App entry, app delegate and windows, menu bar
  State/            App model and the live session logic
  Domain/           Models and pure rules (no UI, covered by the checks)
  Services/
    Audio/          Microphone, computer audio tap, mixing, audio test
    Backend/        HTTP, realtime and transcription sockets
    Storage/        Encrypted local store
    System/         `.env` loading, shortcuts, notifications, screen capture
  Features/         One folder per screen or flow
    Shell/          Window root and sidebar
    Auth/           Welcome and sign-in
    Onboarding/     First-launch tour
    Home/           Home and the ready check
    Practice/       Starting a practice session
    Session/        Start Assist sheet
    Overlay/        Floating bot, bar and conversation panel
    History/        Saved sessions, transcripts and notes
    Profile/        Profile and CV
    Settings/       Settings, plans and the audio test row
  DesignSystem/     Theme, shared controls, Markdown
    Brand/          The bot marks and the voice orb
  Assets.xcassets/  Bots, Icons, Illustrations, Privacy, app icon
  Resources/        Animations and the moving robots
Packages/           Libraries.dev bot avatars and thinking orbs
Design/robot/       Source art for the voxel robots
scripts/            Install, checks, icon generation
Tests/              Logic checks
```

Xcode follows the folders: a file added under `Expo/` joins the app without
editing the project.

## First launch

A four-page welcome tour appears before sign-in, once per Mac. **Take the tour** on
the sign-in window shows it again.

## Ready check

Home lists what a session depends on and offers the fix beside each item.
Transcript consent, a passed computer-audio test and a reachable service are
required; the microphone and screen access are optional. macOS cannot report
whether computer audio capture is allowed, so that line shows the last audio test
on this Mac, which can be out of date if the permission is later removed. The
start sheet warns about anything blocking, without preventing a start.

## Auto answer and transcript only

The answer panel and the bar switch between the two at any time; the choice is
remembered. Both always save the transcript. With **Auto answer**, everything
heard is sent to the assistant at each pause of about 0.7 seconds, with no check
for whether it is a question; only bare hesitation sounds are left out, and an
identical line within eight seconds is sent once. **Include my voice** adds your
microphone. The server's own automatic answers stay off so nothing is answered
twice. Each message sent counts as a question, so this uses the allowance
quickly once plans are enforced. Words heard while an answer is being written go
in the next message.

## Conversation panel

Messages show who spoke and when, with Copy, Shorter, Example and Simpler under
each answer. The composer grows to four lines, can include the screen, and turns
Send into Stop while answering; stopping keeps the text that had arrived. The
voice orb follows the captured audio (see `THIRD_PARTY.md`). Its shader compiles
at run time, so no Metal toolchain is needed to build.

## Floating controls

The bot floats only while nothing else of Expo's is open; clicking it offers
**New session** or **Practice**. The bot, the bar and the answer panel can each
be dragged anywhere and stay where they are left. During a session the
conversation sits directly under the bar at the same width, and dragging either
moves both. The
bar folds into a small pill, and the panel switches between a small and the usual
size with **Shrink / Expand**. While a question is being spoken it appears in the
message box and sends when the speaker pauses; typing there takes it over. If
audio or transcription drops, Expo keeps retrying by itself, less often each
time, unless the cause needs the person (such as a permission).

## Practice

Practice is a live Assist session for rehearsing: choose interview, sales call,
presentation questions or a hard conversation, optionally describe it, and
start. It uses the same bar and answer panel, listens to the microphone and the
computer, answers what it hears on screen, and saves the transcript and notes to
History. Auto answer and your own voice are always on at the start, without
changing the settings for real sessions. A session is recognised as practice by
its `Practice · ` title. Answers count like any session's.

## Glance view

The answer panel's glance button shrinks it to one headline and up to three
points from the latest answer or suggestion, selected from the text on this Mac
and not rewritten. **Shorter**, **Example** and **Simpler** each ask the
assistant again and count as a question. **Full answer** returns to the
conversation. The choice is remembered.

## Screen-share privacy

Switch **Hidden / Visible** on the sign-in window, the floating dock or answer
panel, the sidebar, the menu bar menu, or Settings. It works before sign-in, is
saved on this Mac and defaults to hidden. When
the backend says the plan or administrator does not allow hiding, Expo is visible
and the switch is locked.

Switching replaces Expo's windows, because macOS (seen on 27.2) leaves a window
capturable if it is hidden a second time. The flag itself is a request to macOS:
test with the meeting app you actually use before relying on it.

Expo reads the setting back every two seconds. If macOS does not confirm that its
windows are hidden, it rebuilds them once; if that fails it stops Assist, keeps
the session, withdraws its windows and offers **Retry Privacy Protection** in the
menu bar. This confirms the flag, not what a particular meeting app captures.

Problems that happen with no Expo window in view are sent as macOS notifications,
with no detail while Expo is hidden.

## Permissions

macOS asks the first time each is used: system audio recording, microphone, and
screen recording (only for screen questions). System Settings → Privacy &
Security. If audio stays silent, check the permission first.

## Storage

State is AES-GCM encrypted at `~/Library/Application Support/Expo/state.enc`; the
key and session token live in Keychain. Local data from the Electron app
(`expo-state.json`) is left untouched and not imported; synced history comes back
from the backend after sign-in.

## Shortcuts

`⌘↩` ask Expo · `⇧⌘↩` ask about your screen · `⌘N` new session · `⌘1`–`⌘5` pages · `⌘\` sidebar · `⌘+` `⌘-` `⌘0` zoom

## Design

Warm off-white and charcoal neutrals, defined once for light and dark in
`Expo/DesignSystem/Theme.swift`; color is reserved for status marks. Appearance follows
macOS. The mark is a bot the person picks on first launch (and can change in
Settings): one of eighteen Libraries.dev bot avatars, drawn in code, or the
Icons8 [3D Stickle voxel robot](https://icons8.com/illustrations/illustration/3d-stickle-artificial-intelligence-robot-symbol-built-from-voxel-cubes)
in paper, blue, coral, green or violet. `Design/robot` holds the voxel originals;
`swift scripts/make-icon.swift` produces those variants. Work by the AI is shown
with Libraries.dev thinking orbs. Both kits are in `Packages/LibrariesDev`, whose
README says why they are copied. The icon in Applications is always the paper
robot; the Dock follows the choice while Expo runs.
**Before distributing Expo:** these files were
downloaded on a free Icons8 account and the artwork is not marked free to
redistribute. Icons8 says using its artwork as a logo needs an active
subscription for as long as it is used, and it cannot be trademarked. Icons are Icons8's `liquid-glass-color` pack (`ic-*` assets) and illustrations
its `bouncy` style, some animated; `icons8.json` records their ids. These free
assets need the Icons8 credit shown in Settings. The two 3D privacy images
(`3d-fluency`) are not in the free-to-redistribute set: check your Icons8 licence
before distributing Expo. Other symbols are
Apple SF Symbols.

## Checks

```bash
scripts/test.sh
```

## Not ported

Windows support, the DMG release workflow, and the Electron test fixtures (mock
mode). Screen-share hiding uses `NSWindow.sharingType`, which some capture tools
can ignore. Signing for distribution and notarisation are not set up.
# Expo-App
