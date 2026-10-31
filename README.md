# Backdrop

A menu bar app that replaces your camera background and shows up as its own camera ("Backdrop Camera") in Zoom, Meet, FaceTime and anything else.

On top of the system background effect it adds:

- **Live backgrounds**: looping video, a live window or your whole screen, and 68 built-in backdrops drawn in code: studio rooms (home office, library, brick loft, podcast studio...), places (mountain lake, sunset beach, night skyline, Tokyo rain...), live scenes (aquarium, campfire, nebula, cherry blossom, digital rain, a rainy window...), mesh gradients, lit studio walls (including a flat chroma green), camera looks (frosted glass, dim room, noir, golden hour), and the old Windows **3D Pipes** and **3D Maze** screensavers (rendered in 3D with SceneKit). A parallax option drifts the backdrop as you move.
- **AI backgrounds**: describe a room and Image Playground generates it on-device.
- **Automation**: switch by app (Zoom → this one), calendar event (title contains "client"), or time of day. Global shortcuts: ⌃⌥→ / ⌃⌥← cycle backgrounds, ⌃⌥↑ / ⌃⌥↓ cycle lenses, ⌃⌥R new game, ⌃⌥B camera on/off.
- **Lenses**: Snapchat-style filters, face effects, games and living scenes layered over the picture, and sent to everyone on your call. Sixty filters (photographic looks like Film Noir, Super 8 and Watercolour; weather and light like rain, fireworks and northern lights; and fifteen you play with your hands, like air painting, fire hands and a light blade), sixty-two face lenses (animal and costume dress-up, hearts, tears and storm clouds that follow your expression, funhouse warps), thirty-two games played with your hands, your face or your whole body (slice fruit with your hand like a sword, finger-gun target shooting, Magic Duel, Air Hockey, Copy Cat, Space Blaster, Meteor Dodge, Hole in the Wall...) and ten **scenes**: a safari, a jungle, the deep sea, a dinosaur park, a haunted manor, the Arctic, outer space, a dragon castle, an enchanted forest and a pirate cove, where hand-drawn animals walk behind and around you, notice you, come after you, and run off when you wave. The picker shows a real preview of every lens. You can make your own too: a lens is a folder with a `lens.json`, see [docs/LENS_FORMAT.md](docs/LENS_FORMAT.md). See [Lenses](#lenses).
- **Cutout controls**: quality, edge softness, light wrap (background glow on your edges), colour match.

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

The preview mirrors you like a mirror, except while a game is on, when it shows exactly what other people see so the score and words read the right way round.

**Your own lenses** live in `~/Library/Application Support/Backdrop/Lenses/` (Studio › Lenses › ⋯ › Open Lenses Folder). Each is a folder with a `lens.json` that pins pictures, emoji, text and shapes to the face, switches things on with a smile, a blink, an open mouth or raised eyebrows, warps parts of the face, emits particles and tints the picture. No code, so they are safe to share. Thirty examples are put there (new ones are added when you update, and never one you have deleted); the format, and the limits that keep a stranger's lens from slowing you down, are in [docs/LENS_FORMAT.md](docs/LENS_FORMAT.md). While a lens with text on it is on, the preview shows what other people see rather than a mirror, so the words read the right way round.

Adding a built-in one: implement `Lens` (`Engine/Lenses/Lens.swift`), or for a game `Game` (`GameKit.swift`), and list it in `LensCatalog`. Game rules are plain structs with no pipeline in them, so they are tested exactly; `Tests/SyntheticScene.swift` draws a fake person, room and face so lenses can be rendered to PNGs (`TEST_RUNNER_BACKDROP_TEST_OUTPUT=some/folder xcodebuild test ...`) and looked at.

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
- The camera extension and the app-to-extension handoff have no automated tests: they need a signed install and camera permission.
  The engine (cutout, compositing, sources, rules, 3D Pipes) is covered by the tests above.

## License

[MIT](LICENSE)
