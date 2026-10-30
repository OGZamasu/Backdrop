import Foundation

/// Lenses that come with Backdrop, written into the Lenses folder the first time so they can be opened, copied and changed.
/// Each shows off a few of the things a lens file can do.
enum SampleLenses {
    static let readme = """
    Backdrop lenses
    ===============

    Each folder in here is a lens: a lens.json and any pictures it uses. Nothing in them runs code, so lenses are safe to share.
    Open one in any text editor and change it; Backdrop reloads when you switch back to it. Copy a folder to make your own.

    The full list of what lens.json can say is in docs/LENS_FORMAT.md in the Backdrop repository:
    https://github.com/OGZamasu/Backdrop/blob/main/docs/LENS_FORMAT.md
    """

    static let all: [(folder: String, json: String)] = [
        ("Halo and Horns.backdroplens", """
        {
          "format": 1,
          "name": "Halo and Horns",
          "glyph": "😇",
          "description": "A halo when you smile; horns when you raise your eyebrows.",
          "tags": ["face", "triggers"],
          "layers": [
            { "type": "shape", "shape": "circle", "color": "#FFD70000", "stroke": "#FFD54A", "strokeWidth": 0.07,
              "anchor": "headTop", "offset": [0, 0.22], "size": 0.26, "width": 1.2,
              "animate": { "kind": "bob", "speed": 0.8, "amount": 0.05 },
              "show": { "when": "smile", "above": 0.4 } },
            { "type": "shape", "shape": "triangle", "color": "#D7263D", "stroke": "#5B0A14",
              "anchor": "forehead", "offset": [0.55, 0.45], "size": 0.6, "width": 0.38, "rotation": -18, "mirror": true,
              "animate": { "kind": "dropIn" },
              "show": { "when": "browRaise", "above": 0.5 } }
          ]
        }
        """),
        ("Heart Eyes.backdroplens", """
        {
          "format": 1,
          "name": "Heart Eyes",
          "glyph": "😍",
          "description": "Hearts for eyes, and sparkles when you smile.",
          "tags": ["face", "emoji"],
          "layers": [
            { "type": "emoji", "emoji": "❤️", "anchor": "eyes", "offset": [0.5, 0], "size": 0.6, "mirror": true,
              "animate": { "kind": "pulse", "speed": 1.4, "amount": 0.12 } }
          ],
          "emitters": [
            { "preset": "sparkles", "anchor": "eyes", "show": { "when": "smile", "above": 0.4 } }
          ]
        }
        """),
        ("Golden Hour.backdroplens", """
        {
          "format": 1,
          "name": "Golden Hour",
          "glyph": "🌇",
          "description": "Warm light and a soft edge. A look for the whole picture, so it needs no face.",
          "tags": ["look"],
          "look": { "saturation": 1.25, "contrast": 1.05, "tint": "#FFB347", "tintAmount": 0.18, "vignette": 0.5 }
        }
        """),
        ("Bubble Talk.backdroplens", """
        {
          "format": 1,
          "name": "Bubble Talk",
          "glyph": "🫧",
          "description": "Open your mouth and blow bubbles.",
          "tags": ["face", "particles"],
          "emitters": [
            { "preset": "bubbles", "anchor": "mouth", "show": { "when": "mouthOpen", "above": 0.4 } }
          ]
        }
        """),
        ("Name Tag.backdroplens", """
        {
          "format": 1,
          "name": "Name Tag",
          "glyph": "🏷️",
          "description": "A HELLO name tag along the bottom of the picture. Change the words to your own.",
          "tags": ["screen", "text"],
          "layers": [
            { "type": "shape", "shape": "roundRect", "color": "#E63946", "stroke": "#FFFFFF",
              "anchor": "screen", "offset": [0, -0.37], "size": 0.17, "width": 0.52 },
            { "type": "text", "text": "HELLO MY NAME IS", "color": "#FFFFFF",
              "anchor": "screen", "offset": [0, -0.335], "size": 0.036 },
            { "type": "text", "text": "YOUR NAME", "color": "#FFFFFF",
              "anchor": "screen", "offset": [0, -0.395], "size": 0.06, "weight": 1 }
          ]
        }
        """),
    ]

    /// Writes the samples and a readme into `directory`, leaving anything already there alone.
    static func install(into directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let readmeURL = directory.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readmeURL.path) { try readme.write(to: readmeURL, atomically: true, encoding: .utf8) }
        for sample in all {
            let folder = directory.appendingPathComponent(sample.folder, isDirectory: true)
            guard !fm.fileExists(atPath: folder.path) else { continue }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try sample.json.write(to: folder.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        }
    }
}
