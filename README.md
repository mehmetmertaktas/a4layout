# A4 Layout

A minimal native macOS app for arranging images, text, and lines on pages and exporting as PDF.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-single%20file-orange)

## Features

- **Compact toolbar** with all tools visible — no memorizing shortcuts
- **A4 and US Letter** page sizes
- **Paste images** (⌘V) or **drag & drop** from Finder
- **Smart snap guides** — images snap to edges, centers, and page boundaries
- **Center-based resize** — images scale symmetrically from their center
- **Frame options** — multiple colors (black, gray, red, blue) and widths (thin, medium, thick)
- **Text tool** — click to place, double-click to edit
- **Line tool** — click and drag to draw; hold Shift to constrain to horizontal/vertical
- **Rotate images** 90° clockwise (⌘R)
- **Image opacity** slider (5–100%)
- **Background color** — white, light gray, cream, or black
- **Grid overlay** toggle for alignment (⌘G) — not rendered in PDF
- **Undo / Redo** (⌘Z / ⌘⇧Z)
- **Duplicate** any element (⌘D)
- **Arrow key nudge** — 1pt per press, 10pt with Shift
- **Multiple pages** — add/remove pages, continuous scroll
- **Unsaved changes guard** — warns before closing with unsaved work
- **Export to multi-page PDF** (⌘S)

## Install

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/mehmetmertaktas/a4layout.git
cd a4layout
./build.sh
```

This creates **A4 Layout.app** in the current directory. Move it to `/Applications` or double-click to run.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘V | Paste image |
| ⌘D | Duplicate selected element |
| ⌘B | Toggle frame on selected image |
| ⌘R | Rotate image 90° clockwise |
| ⌘G | Toggle grid overlay |
| ⌘Z | Undo |
| ⌘⇧Z | Redo |
| ⌘S | Save as PDF |
| ⌘N | Add page |
| ⌘⇧N | Remove last page |
| ←→↑↓ | Nudge selected element 1pt |
| ⇧ + ←→↑↓ | Nudge selected element 10pt |
| Delete | Remove selected element |
| ⌘Q | Quit |

## How It Works

One Swift file (`a4layout.swift`), no Xcode project, no dependencies. Uses AppKit for the UI and CoreGraphics for PDF export. All elements are stored in page coordinate space (595×842pt for A4, 612×792pt for Letter) and scaled to the screen for resolution-independent layout.
