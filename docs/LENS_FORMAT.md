# Making a lens

A Backdrop lens is a folder with a `lens.json` and any pictures it uses. Nothing in it runs code, so lenses are safe to share and
easy to make: copy a folder from your Lenses folder (Studio › Lenses › ⋯ › Open Lenses Folder), open `lens.json` in a text
editor, and change it. Backdrop looks for changes whenever it comes to the front (opening the Studio does that), and the Reload
item in the same menu does it on demand. A lens that is on is put on again if its `lens.json` or any file in its folder changed.

```
My Lens.backdroplens/
  lens.json
  glasses.png        (anything lens.json names)
```

The design follows what Snap's Lens Studio documents publicly (face landmarks, expression triggers, face attachments, warps) and
the lens library of the old Snap Camera app. It uses no Snap code or lens files; it is a much smaller thing, written for Backdrop.

## A whole lens

```json
{
  "format": 1,
  "name": "Party",
  "author": "you",
  "glyph": "🥳",
  "description": "A hat, and confetti when you smile.",
  "tags": ["face", "fun"],

  "layers":   [ ...things pinned to the face or the picture... ],
  "warps":    [ ...bulges and pinches... ],
  "emitters": [ ...streams of particles... ],
  "look":     { ...colour for the whole picture... }
}
```

`format` (1 or more; 1 is the only one so far) and `name` are required. A lens needs at least one layer, warp, emitter or a look that
changes something. Anything wrong in a part (an unknown anchor, a missing picture) is skipped with a note you can see in the
Studio, and the rest still works. A `lens.json` that isn't valid JSON is reported with its line and column.

## Where things go: anchors

Positions are in **eye-spacings** from the middle of the eyes: `x` along the eyes, `y` up the face. One unit is the distance between
the eyes, so a hat at `y: 1.5` sits on top of the head whether you are close to the camera or far away, and follows every tilt.

| anchor | where |
| --- | --- |
| `eyes` | between the eyes (the default) |
| `leftEye`, `rightEye` | each eye (as they appear in the picture) |
| `nose`, `mouth` | the tip of the nose, the middle of the mouth |
| `forehead`, `headTop` | the forehead, the top of the head |
| `chin` | below the mouth |
| `cheekLeft`, `cheekRight` | the cheeks |
| `face` | the middle of the face |
| `screen` | the picture itself: `offset` is a fraction of the picture from its middle (`[0, -0.4]` is low and central); `size` is a fraction of its height. Needs no face. |

## Layers

```json
{ "type": "image", "image": "glasses.png", "anchor": "eyes", "size": 1.1 }
```

| key | meaning |
| --- | --- |
| `type` | `image`, `emoji`, `text` or `shape` |
| `image` / `emoji` / `text` / `shape` | what to draw. Shapes: `circle`, `rect`, `roundRect`, `triangle`, `star`, `heart`. Pictures must be PNG, JPEG, HEIC or WebP files inside the lens folder (see Limits). Text is up to 80 characters, an emoji up to 8. |
| `color`, `stroke` | `#RGB`, `#RRGGBB` or `#RRGGBBAA`. `color` fills shapes and colours text; `stroke` outlines shapes (not text or pictures). |
| `strokeWidth` | outline thickness, in the same units as `size` (default: a small fraction of the shape) |
| `anchor`, `offset` | where; `offset` is `[x, y]` |
| `size` | height (for text, the font size). `width` sets a shape's width separately. |
| `rotation` | degrees, on top of the head's tilt |
| `follow` | `"none"` to stay upright instead of tilting with the head; anything else follows it |
| `opacity` | 0 to 1 |
| `blend` | `normal` (default), `add` (glows), `multiply`, `screen` |
| `mirror` | `true` also draws a mirror image across the middle of the face (anchor and offset together), so one ear makes two, and an `anchor` of `leftEye` with `mirror` covers both eyes |
| `weight` | text weight, 0 to 1 (default 0.8, a bold) |
| `show` | when it appears (below) |
| `animate` | movement (below) |

## When things appear: triggers

```json
"show": { "when": "mouthOpen", "above": 0.5, "fade": 0.2 }
```

`when` is one of `always`, `faceFound`, `mouthOpen`, `browRaise`, `blink`, `smile`. Each reads 0 to 1.

- `mouthOpen`: how far apart the lips are, compared with the size of the face.
- `browRaise`, `blink` and `smile` are judged against how *your* face looks at rest, so a naturally high eyebrow or narrow eye
  doesn't set anything off. `blink` needs both eyes to close (a wink doesn't count). `smile` is a mouth wider than usual that lasts a
  moment, so a word doesn't set it off. These three read 0 while the head is turned or tipped more than about 25 degrees.

`above` and `below` set the thresholds (with none, a half; once on, it stays on a little below the line so it doesn't flicker).
`fade` is the time in seconds to fade in and out (default 0.12). Things that are pinned to the face disappear when there is no face.

## Movement: animations

```json
"animate": { "kind": "bob", "speed": 1, "amount": 0.15 }
```

`bob` (up and down), `float` (a slow drift), `pulse` (grows and shrinks), `spin`, `wiggle` (rocks side to side), `dropIn` (falls into
place each time it appears). `speed` is cycles a second (default 1); `amount` is how far (default 0.15).

## Warps

```json
{ "kind": "bulge", "anchor": "leftEye", "radius": 0.6, "strength": 0.8, "show": { "when": "always" } }
```

`bulge` swells part of the face and `pinch` squeezes it. `radius` is in eye-spacings (default 0.6); `strength` is 0 to 1 (default 0.6).
Warps need a face anchor. At most 6 warps are used.

## Emitters

```json
{ "preset": "bubbles", "anchor": "mouth", "show": { "when": "mouthOpen", "above": 0.4 }, "rate": 1.5, "size": 1 }
```

`anchor` defaults to `mouth`. Presets: `rainbow`, `fire`, `hearts`, `sparkles`, `confetti`, `bubbles`. `rate` and `size` scale them
(default 1, at most 2). Rainbow and fire go toward the chin, along the face; hearts and bubbles drift up and out; confetti goes up
and out and then falls; sparkles scatter in every direction. At most 6 emitters are used, and they share a fixed number of particles.

## Look

A colour change for the whole picture, with no face needed:

```json
"look": { "saturation": 1.25, "contrast": 1.05, "brightness": 0, "hue": 0, "vignette": 0.5, "tint": "#FFB347", "tintAmount": 0.18 }
```

## Limits

These keep a lens from slowing Backdrop down, whoever wrote it:

- `lens.json` up to 1 MB; names up to 60 characters, descriptions 300, up to 16 tags.
- Up to 64 layers, 6 emitters and 6 warps.
- Pictures: PNG, JPEG, HEIC or WebP, up to 20 MB, 8192 pixels along a side and 40 million pixels each, 100 million in all, and up to
  16 different ones (a picture used by several layers counts once). They are scaled down to 1024 pixels when the lens is put on.
- Links (symbolic links, aliases) inside a lens folder are not followed, so a lens can only show files that are in its own folder.
- Numbers are kept to sensible ranges. A lens made for a newer `format` than your Backdrop understands says so instead of half working.

## Tips

- Start from a sample. Each one in the Lenses folder shows a few of the things above.
- Draw props facing the camera on a transparent background; a square picture is easiest to line up.
- To place something by eye, set `anchor` and a rough `offset`, switch back to Backdrop, and nudge until it's right.
- Heavy lenses are the ones with many large pictures. A few emoji and shapes cost almost nothing.
