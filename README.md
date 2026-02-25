# A4 Layout

A minimal native macOS app for arranging images on A4 pages and exporting as PDF.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-single%20file-orange)

## Features

- Paste images (⌘V) and freely move/resize them on A4 pages
- Smart snap guides — images snap to edges, centers, and page boundaries with visual alignment lines
- Toggle thin black frame on images (⌘B)
- Multiple pages — add (⌘N) / remove (⌘⇧N) pages, or click the + button
- Export to multi-page PDF (⌘S)
- Responsive — the canvas scales with the window

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
| ⌘B | Toggle frame on selected image |
| ⌘S | Save as PDF |
| ⌘N | Add page |
| ⌘⇧N | Remove last page |
| Delete | Remove selected image |
| ⌘Q | Quit |

## How It Works

One Swift file (`a4layout.swift`), no Xcode project, no dependencies. It uses AppKit for the UI and CoreGraphics for PDF export. Images are stored in A4 coordinate space (595×842 pt) and scaled to the screen, so the layout is resolution-independent.
