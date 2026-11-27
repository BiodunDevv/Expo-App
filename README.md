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
    Session/        The question asked before a meeting starts
    Overlay/        Floating bot and the session window
    History/        Saved sessions, transcripts and notes
    Profile/        Profile and CV
    Settings/       Settings, plans and the audio test row
  DesignSystem/     Theme, shared controls, Markdown
    Brand/          The bot marks and the voice ring
  Assets.xcassets/  Bots, Icons, Illustrations, Privacy, app icon
  Resources/        Animations and the moving robots
Packages/           Libraries.dev bot avatars, orbs, beam and ring
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
start question warns about anything blocking, without preventing a start.

## Starting and naming a meeting

Starting asks only "Start a meeting?", from the main window or the floating bot.
There is nothing to fill in. The session is called `Meeting session` until it
ends; the backend then names it from what was said, or from what was asked when
nothing was heard. A name someone typed is never replaced.

## Auto answer and transcript only

The session window switches between the two at any time; the choice is
remembered. Both always save the transcript. With **Auto answer**, everything
heard is sent to the assistant at each pause of about 0.7 seconds, with no check
for whether it is a question; only bare hesitation sounds are left out, and an
identical line within eight seconds is sent once. **Include my voice** adds your
microphone. The server's own automatic answers stay off so nothing is answered
twice. Each message sent counts as a question, so this uses the allowance
quickly once plans are enforced. Words heard while an answer is being written go
in the next message.

## The session window

A session shows one window, in three sizes:

- **Input** (how it starts): the input, with **Auto** and **Transcript** beside
  it, over the toolbar.
- **Chat**: the whole conversation between them. It opens with the first answer,
  unless it was hidden by hand, and whenever you ask something.
- **Minimized**: a small note that the meeting is in progress, with its time, new
  answers and **Show chat**. Answers never expand it.

The toolbar holds the session menu, **Answer** (`⌘↩`), screen capture, hide from
screen sharing, options, listening, end, small size, minimize (**−**) and **Show
chat / Hide chat**. Esc steps down: options, chat, minimized, then the floating
bot.

The chat follows the newest words. Scroll up and it holds still, offering
**Latest** or **New message**; scrolling to the end, pressing that, or asking
something follows again.

Drag the sides to change the width, the bottom or a lower corner to change the
height, and the toolbar or the small note to move it. Size and place are
remembered.

With auto answer on, no transcript is shown: heard words appear in the input,
then the answer. Transcript only shows what is said, with a **Chat** page for
anything asked. A captured picture can be viewed while the session runs and is
not saved. Glance view, answer style and see-through are under options. A beam
runs round the window only while Expo is hearing or answering.

## Practice

Practice is a live Assist session for rehearsing: choose interview, sales call,
presentation questions or a hard conversation, optionally describe it, and
start. It uses the same session window, listens to the microphone and the
computer, answers what it hears on screen, and saves the transcript and notes to
History. Auto answer and your own voice are always on at the start, without
changing the settings for real sessions. A session is recognised as practice by
its `Practice · ` title. Answers count like any session's.

## Answer style

Options (also Settings and onboarding) sets how questions are answered: standard, bullets, short or full script, each optionally
in simple English. It applies to heard and typed questions and **What should I
say?**, not to named follow-ups such as Shorter. The backend must accept
`answerFormat` on `/assistant/ask/stream`.

## Saved profiles

Notes for a job or client, added in Profile or saved from the practice screen.
The one marked **In use** in Profile is given to new meetings, and the start
question names it. They stay on this Mac, in the encrypted store; the CV is one
per account.

## Practice review

Opening a finished practice session shows words spoken, pace, filler phrases and
each reply beside the suggested answer, all worked out on this Mac. **Get
feedback** asks the assistant for coaching and counts as one answer. Pace needs
the backend's `speechSeconds`; sessions recorded before it show none.

## Screen capture

**Screen capture** in the toolbar is set to the entire screen; press return to
answer every question visible, with nothing to type
(`⇧⌘↩` does it in one step). A typed question is asked about the screen instead.
The answer is saved with the session and the transcript gets a `Screen` line
naming what was answered. The picture can be viewed while the session runs and is never saved; Expo's
own windows are left out. The chat provider must be able to read images.

## See-through

The floating windows are dark glass with light text in every appearance, so they
read over white or dark screens. **Clear**, **Tinted** and **Solid** are chosen
from the options menu or in Settings. The text sits on cards;
the space around them lets the meeting show. Code in answers has its language,
line numbers, colour and a copy button.

## Audio recovery

A quiet Mac delivers no computer audio, which is not a fault: Expo sends a little
silence to keep transcription connected, and rebuilds capture only when the
output device changes or the microphone stops delivering. One alert is shown per
outage.

## Emailed notes

Choose whether a session's notes and transcript are emailed: a default in
Settings, and for the running session in its options or
when ending it. A finished session also has **Email it to me**. The server sends
only to the account's own address, on plans that include emailed notes, and needs
its mail keys. It needs the backend's `emailNotes` field and
`POST /sessions/:id/notes/email`.

## Small size

The toolbar's size button shrinks the session window to its small size and
switches back to the size from before.

## Glance view

**Glance view** in the options menu reduces the answers to one headline and up to three
points from the latest answer or suggestion, selected from the text on this Mac
and not rewritten. **Shorter**, **Example** and **Simpler** each ask the
assistant again and count as a question. **Full answer** returns to the
conversation. The choice is remembered.

## Screen-share privacy

Switch **Hidden / Visible** on the sign-in window, the session
window, the sidebar, the menu bar menu, or Settings. It works before sign-in, is
saved on this Mac and defaults to hidden. When
the backend says the plan or administrator does not allow hiding, Expo is visible
and the switch is locked.

While hidden, Expo's menus are left out of capture too, it shows no tooltips,
and the pointer keeps its plain arrow over the floating windows. macOS gives an
app no way to remove the pointer itself from another app's screen share, so
people watching can still see it move.

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
with Libraries.dev thinking orbs. The Libraries.dev kits are in `Packages/LibrariesDev`, whose
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
