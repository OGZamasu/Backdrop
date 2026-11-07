# Backdrop

A menu bar app that replaces your camera background and shows up as its own camera ("Backdrop Camera") in Zoom, Meet, FaceTime and anything else.

On top of the system background effect it adds:

- **Live backgrounds**: looping video, a live window or your whole screen, and 68 built-in backdrops drawn in code: studio rooms (home office, library, brick loft, podcast studio...), places (mountain lake, sunset beach, night skyline, Tokyo rain...), live scenes (aquarium, campfire, nebula, cherry blossom, digital rain, a rainy window...), mesh gradients, lit studio walls (including a flat chroma green), camera looks (frosted glass, dim room, noir, golden hour), and the old Windows **3D Pipes** and **3D Maze** screensavers (rendered in 3D with SceneKit). A parallax option drifts the backdrop as you move.
- **Present**: share a window, a whole screen or a second camera into your call and arrange it: behind you as always, as a framed panel floating in the room with you standing in front of it, or filling the picture with you over it as a cutout or a camera bubble. Move and resize things with the mouse on the Studio preview, or with your hands: pinch to grab, pinch with both hands to resize, double pinch to zoom. See [Present](#present).
- **AI backgrounds**: describe a room and Image Playground generates it on-device.
- **Automation**: switch by app (Zoom → this one), calendar event (title contains "client"), or time of day. Global shortcuts: ⌃⌥→ / ⌃⌥← cycle backgrounds, ⌃⌥↑ / ⌃⌥↓ cycle lenses, ⌃⌥R new game, ⌃⌥P pause or resume screen sharing, ⌃⌥B camera on/off.
- **Lenses**: Snapchat-style filters, face effects, games and living scenes layered over the picture, and sent to everyone on your call. Sixty filters (photographic looks like Film Noir, Super 8 and Watercolour; weather and light like rain, fireworks and northern lights; and fifteen you play with your hands, like air painting, fire hands and a light blade), sixty-three face lenses (animal and costume dress-up, hearts, tears and storm clouds that follow your expression, funhouse warps, and **Dragon Ball**: power up through nine forms, from Super Saiyan to Ultra Instinct, with both fists and fire ten moves from the show with your hands), thirty-two games played with your hands, your face or your whole body (slice fruit with your hand like a sword, finger-gun target shooting, Magic Duel, Air Hockey, Copy Cat, Space Blaster, Meteor Dodge, Hole in the Wall...) and ten **scenes**: a safari, a jungle, the deep sea, a dinosaur park, a haunted manor, the Arctic, outer space, a dragon castle, an enchanted forest and a pirate cove, where hand-drawn animals walk behind and around you, notice you, come after you, and run off when you wave. The picker shows a real preview of every lens. You can make your own too: a lens is a folder with a `lens.json`, see [docs/LENS_FORMAT.md](docs/LENS_FORMAT.md). See [Lenses](#lenses).
- **Cutout controls**: quality, edge softness, light wrap (background glow on your edges), colour match.
- **A Studio window** that does everything the menu bar popover does, and more. The camera switch and what is on the picture stay in the sidebar (with a red dot while your screen is going out); **Backgrounds**, **Present** (sharing a window, screen or second camera and arranging it), **Lenses**, **Automation**, **Camera** (the camera choice and cutout controls, with a live preview beside the sliders) and **Settings** (open at login, on-screen messages, keyboard shortcuts, Backdrop Camera setup and removal, permissions, the folders where your files live, reset, about) are one click or ⌘1 to ⌘6 away. ⌘, opens Settings from anywhere.

## Download

Get the latest `Backdrop-x.y.z.zip` from [Releases](https://github.com/OGZamasu/Backdrop/releases). It is signed with a Developer ID certificate and notarized by Apple, so it opens without warnings.

1. Unzip it and drag **Backdrop.app** into **Applications**. It has to live there for macOS to accept its camera extension.
2. Open it. Click the menu bar icon, then **Set Up Backdrop Camera**, and approve it in System Settings › General › Login Items & Extensions › Camera Extensions.
3. Turn the camera on, then choose **Backdrop Camera** in your video app.

Check the download against the `.sha256` file on the release page with `shasum -a 256 -c Backdrop-x.y.z.zip.sha256`.

## Lenses

Pick one from the **Lenses** row in the menu bar popover, or the **Lenses** pane of the Studio, which also has a live preview, descriptions and high scores. A lens sits on top of whatever backdrop is chosen (including Off) and shows up in Backdrop Camera.

- **Filters** work on the whole picture or on your outline. Some use your hands (marked "Needs a hand in view").
- **Faces** use Vision's face landmarks (the largest face in view): eyes, mouth and eyebrows. Open your mouth for the breath lenses and Mouth Catch, raise your eyebrows for laser eyes. Eyebrow height is judged against how your face looks at rest, so it works for any face.
- **Hands** use Vision's hand pose (up to two hands, about 30 looks a second, only while a lens that uses them is on). Lenses and games read which fingers are out, where a fingertip points and how fast the hand moves. Hold a hand up where the camera can see it, in good light. A very fast swipe can blur it out of tracking for a moment, so the games hold on to a hand briefly and Fruit Slash lets a strong body movement cut fruit when the hand is lost.
- **Games** wait for you to step into the frame (or hold up a hand, for the hand games), count down, play, and show your score; leave the picture and they pause. Silhouette games (Balloon Pop, Breakout, Ball Pit, Meteor Dodge, Bubble Wrap, Hole in the Wall) use your cutout as the playing surface; Balloon Pop and Bubble Wrap react to *movement*, so swat. Flappy Face is steered by your head height. Best scores are kept between launches.
- **Scenes** replace what is behind you with a painted, living place. The animals live in lanes behind and in front of you and never cover your face. Wave your arms to scare them off; in the safari and jungle a bird can land on a raised open palm.
- **Dragon Ball** (Faces › Anime) uses your face, your hands and your cutout together, and is all drawn in code. Hold **both fists up and still** to power up: a ring of energy fills, then you go up a form with a flash and a shockwave, and keep holding to go up again (open your mouth wide while you hold to charge faster). The forms are Super Saiyan, 2 and 3 from Dragon Ball Z, then God, Blue, Blue Kaioken, Ultra Ego, Ultra Instinct Sign and Ultra Instinct from Dragon Ball Super, each with its own hair, eyes, brows (none for Super Saiyan 3) and aura. Hold **both open palms low and apart** for a moment to calm back down to base. The form stays until your face has been gone for a few seconds, and it decides how big and what colour your moves are. The moves are each a pose held for a moment, so waving at your friends does not set them off: **Kamehameha** (cup both hands together at your side, fingers pointing out, then thrust), **Final Flash** (both flat palms up at your chest, then push), **Special Beam Cannon** (two fingers held to your forehead, then point), **Instant Transmission** (touch two fingers to your forehead and let go quickly), **Ki Blast** (push an open palm at the camera), **Finger Beam** (point a finger and hold it still), **Spirit Bomb** (both hands above your head, then swing them down), **Destructo Disc** (one flat hand above your head, then flick), **Solar Flare** (both hands together in front of your face) and **Zanzoken** (a very fast sideways swipe). The status line says what to try next.

The preview mirrors you like a mirror, except while a game is on, when it shows exactly what other people see so the score and words read the right way round.

**Your own lenses** live in `~/Library/Application Support/Backdrop/Lenses/` (Studio › Lenses › ⋯ › Open Lenses Folder). Each is a folder with a `lens.json` that pins pictures, emoji, text and shapes to the face, switches things on with a smile, a blink, an open mouth or raised eyebrows, warps parts of the face, emits particles and tints the picture. No code, so they are safe to share. Thirty examples are put there (new ones are added when you update, and never one you have deleted); the format, and the limits that keep a stranger's lens from slowing you down, are in [docs/LENS_FORMAT.md](docs/LENS_FORMAT.md). While a lens with text on it is on, the preview shows what other people see rather than a mirror, so the words read the right way round.

Adding a built-in one: implement `Lens` (`Engine/Lenses/Lens.swift`), or for a game `Game` (`GameKit.swift`), and list it in `LensCatalog`. Game rules are plain structs with no pipeline in them, so they are tested exactly; `Tests/SyntheticScene.swift` draws a fake person, room and face so lenses can be rendered to PNGs (`TEST_RUNNER_BACKDROP_TEST_OUTPUT=some/folder xcodebuild test ...`) and looked at.

## Present

Share a window (your slides, a browser tab, a design), a whole screen or a **second camera** from **Present** in the Studio, or **Add › Window, Screen or Camera…** in the menu bar popover. The picker shows every screen and every window, grouped by app, with live pictures of each, then your cameras, and a search. Backdrop's own windows are always left out. You can show or hide the pointer and share at 30 or 60 frames a second. A window or screen needs Screen Recording; if that is off, Present says so and opens the right page of System Settings, and cameras still work.

**A second camera** is anything macOS lists as a camera other than your main one and Backdrop Camera: a USB or HDMI-capture camera over your desk or a whiteboard, the built-in camera when your main one is external, an iPhone as a Continuity Camera or its Desk View, even OBS's virtual camera. It is shown exactly like a shared window, so it can sit behind you, float as a panel in a corner, or fill the picture with you over it, and it moves, resizes and snaps with your hands the same way. It is only on while it is showing: Backdrop's own camera has to be on first, pausing (⌃⌥P) or stopping closes it so its light goes off, and unplugging it shows a calm "disconnected" card until it is plugged back in. The picker has no live picture of a camera, since looking would turn every camera on. If you choose the second camera as your main camera, it steps aside and your previous background comes back.

Then pick an arrangement:

- **Backdrop**: the screen fills the picture behind you, as before.
- **Floating Panel**: the screen floats in the room as a framed panel and you stand in front of it, like a presenter in front of a big screen. It has continuous rounded corners, a fine highlight along its rim, a two-part shadow, a glow of its own colours on the wall round it, a slight turn toward the middle as it moves to the side, a little depth as you move your head, and a faint shadow of you falling on it. Around it: the screen's own light in a dim room (the default), your room blurred, or any backdrop from the library. Optionally its name sits in a small label under it.
- **Presenter**: the screen fills the picture and you are the thing that moves: your cutout, or a camera bubble (a circle or a rounded square) that frames your head and shoulders.

Presets (Left, Right, Centre, Corner Bubble, Side by Side) set things up in one click, and each arrangement remembers where you left things. Sliders set the size, tilt, depth, corners and shadow. One thing is shown at a time: a screen and a second camera together is not done yet.

**Moving things.** On the Studio preview, drag to move, pinch on the trackpad or scroll to resize, drag a corner handle, and double-click to zoom up and back. With **Control with your hands** on, do the same in the air: pinch (thumb to index finger) on or near the panel, or near you in Presenter, and hold it a moment to grab it; move your hand and it follows; pinch with both hands and spread them to resize; let go and it glides on, settles gently onto the centre lines, thirds and margins (with a brief guide), and is never lost off the edge. A double pinch zooms it up and back. A ring appears round the panel as your pinch comes near, draws in as your fingers close and fills as you hold. Only a deliberate pinch that starts near the panel and is held still for a moment grabs: open hands, fists, pointing, waving and hands on a keyboard never do, a quick pinch does nothing, a hand that leaves the picture lets go gently, and while a lens that uses your hands is on, a grab takes a slightly longer hold. A "How it works" animation and a live "Hand tracking: seeing 1 hand" line in the pane show it before you try. Hand tracking drops to 8 looks a second after a couple of seconds with no hand in view and goes back to 30 the moment one appears.

**Lenses go where you go.** A lens on top of Present (a crown, Dragon Ball's hair and aura, a game that follows your hands) is told where your face, hands and outline are in the picture people see, not where the camera had you, so it stays on your head when Present moves, shrinks or tucks you into a bubble. In a bubble, a lens works inside the bubble: what it draws follows you there, and the bubble's own room and ring stay when a lens puts you back over the picture.

**What viewers see.** The cursors, rings, handles and guides are drawn only on your own preview, never on the picture sent to the call: viewers just see the panel move. While a screen is arranged the preview shows exactly what they see (not a mirror), so your slides read the right way round.

**Pausing.** ⌃⌥P (or Pause Sharing) swaps the screen for a calm "Paused" card, from any app; press it again to resume. A closed window shows a "closed" card, never a black rectangle, and comes back by itself when it is opened again. While your screen is going out, the menu bar icon and the Studio's sidebar show a red dot.

**Full-screen apps.** An app that goes full screen moves to a desktop of its own, so from the desktop Backdrop is on it is out of view. The picker still lists it (marked "On another desktop", with a live picture), the capture keeps going while you switch between desktops, and it finds the window again if the capture restarts. Other windows on other desktops are not offered, since from here they cannot be told from hidden or minimised ones; switch to their desktop and they appear.

## Requirements

- macOS 15.1 or later (developed on macOS 27), Apple silicon.
- Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- For the virtual camera: a paid Apple Developer Program team (see below). Everything else runs without one.
- AI backgrounds need Apple Intelligence (Image Playground).

## Layout

```
Engine/           Camera, person segmentation, compositing, background sources, rules.
                  No UI. Compiled into both the app and the tests.
Engine/Lenses/    Lenses: filters, face effects, games, scenes, face and hand tracking, the silhouette physics,
                  Catalog/ (what the picker lists) and Packs/ for lenses made of plain files.
Engine/Backgrounds/  The built-in live backdrops drawn in code.
Engine/Stage/     Present: the layout model, springs and snapping, the hand and mouse controller, the stage compositor,
                  and the chrome drawn on the preview only.
docs/             The lens file format.
App/              Menu bar app, Studio window, automation, hotkeys, virtual camera bridge.
CameraExtension/  The system extension. It only forwards frames the app pushes into its sink stream.
Tests/            Engine tests (no camera or signing needed).
```

The app does all the work; the extension is deliberately tiny. The app writes finished frames into the extension's sink stream, and the extension republishes them. When the app is off, the extension shows an "off" card.

## Build

```bash
brew install xcodegen
xcodegen generate
```

Run the engine tests (no signing, no camera):

```bash
xcodebuild test -project Backdrop.xcodeproj -scheme BackdropTests -destination 'platform=macOS'
```

Compile the app without signing:

```bash
xcodebuild build -project Backdrop.xcodeproj -scheme Backdrop -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Trying it without signing

```bash
scripts/run-preview.sh
```

Builds, ad-hoc signs and opens the app. Everything works except the "Backdrop Camera" virtual camera, so you can preview the cutout, backgrounds, AI generation, live windows and automation inside the app itself. macOS will ask for camera access the first time you turn the camera on.

## Running it for real

The virtual camera is a system extension, so the app must be signed with a provisioning profile that has the System Extension capability and an app group. That needs:

- Your Apple ID added in Xcode › Settings › Accounts. Without it, signing fails with "No Accounts".
- A paid Apple Developer Program team. A free personal team cannot use system extensions.

**Set your identity once.** Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and set your own bundle ID and team:

```
BACKDROP_BUNDLE_ID = com.yourname.backdrop
DEVELOPMENT_TEAM = ABCDE12345
```

The camera extension's identifier is derived from it (`<bundle ID>.camera`), so nothing else needs editing. Then build with automatic signing and `-allowProvisioningUpdates` (this registers those App IDs, and an app group, on your team):

```bash
xcodegen generate
xcodebuild build -project Backdrop.xcodeproj -scheme Backdrop -destination 'platform=macOS' -allowProvisioningUpdates
```

Put the built `Backdrop.app` in `/Applications` (macOS only accepts a camera extension from an app there), then:

1. Run the app and click **Set Up Backdrop Camera** in the menu bar popover.
2. Approve it in System Settings › General › Login Items & Extensions › Camera Extensions.
3. Turn the camera on, then pick **Backdrop Camera** in your video app.

When you build a newer version, bump `CURRENT_PROJECT_VERSION` in `project.yml`. On launch Backdrop compares the installed extension's version with the one it carries and replaces it if they differ.

The device UUID shared between the app and the extension lives in `App/VirtualCamera/VirtualCameraSink.swift` and `CameraExtension/Provider.swift`. Change them together.

## Making a release

```bash
DEVELOPMENT_TEAM=YOURTEAMID scripts/release.sh
```

Builds a Release archive, signs it with Developer ID, has Apple notarize it, and writes `build/release/Backdrop-<version>.zip` and a checksum.
It uses the Apple ID Xcode is signed in to (no certificate to export, no password to store). The first run registers the App IDs and an app group on your team. The signature carries the name on your Developer ID certificate, which is your legal name for an individual account.

## Known gaps

- Output is 1280×720. Real frames arrive at about 30 fps; the camera extension repeats the latest one to present a steady 60 Hz.
  **The 60 fps is deliberate. Do not "fix" it back to 30.** macOS offers its own Background, Portrait and Studio Light
  effects on any camera whose format runs at 30 fps or less, and an app that applies them (Discord, FaceTime…) paints
  Apple's background over Backdrop's. A 60 fps format is not offered those effects (checked with
  `AVCaptureDeviceFormat.isBackgroundReplacementSupported`, which is `false` at 60 fps and `true` at 30, at both 720p and 1080p).
  The format's frame-rate range and the stream's `frameDuration` property must agree, or the extension fails to start.
- If macOS's Background or Portrait effect is switched on for Backdrop's *own* camera input (Control Center › Video Effects
  while Backdrop is running), the popover warns, because the app can't switch it off itself.
- The camera is switched on and off by hand (menu or ⌃⌥B). It does not yet start automatically when another app opens Backdrop Camera.
- Face tracking is tested against synthetic landmarks and cartoon faces, not recorded real ones, so prop placement
  (crown, ears, hat) and the mouth, eyebrow, blink and smile thresholds are the first things to tune on real faces. The lens
  status line in the popover shows all four live readings for exactly that.
- Games read your body from the cutout, so a person in front of a busy background or in poor light plays worse.
- Hand tracking was developed against made-up hands and Vision's reading of emoji hands (the only hands available without a camera),
  not recorded real ones. The gesture rules (which fingers count as out, the thumb "hammer" of Finger Guns, the poke speed of
  Whack-a-Mole, the vote in Rock Paper Scissors) are the first things to tune on real hands. A finger pointed straight at the camera
  looks the same to a 2D tracker as a curled one, so point across the picture or at an angle.
- Dragon Ball's hand poses (cupped hands for the Kamehameha, two fingers at the forehead, a palm pushed at the camera, a very fast swipe) were measured on made-up hands and Vision's reading of emoji hands, so how Vision reads a real cupped hand, and how much a real palm's size jitters, are the first things to tune. A palm pushed at the camera while saying "stop" can fire a Ki Blast. The moves are measured from your face, so none fires with no face in view. Its frames are heavier than most lenses (the aura of the top forms is the biggest part); the top form in the middle of a move took about 20 ms a frame in the tests on a busy machine (the Aura lens takes about 4 ms), so check it in a real call before relying on it at 30 frames a second.
- Present's hand control (the pinch thresholds, the hold before a grab, the hit area around the panel, the double pinch timing) was tuned on made-up hands and Vision's reading of emoji hands, not recorded real hands, like the other hand features. It is the first thing to tune on a real camera.
- Your hands work on the camera picture mapped to the whole picture, like a trackpad the size of the screen, so in Presenter with a small cutout or bubble the cursor is not over your own visible hand; the cursor shows where your pinch is.
- A second camera was built and tested without a second camera: the capture is the same code as the main camera's, but plugging one in, taking it away mid-call, an iPhone as a Continuity Camera and two cameras on one USB hub have not been tried with real hardware. Only one second camera can be shown at a time, it is shown as it arrives (a phone held upright gives a tall picture; there is no rotate or mirror option), and it is capped at 720p.
- The preview is not a mirror while a screen is arranged (so the screen reads correctly). A mirrored preview with a readable panel is not done yet. The plain Backdrop arrangement still mirrors, as before.
- How ScreenCaptureKit reports a resized window's area inside its frames (`contentRect`) was handled defensively but only checked against made-up values; a window being resized or changing shape is eased on screen, but has not been tried against a real capture in tests.
- Full-screen apps were tried with a throwaway test window (sent full screen, then the view moved to another desktop), not with real apps such as slideshows, browsers and video players. An app that opens a separate window for its full-screen mode (a slideshow, say) is found again by its title or as the app's full-screen window, which is a guess that has not been tried on one. The part of a full-screen window above the top of the screen (where its title bar slides in) is part of the window, so it may show as a thin strip at the top of the shared picture.
- The camera extension and the app-to-extension handoff have no automated tests: they need a signed install and camera permission.
  The engine (cutout, compositing, sources, rules, 3D Pipes) is covered by the tests above.

## License

[MIT](LICENSE)
