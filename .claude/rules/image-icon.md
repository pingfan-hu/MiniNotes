# MiniNotes App Icon Generation

When generating the app icon for MiniNotes, use the **claude-image-gen CLI** (guinacio/claude-image-gen). Never use Pillow, HTML/CSS+puppeteer, SVG, or any other method.

## API Key Safety

**NEVER** write, echo, export, or reference the Gemini API key as a literal value in any command, file, or permission entry. The key lives exclusively in `~/.zshrc` as `$NANOBANANA_GEMINI_API_KEY`. If it is not set, tell the user to run `source ~/.zshrc`.

## Prerequisites

The CLI must be built once before use. If `/tmp/claude-image-gen/mcp-server/build/cli.bundle.js` does not exist:

```bash
cd /tmp && git clone https://github.com/guinacio/claude-image-gen.git --depth=1
cd /tmp/claude-image-gen/mcp-server && npm install && npm run bundle
```

## Workflow

1. **Run the CLI** from the project root (output lands in current directory):
   ```bash
   cd /Users/pingfan/Documents/GitHub/software/MiniNotes
   GEMINI_API_KEY="$NANOBANANA_GEMINI_API_KEY" node /tmp/claude-image-gen/mcp-server/build/cli.bundle.js \
     --prompt "...prompt..." \
     --aspect-ratio "1:1"
   ```

2. **Preview** the generated `.jpg` with the Read tool.

3. **Convert to PNG at all required sizes** using `sips`:
   ```bash
   sips -s format png generated-<uuid>.jpg --out AppIcon-1024.png
   sips -z 512 512  AppIcon-1024.png --out AppIcon-512.png
   sips -z 256 256  AppIcon-1024.png --out AppIcon-256.png
   sips -z 128 128  AppIcon-1024.png --out AppIcon-128.png
   sips -z 64  64   AppIcon-1024.png --out AppIcon-64.png
   sips -z 32  32   AppIcon-1024.png --out AppIcon-32.png
   sips -z 16  16   AppIcon-1024.png --out AppIcon-16.png
   ```

4. **Place into the AppIcon.appiconset** at `MiniNotes/Assets.xcassets/AppIcon.appiconset/`.

5. **Delete** the temporary `.jpg` after conversion.

## App Icon Visual Style

MiniNotes is a macOS menu bar Markdown note-taking app. The icon should reflect:

- **Shape**: macOS squircle (do NOT add your own corner rounding — describe the content, Xcode applies the squircle mask automatically)
- **Background**: soft light lavender or warm off-white — calm, not stark white, not dark
- **Accent color**: muted indigo/lavender (`#6B7FC4` range)
- **Motif**: pen/pencil + paper/document — e.g. an open notebook with a pen resting on it, or a piece of paper with handwritten lines and a pencil beside it
- **Style**: clean flat illustration, minimal depth — no 3D render, no neon, no gradients on the background
- **Mood**: calm, minimal, approachable — a quiet tool for quick notes

## Prompt Template

```
macOS app icon, 1:1, no rounded corners (host OS clips the squircle).
Soft light lavender background (#EEF0FF), fills edge to edge.
Center: flat illustration of an open notebook with a few ruled lines
and a pencil resting diagonally across it.
Notebook cover in muted indigo (#6B7FC4), pages in near-white.
Pencil in warm yellow with a gray eraser tip.
Clean flat design, minimal shadows, no gradients on the background,
no text, no border. The illustration occupies roughly 65% of the canvas,
centered with generous padding. Academic, calm, approachable aesthetic.
```

Adjust the prompt as needed to explore variations (different background hues, notebook vs. sticky note, etc.).

## Output Path Convention

Final icon assets live at:
```
MiniNotes/Assets.xcassets/AppIcon.appiconset/
```

The `Contents.json` in that directory maps each size to its filename.
