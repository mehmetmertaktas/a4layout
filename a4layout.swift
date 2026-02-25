import AppKit
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────
// MARK: - Page Size
// ─────────────────────────────────────────────────────────────

enum PageSize: String, CaseIterable {
    case a4     = "A4"
    case letter = "US Letter"
    var width: CGFloat  { self == .a4 ? 595 : 612 }
    var height: CGFloat { self == .a4 ? 842 : 792 }
}

// ─────────────────────────────────────────────────────────────
// MARK: - Canvas Items
// ─────────────────────────────────────────────────────────────

class ImageItem {
    var image: NSImage
    var x: CGFloat
    var y: CGFloat          // continuous: page N starts at N*pageH
    var width: CGFloat
    var height: CGFloat
    var aspectRatio: CGFloat
    var isSelected = false
    var frameColor: NSColor? = nil   // nil = no frame
    var frameWidth: CGFloat = 1
    var opacity: CGFloat = 1.0
    var rotation: Int = 0            // 0, 90, 180, 270

    init(image: NSImage, x: CGFloat, y: CGFloat, width: CGFloat) {
        self.image = image
        self.aspectRatio = image.size.width / image.size.height
        self.x = x; self.y = y
        self.width = width
        self.height = width / self.aspectRatio
    }

    func clone(offsetX: CGFloat = 15, offsetY: CGFloat = 15) -> ImageItem {
        let c = ImageItem(image: image, x: x + offsetX, y: y + offsetY, width: width)
        c.frameColor = frameColor; c.frameWidth = frameWidth
        c.opacity = opacity; c.rotation = rotation
        return c
    }

    func rotated90CW() {
        let newImg = NSImage(size: NSSize(width: image.size.height, height: image.size.width))
        newImg.lockFocus()
        let t = NSAffineTransform()
        t.translateX(by: newImg.size.width / 2, yBy: newImg.size.height / 2)
        t.rotate(byDegrees: -90)
        t.translateX(by: -image.size.width / 2, yBy: -image.size.height / 2)
        t.concat()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        newImg.unlockFocus()
        image = newImg
        rotation = (rotation + 90) % 360
        let cx = x + width / 2, cy = y + height / 2
        aspectRatio = image.size.width / image.size.height
        let newW = height   // swap w/h
        let newH = newW / aspectRatio
        width = newW; height = newH
        x = cx - width / 2; y = cy - height / 2
    }
}

class TextItem {
    var text: String
    var x: CGFloat
    var y: CGFloat
    var fontSize: CGFloat
    var color: NSColor
    var isSelected = false

    init(text: String, x: CGFloat, y: CGFloat, fontSize: CGFloat = 16, color: NSColor = .black) {
        self.text = text; self.x = x; self.y = y
        self.fontSize = fontSize; self.color = color
    }

    func clone(offsetX: CGFloat = 15, offsetY: CGFloat = 15) -> TextItem {
        let c = TextItem(text: text, x: x + offsetX, y: y + offsetY,
                         fontSize: fontSize, color: color)
        return c
    }

    var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: color]
    }

    var size: NSSize { (text as NSString).size(withAttributes: attrs) }
}

class LineItem {
    var x1: CGFloat; var y1: CGFloat
    var x2: CGFloat; var y2: CGFloat
    var color: NSColor
    var lineWidth: CGFloat
    var isSelected = false

    init(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat,
         color: NSColor = .black, lineWidth: CGFloat = 1) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        self.color = color; self.lineWidth = lineWidth
    }

    func clone(offsetX: CGFloat = 15, offsetY: CGFloat = 15) -> LineItem {
        return LineItem(x1: x1 + offsetX, y1: y1 + offsetY,
                        x2: x2 + offsetX, y2: y2 + offsetY,
                        color: color, lineWidth: lineWidth)
    }

    func hitTest(a4Point p: NSPoint, threshold: CGFloat = 5) -> Bool {
        let dx = x2 - x1, dy = y2 - y1
        let len = hypot(dx, dy)
        guard len > 0.1 else { return hypot(p.x - x1, p.y - y1) < threshold }
        let t = max(0, min(1, ((p.x - x1) * dx + (p.y - y1) * dy) / (len * len)))
        let cx = x1 + t * dx, cy = y1 + t * dy
        return hypot(p.x - cx, p.y - cy) < threshold
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - Interaction Mode
// ─────────────────────────────────────────────────────────────

enum InteractionMode {
    case select
    case addText
    case drawLine
}

// ─────────────────────────────────────────────────────────────
// MARK: - Undo Snapshot
// ─────────────────────────────────────────────────────────────

struct UndoSnapshot {
    struct ImgSnap {
        let image: NSImage; let x, y, width, height, aspectRatio, opacity, frameWidth: CGFloat
        let frameColor: NSColor?; let rotation: Int
    }
    struct TxtSnap {
        let text: String; let x, y, fontSize: CGFloat; let color: NSColor
    }
    struct LnSnap {
        let x1, y1, x2, y2, lineWidth: CGFloat; let color: NSColor
    }
    let images: [ImgSnap]
    let texts: [TxtSnap]
    let lines: [LnSnap]
    let numPages: Int
    let pageSize: PageSize
    let bgColor: NSColor
}

// ─────────────────────────────────────────────────────────────
// MARK: - Snap Guides
// ─────────────────────────────────────────────────────────────

enum GuideAxis { case vertical, horizontal }

struct SnapGuide {
    let axis: GuideAxis
    let a4Pos: CGFloat
    let page: Int
}

struct SnapResult {
    var delta: CGFloat = 0
    var positions: [CGFloat] = []
    var snapped: Bool { !positions.isEmpty }
}

func snapAxis(dragEdges: [CGFloat], targetEdges: [CGFloat], threshold: CGFloat) -> SnapResult {
    var bestDist: CGFloat = .greatestFiniteMagnitude
    var bestDelta: CGFloat = 0
    for de in dragEdges {
        for te in targetEdges {
            let d = abs(te - de)
            if d < bestDist && d <= threshold { bestDist = d; bestDelta = te - de }
        }
    }
    guard bestDist <= threshold else { return SnapResult() }
    let adjusted = dragEdges.map { $0 + bestDelta }
    var positions = Set<CGFloat>()
    for te in targetEdges {
        for ae in adjusted { if abs(te - ae) < 0.5 { positions.insert(te); break } }
    }
    return SnapResult(delta: bestDelta, positions: Array(positions))
}

// ─────────────────────────────────────────────────────────────
// MARK: - Document View
// ─────────────────────────────────────────────────────────────

class DocumentView: NSView, NSTextFieldDelegate {
    var images: [ImageItem] = []
    var texts: [TextItem] = []
    var lines: [LineItem] = []

    var selectedImage: ImageItem?
    var selectedText: TextItem?
    var selectedLine: LineItem?

    var numPages = 1
    var pageSize: PageSize = .a4
    var bgColor: NSColor = .white
    var showGrid = false

    var mode: InteractionMode = .select
    var isDirty = false
    var onRelayout: (() -> Void)?
    var onDirtyChanged: (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    // Undo
    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []
    private let maxUndo = 50

    // Drag state
    private var isDragging = false
    private var isResizing = false
    private var isDrawingLine = false
    private var dragStartScreen = NSPoint.zero
    private var itemStartPos = NSPoint.zero
    private var itemStartWidth: CGFloat = 0
    private var itemStartHeight: CGFloat = 0
    private var itemStartCenter = NSPoint.zero
    private var lineStartEnd = NSPoint.zero   // second endpoint for line drag
    private var newLineItem: LineItem?

    // Text editing
    private var editingTextField: NSTextField?
    private var editingTextItem: TextItem?

    private var pasteCount = 0
    private var activeGuides: [SnapGuide] = []

    private let handleR: CGFloat = 5
    let pad: CGFloat = 28
    let gap: CGFloat = 24
    private let addBtnSize: CGFloat = 32
    private let snapThreshold: CGFloat = 5

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var PW: CGFloat { pageSize.width }
    var PH: CGFloat { pageSize.height }

    var pageW: CGFloat { max(100, bounds.width - pad * 2) }
    var scale: CGFloat { pageW / PW }
    var pageH: CGFloat { PH * scale }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError() }

    func totalHeight(forWidth w: CGFloat) -> CGFloat {
        let pw = max(100, w - pad * 2)
        let ph = PH * (pw / PW)
        return pad + CGFloat(numPages) * ph + CGFloat(max(0, numPages - 1)) * gap + pad + addBtnSize + 24
    }

    func pageRect(for i: Int) -> NSRect {
        NSRect(x: pad, y: pad + CGFloat(i) * (pageH + gap), width: pageW, height: pageH)
    }

    var addButtonRect: NSRect {
        let lastPage = pageRect(for: numPages - 1)
        let btnY = lastPage.maxY + gap * 0.5
        return NSRect(x: bounds.midX - addBtnSize / 2, y: btnY, width: addBtnSize, height: addBtnSize)
    }

    // ── Coordinate conversion ──

    func toA4(_ sp: NSPoint) -> NSPoint {
        for i in 0..<numPages {
            let r = pageRect(for: i)
            if sp.y < r.maxY + gap / 2 || i == numPages - 1 {
                let lx = (sp.x - r.minX) / scale
                let ly = (sp.y - r.minY) / scale
                return NSPoint(x: lx, y: CGFloat(i) * PH + ly)
            }
        }
        return .zero
    }

    func toScreen(_ a4: NSPoint) -> NSPoint {
        let pg = min(max(0, Int(a4.y / PH)), numPages - 1)
        let ly = a4.y - CGFloat(pg) * PH
        let r = pageRect(for: pg)
        return NSPoint(x: r.minX + a4.x * scale, y: r.minY + ly * scale)
    }

    func screenFrame(for item: ImageItem) -> NSRect {
        let o = toScreen(NSPoint(x: item.x, y: item.y))
        return NSRect(x: o.x, y: o.y, width: item.width * scale, height: item.height * scale)
    }

    func screenFrame(for item: TextItem) -> NSRect {
        let o = toScreen(NSPoint(x: item.x, y: item.y))
        let sz = item.size
        return NSRect(x: o.x, y: o.y, width: sz.width * scale, height: sz.height * scale)
    }

    // ── Undo / Redo ──

    func pushUndo() {
        let snap = UndoSnapshot(
            images: images.map { .init(image: $0.image, x: $0.x, y: $0.y, width: $0.width,
                                        height: $0.height, aspectRatio: $0.aspectRatio,
                                        opacity: $0.opacity, frameWidth: $0.frameWidth,
                                        frameColor: $0.frameColor, rotation: $0.rotation) },
            texts: texts.map { .init(text: $0.text, x: $0.x, y: $0.y,
                                      fontSize: $0.fontSize, color: $0.color) },
            lines: lines.map { .init(x1: $0.x1, y1: $0.y1, x2: $0.x2, y2: $0.y2,
                                      lineWidth: $0.lineWidth, color: $0.color) },
            numPages: numPages, pageSize: pageSize, bgColor: bgColor
        )
        undoStack.append(snap)
        if undoStack.count > maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restoreSnapshot(_ snap: UndoSnapshot) {
        deselectAll()
        images = snap.images.map { s in
            let it = ImageItem(image: s.image, x: s.x, y: s.y, width: s.width)
            it.height = s.height; it.aspectRatio = s.aspectRatio
            it.opacity = s.opacity; it.frameWidth = s.frameWidth
            it.frameColor = s.frameColor; it.rotation = s.rotation
            return it
        }
        texts = snap.texts.map { TextItem(text: $0.text, x: $0.x, y: $0.y,
                                            fontSize: $0.fontSize, color: $0.color) }
        lines = snap.lines.map { LineItem(x1: $0.x1, y1: $0.y1, x2: $0.x2, y2: $0.y2,
                                            color: $0.color, lineWidth: $0.lineWidth) }
        numPages = snap.numPages; pageSize = snap.pageSize; bgColor = snap.bgColor
        markDirty()
        onRelayout?()
        needsDisplay = true
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        // Push current state to redo
        let cur = UndoSnapshot(
            images: images.map { .init(image: $0.image, x: $0.x, y: $0.y, width: $0.width,
                                        height: $0.height, aspectRatio: $0.aspectRatio,
                                        opacity: $0.opacity, frameWidth: $0.frameWidth,
                                        frameColor: $0.frameColor, rotation: $0.rotation) },
            texts: texts.map { .init(text: $0.text, x: $0.x, y: $0.y,
                                      fontSize: $0.fontSize, color: $0.color) },
            lines: lines.map { .init(x1: $0.x1, y1: $0.y1, x2: $0.x2, y2: $0.y2,
                                      lineWidth: $0.lineWidth, color: $0.color) },
            numPages: numPages, pageSize: pageSize, bgColor: bgColor
        )
        redoStack.append(cur)
        restoreSnapshot(snap)
    }

    func redo() {
        guard let snap = redoStack.popLast() else { return }
        let cur = UndoSnapshot(
            images: images.map { .init(image: $0.image, x: $0.x, y: $0.y, width: $0.width,
                                        height: $0.height, aspectRatio: $0.aspectRatio,
                                        opacity: $0.opacity, frameWidth: $0.frameWidth,
                                        frameColor: $0.frameColor, rotation: $0.rotation) },
            texts: texts.map { .init(text: $0.text, x: $0.x, y: $0.y,
                                      fontSize: $0.fontSize, color: $0.color) },
            lines: lines.map { .init(x1: $0.x1, y1: $0.y1, x2: $0.x2, y2: $0.y2,
                                      lineWidth: $0.lineWidth, color: $0.color) },
            numPages: numPages, pageSize: pageSize, bgColor: bgColor
        )
        undoStack.append(cur)
        restoreSnapshot(snap)
    }

    // ── Dirty ──

    func markDirty() {
        isDirty = true
        onDirtyChanged?()
    }

    func clearDirty() {
        isDirty = false
        onDirtyChanged?()
    }

    // ── Selection ──

    func deselectAll() {
        selectedImage?.isSelected = false; selectedImage = nil
        selectedText?.isSelected = false; selectedText = nil
        selectedLine?.isSelected = false; selectedLine = nil
        activeGuides = []
        onSelectionChanged?()
    }

    func selectImage(_ item: ImageItem?) {
        deselectAll()
        selectedImage = item
        item?.isSelected = true
        onSelectionChanged?()
        needsDisplay = true
    }

    func selectText(_ item: TextItem?) {
        deselectAll()
        selectedText = item
        item?.isSelected = true
        onSelectionChanged?()
        needsDisplay = true
    }

    func selectLine(_ item: LineItem?) {
        deselectAll()
        selectedLine = item
        item?.isSelected = true
        onSelectionChanged?()
        needsDisplay = true
    }

    // ── Snap computation ──

    let guideColor = NSColor(red: 1, green: 0.22, blue: 0.38, alpha: 0.85)

    func computeSnaps(for item: ImageItem) -> (dx: CGFloat, dy: CGFloat, guides: [SnapGuide]) {
        let page = min(max(0, Int(item.y / PH)), numPages - 1)
        let localY = item.y - CGFloat(page) * PH
        let dxEdges = [item.x, item.x + item.width / 2, item.x + item.width]
        let dyEdges = [localY, localY + item.height / 2, localY + item.height]
        var txEdges: [CGFloat] = [0, PW / 2, PW]
        var tyEdges: [CGFloat] = [0, PH / 2, PH]
        for other in images where other !== item {
            let op = min(max(0, Int(other.y / PH)), numPages - 1)
            guard op == page else { continue }
            let oly = other.y - CGFloat(op) * PH
            txEdges.append(contentsOf: [other.x, other.x + other.width / 2, other.x + other.width])
            tyEdges.append(contentsOf: [oly, oly + other.height / 2, oly + other.height])
        }
        let sx = snapAxis(dragEdges: dxEdges, targetEdges: txEdges, threshold: snapThreshold)
        let sy = snapAxis(dragEdges: dyEdges, targetEdges: tyEdges, threshold: snapThreshold)
        var guides: [SnapGuide] = []
        for pos in sx.positions { guides.append(SnapGuide(axis: .vertical, a4Pos: pos, page: page)) }
        for pos in sy.positions { guides.append(SnapGuide(axis: .horizontal, a4Pos: pos, page: page)) }
        return (sx.snapped ? sx.delta : 0, sy.snapped ? sy.delta : 0, guides)
    }

    // ── Drawing ──

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.91, alpha: 1).setFill()
        dirtyRect.fill()

        for i in 0..<numPages {
            let r = pageRect(for: i)
            guard dirtyRect.intersects(r.insetBy(dx: -16, dy: -16)) else { continue }

            // Shadow + page bg
            NSGraphicsContext.saveGraphicsState()
            let shd = NSShadow()
            shd.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shd.shadowOffset = NSSize(width: 0, height: -1)
            shd.shadowBlurRadius = 8
            shd.set()
            bgColor.setFill()
            r.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Clip to page
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: r).setClip()

            // Grid overlay (before items)
            if showGrid {
                let gridSpacing: CGFloat = 50  // A4 points
                NSColor(white: 0.75, alpha: 0.35).setStroke()
                let gp = NSBezierPath()
                gp.lineWidth = 0.25
                let pattern: [CGFloat] = [4, 4]
                gp.setLineDash(pattern, count: 2, phase: 0)
                var gx: CGFloat = gridSpacing
                while gx < PW {
                    let sx = r.minX + gx * scale
                    gp.move(to: NSPoint(x: sx, y: r.minY))
                    gp.line(to: NSPoint(x: sx, y: r.maxY))
                    gx += gridSpacing
                }
                var gy: CGFloat = gridSpacing
                while gy < PH {
                    let sy = r.minY + gy * scale
                    gp.move(to: NSPoint(x: r.minX, y: sy))
                    gp.line(to: NSPoint(x: r.maxX, y: sy))
                    gy += gridSpacing
                }
                gp.stroke()
            }

            // Hint on first page when empty
            if i == 0 && images.isEmpty && texts.isEmpty && lines.isEmpty {
                let hintAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor(white: 0.72, alpha: 1),
                    .font: NSFont.systemFont(ofSize: 15, weight: .light)
                ]
                let hintText = "Paste an image  \u{2318}V  or drag from Finder" as NSString
                let sz = hintText.size(withAttributes: hintAttrs)
                hintText.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2),
                              withAttributes: hintAttrs)
            }

            let pageTop = CGFloat(i) * PH
            let pageBot = pageTop + PH

            // Draw lines
            for item in lines {
                let minY = min(item.y1, item.y2), maxY = max(item.y1, item.y2)
                guard maxY > pageTop && minY < pageBot else { continue }
                let p1 = toScreen(NSPoint(x: item.x1, y: item.y1))
                let p2 = toScreen(NSPoint(x: item.x2, y: item.y2))
                item.color.setStroke()
                let path = NSBezierPath()
                path.lineWidth = item.lineWidth * scale
                path.move(to: p1); path.line(to: p2)
                path.stroke()

                if item.isSelected {
                    NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
                    let sp = NSBezierPath()
                    sp.lineWidth = max(1, item.lineWidth * scale + 2)
                    sp.move(to: p1); sp.line(to: p2)
                    sp.stroke()
                    // Endpoint dots
                    for ep in [p1, p2] {
                        let dr: CGFloat = 4
                        NSColor.controlAccentColor.setFill()
                        NSBezierPath(ovalIn: NSRect(x: ep.x - dr, y: ep.y - dr, width: dr * 2, height: dr * 2)).fill()
                    }
                }
            }

            // Draw images
            for item in images {
                guard item.y + item.height > pageTop && item.y < pageBot else { continue }
                let f = screenFrame(for: item)
                item.image.draw(in: f, from: .zero, operation: .sourceOver, fraction: item.opacity)

                if let fc = item.frameColor {
                    fc.setStroke()
                    let bezel = NSBezierPath(rect: f)
                    bezel.lineWidth = max(0.5, item.frameWidth * scale)
                    bezel.stroke()
                }

                if item.isSelected {
                    NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
                    let border = NSBezierPath(rect: f.insetBy(dx: -1, dy: -1))
                    border.lineWidth = 1.5
                    border.stroke()
                    // Resize handle
                    let c = NSPoint(x: f.maxX, y: f.maxY)
                    let ov = NSRect(x: c.x - handleR, y: c.y - handleR,
                                    width: handleR * 2, height: handleR * 2)
                    NSColor.controlAccentColor.setFill()
                    NSBezierPath(ovalIn: ov).fill()
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: ov.insetBy(dx: 1.5, dy: 1.5)).fill()
                }
            }

            // Draw texts
            for item in texts {
                let sz = item.size
                guard item.y + sz.height > pageTop && item.y < pageBot else { continue }
                let o = toScreen(NSPoint(x: item.x, y: item.y))
                let drawRect = NSRect(x: o.x, y: o.y, width: sz.width * scale, height: sz.height * scale)

                // Scale the font for screen rendering
                let scaledAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: item.fontSize * scale),
                    .foregroundColor: item.color
                ]
                (item.text as NSString).draw(at: NSPoint(x: o.x, y: o.y), withAttributes: scaledAttrs)

                if item.isSelected {
                    NSColor.controlAccentColor.withAlphaComponent(0.3).setStroke()
                    let border = NSBezierPath(rect: drawRect.insetBy(dx: -2, dy: -2))
                    border.lineWidth = 1
                    let dashPattern: [CGFloat] = [3, 3]
                    border.setLineDash(dashPattern, count: 2, phase: 0)
                    border.stroke()
                }
            }

            // Snap guide lines
            for guide in activeGuides where guide.page == i {
                guideColor.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 0.75
                if guide.axis == .vertical {
                    let sx = r.minX + guide.a4Pos * scale
                    path.move(to: NSPoint(x: sx, y: r.minY))
                    path.line(to: NSPoint(x: sx, y: r.maxY))
                } else {
                    let sy = r.minY + guide.a4Pos * scale
                    path.move(to: NSPoint(x: r.minX, y: sy))
                    path.line(to: NSPoint(x: r.maxX, y: sy))
                }
                path.stroke()
            }

            // Page number
            let num = "\(i + 1)" as NSString
            let numAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(white: 0.78, alpha: 1),
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            ]
            let nsz = num.size(withAttributes: numAttrs)
            num.draw(at: NSPoint(x: r.midX - nsz.width / 2, y: r.maxY - nsz.height - 8),
                     withAttributes: numAttrs)

            NSGraphicsContext.restoreGraphicsState()
        }

        // "+" button
        let btnR = addButtonRect
        if dirtyRect.intersects(btnR.insetBy(dx: -8, dy: -8)) {
            NSColor(white: 0.82, alpha: 1).setStroke()
            let circle = NSBezierPath(ovalIn: btnR.insetBy(dx: 2, dy: 2))
            circle.lineWidth = 1.5; circle.stroke()
            let plus = "+" as NSString
            let pAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(white: 0.62, alpha: 1),
                .font: NSFont.systemFont(ofSize: 18, weight: .light)
            ]
            let psz = plus.size(withAttributes: pAttrs)
            plus.draw(at: NSPoint(x: btnR.midX - psz.width / 2, y: btnR.midY - psz.height / 2),
                      withAttributes: pAttrs)
        }

        // Line being drawn
        if isDrawingLine, let nl = newLineItem {
            let p1 = toScreen(NSPoint(x: nl.x1, y: nl.y1))
            let p2 = toScreen(NSPoint(x: nl.x2, y: nl.y2))
            nl.color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = nl.lineWidth * scale
            path.move(to: p1); path.line(to: p2)
            path.stroke()
        }
    }

    // ── Hit testing ──

    private func hitImage(at a4: NSPoint) -> ImageItem? {
        for item in images.reversed() {
            if NSRect(x: item.x, y: item.y, width: item.width, height: item.height).contains(a4) {
                return item
            }
        }
        return nil
    }

    private func hitText(at a4: NSPoint) -> TextItem? {
        for item in texts.reversed() {
            let sz = item.size
            if NSRect(x: item.x, y: item.y, width: sz.width, height: sz.height).contains(a4) {
                return item
            }
        }
        return nil
    }

    private func hitLine(at a4: NSPoint) -> LineItem? {
        for item in lines.reversed() {
            if item.hitTest(a4Point: a4) { return item }
        }
        return nil
    }

    private func isOnHandle(screen sp: NSPoint, item: ImageItem) -> Bool {
        let f = screenFrame(for: item)
        return hypot(sp.x - f.maxX, sp.y - f.maxY) < handleR + 6
    }

    // ── Mouse events ──

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitTextEditing()
        let sp = convert(event.locationInWindow, from: nil)

        // "+" button
        if addButtonRect.insetBy(dx: -4, dy: -4).contains(sp) {
            pushUndo(); addPage(); onRelayout?()
            DispatchQueue.main.async { [self] in scrollToVisible(pageRect(for: numPages - 1)) }
            return
        }

        let a4 = toA4(sp)

        switch mode {
        case .addText:
            pushUndo()
            let item = TextItem(text: "Text", x: a4.x, y: a4.y)
            texts.append(item)
            selectText(item)
            markDirty()
            mode = .select
            // Start editing immediately
            beginTextEditing(item)
            return

        case .drawLine:
            isDrawingLine = true
            let nl = LineItem(x1: a4.x, y1: a4.y, x2: a4.x, y2: a4.y)
            newLineItem = nl
            dragStartScreen = sp
            return

        case .select:
            break
        }

        // Select mode: check resize handle, then hit test
        if let item = selectedImage, isOnHandle(screen: sp, item: item) {
            pushUndo()
            isResizing = true
            dragStartScreen = sp
            itemStartWidth = item.width
            itemStartHeight = item.height
            itemStartCenter = NSPoint(x: item.x + item.width / 2, y: item.y + item.height / 2)
        } else if let hit = hitImage(at: a4) {
            pushUndo()
            selectImage(hit)
            isDragging = true
            dragStartScreen = sp
            itemStartPos = NSPoint(x: hit.x, y: hit.y)
        } else if let hit = hitText(at: a4) {
            if hit === selectedText && event.clickCount == 2 {
                beginTextEditing(hit)
            } else {
                pushUndo()
                selectText(hit)
                isDragging = true
                dragStartScreen = sp
                itemStartPos = NSPoint(x: hit.x, y: hit.y)
            }
        } else if let hit = hitLine(at: a4) {
            pushUndo()
            selectLine(hit)
            isDragging = true
            dragStartScreen = sp
            itemStartPos = NSPoint(x: hit.x1, y: hit.y1)
            lineStartEnd = NSPoint(x: hit.x2, y: hit.y2)
        } else {
            deselectAll()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let sp = convert(event.locationInWindow, from: nil)
        let dx = (sp.x - dragStartScreen.x) / scale
        let dy = (sp.y - dragStartScreen.y) / scale

        if isDrawingLine, let nl = newLineItem {
            var a4 = toA4(sp)
            // Shift constrains to H/V
            if event.modifierFlags.contains(.shift) {
                let adx = abs(a4.x - nl.x1), ady = abs(a4.y - nl.y1)
                if adx > ady { a4.y = nl.y1 } else { a4.x = nl.x1 }
            }
            nl.x2 = a4.x; nl.y2 = a4.y
            needsDisplay = true
            return
        }

        if isResizing, let item = selectedImage {
            let newW = max(20, itemStartWidth + dx)
            let newH = newW / item.aspectRatio
            item.width = newW; item.height = newH
            item.x = itemStartCenter.x - newW / 2
            item.y = itemStartCenter.y - newH / 2
            activeGuides = []
            markDirty()
            needsDisplay = true
        } else if isDragging {
            if let item = selectedImage {
                item.x = itemStartPos.x + dx
                item.y = itemStartPos.y + dy
                let (sdx, sdy, guides) = computeSnaps(for: item)
                item.x += sdx; item.y += sdy
                activeGuides = guides
                markDirty()
            } else if let item = selectedText {
                item.x = itemStartPos.x + dx
                item.y = itemStartPos.y + dy
                markDirty()
            } else if let item = selectedLine {
                item.x1 = itemStartPos.x + dx
                item.y1 = itemStartPos.y + dy
                item.x2 = lineStartEnd.x + dx
                item.y2 = lineStartEnd.y + dy
                markDirty()
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDrawingLine, let nl = newLineItem {
            let len = hypot(nl.x2 - nl.x1, nl.y2 - nl.y1)
            if len > 2 {
                pushUndo()
                lines.append(nl)
                selectLine(nl)
                markDirty()
            }
            isDrawingLine = false
            newLineItem = nil
            mode = .select
            needsDisplay = true
            return
        }
        isDragging = false
        isResizing = false
        activeGuides = []
        needsDisplay = true
    }

    // ── Keyboard ──

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)
        let nudge: CGFloat = shift ? 10 : 1

        switch event.keyCode {
        case 123: // Left
            nudgeSelected(dx: -nudge, dy: 0)
        case 124: // Right
            nudgeSelected(dx: nudge, dy: 0)
        case 125: // Down
            nudgeSelected(dx: 0, dy: nudge)
        case 126: // Up
            nudgeSelected(dx: 0, dy: -nudge)
        case 51: // Delete
            if !cmd { deleteSelected() }
        default:
            super.keyDown(with: event)
        }
    }

    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        if let item = selectedImage {
            pushUndo(); item.x += dx; item.y += dy; markDirty(); needsDisplay = true
        } else if let item = selectedText {
            pushUndo(); item.x += dx; item.y += dy; markDirty(); needsDisplay = true
        } else if let item = selectedLine {
            pushUndo()
            item.x1 += dx; item.y1 += dy; item.x2 += dx; item.y2 += dy
            markDirty(); needsDisplay = true
        }
    }

    // ── Text editing ──

    func beginTextEditing(_ item: TextItem) {
        commitTextEditing()
        editingTextItem = item
        let o = toScreen(NSPoint(x: item.x, y: item.y))
        let sz = item.size
        let field = NSTextField(frame: NSRect(x: o.x, y: o.y,
                                              width: max(100, sz.width * scale + 20),
                                              height: max(24, sz.height * scale + 4)))
        field.stringValue = item.text
        field.font = NSFont.systemFont(ofSize: item.fontSize * scale)
        field.textColor = item.color
        field.isBordered = true
        field.isEditable = true
        field.backgroundColor = .white
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldAction(_:))
        addSubview(field)
        field.selectText(nil)
        editingTextField = field
    }

    @objc func textFieldAction(_ sender: NSTextField) {
        commitTextEditing()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditing()
    }

    func commitTextEditing() {
        guard let field = editingTextField, let item = editingTextItem else { return }
        let newText = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if newText.isEmpty {
            pushUndo()
            texts.removeAll { $0 === item }
            deselectAll()
        } else if newText != item.text {
            pushUndo()
            item.text = newText
        }
        field.removeFromSuperview()
        editingTextField = nil
        editingTextItem = nil
        markDirty()
        needsDisplay = true
    }

    // ── Drag & drop from Finder ──

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingContentsConformToTypes: NSImage.imageTypes]) as? [URL] else {
            // Try pasteboard image directly
            if let img = NSImage(pasteboard: sender.draggingPasteboard) {
                let sp = convert(sender.draggingLocation, from: nil)
                let a4 = toA4(sp)
                pushUndo()
                var w = img.size.width
                if w > PW * 0.6 { w = PW * 0.6 }
                let item = ImageItem(image: img, x: a4.x - w / 2, y: a4.y, width: w)
                images.append(item)
                selectImage(item)
                markDirty()
                return true
            }
            return false
        }
        let sp = convert(sender.draggingLocation, from: nil)
        let a4 = toA4(sp)
        pushUndo()
        var offset: CGFloat = 0
        for url in items {
            guard let img = NSImage(contentsOf: url) else { continue }
            var w = img.size.width
            if w > PW * 0.6 { w = PW * 0.6 }
            let item = ImageItem(image: img, x: a4.x - w / 2 + offset, y: a4.y + offset, width: w)
            images.append(item)
            selectImage(item)
            offset += 15
        }
        markDirty()
        return true
    }

    // ── Actions ──

    func visiblePage() -> Int {
        guard let sv = enclosingScrollView else { return 0 }
        let mid = sv.contentView.bounds.midY
        var best = 0, bestD: CGFloat = .greatestFiniteMagnitude
        for i in 0..<numPages {
            let d = abs(pageRect(for: i).midY - mid)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    func pasteImage() {
        guard let image = NSImage(pasteboard: .general) else { return }
        pushUndo()
        var w = image.size.width
        if w > PW * 0.6 { w = PW * 0.6 }
        let pg = visiblePage()
        let off = CGFloat(pasteCount % 5) * 18
        let item = ImageItem(image: image,
                             x: (PW - w) / 2 + off,
                             y: CGFloat(pg) * PH + 80 + off,
                             width: w)
        images.append(item)
        pasteCount += 1
        selectImage(item)
        markDirty()
    }

    func addPage() {
        numPages += 1
        markDirty()
    }

    func removePage() {
        guard numPages > 1 else { return }
        pushUndo()
        let top = CGFloat(numPages - 1) * PH
        images.removeAll { $0.y >= top }
        texts.removeAll { $0.y >= top }
        lines.removeAll { min($0.y1, $0.y2) >= top }
        deselectAll()
        numPages -= 1
        markDirty()
    }

    func deleteSelected() {
        if let item = selectedImage {
            pushUndo()
            images.removeAll { $0 === item }
            deselectAll()
            markDirty()
        } else if let item = selectedText {
            pushUndo()
            texts.removeAll { $0 === item }
            deselectAll()
            markDirty()
        } else if let item = selectedLine {
            pushUndo()
            lines.removeAll { $0 === item }
            deselectAll()
            markDirty()
        }
        needsDisplay = true
    }

    func duplicateSelected() {
        if let item = selectedImage {
            pushUndo()
            let dup = item.clone()
            images.append(dup)
            selectImage(dup)
            markDirty()
        } else if let item = selectedText {
            pushUndo()
            let dup = item.clone()
            texts.append(dup)
            selectText(dup)
            markDirty()
        } else if let item = selectedLine {
            pushUndo()
            let dup = item.clone()
            lines.append(dup)
            selectLine(dup)
            markDirty()
        }
    }

    func rotateSelected() {
        guard let item = selectedImage else { return }
        pushUndo()
        item.rotated90CW()
        markDirty()
        needsDisplay = true
    }

    func setSelectedOpacity(_ val: CGFloat) {
        guard let item = selectedImage else { return }
        pushUndo()
        item.opacity = val
        markDirty()
        needsDisplay = true
    }

    func setSelectedFrameColor(_ color: NSColor?) {
        guard let item = selectedImage else { return }
        pushUndo()
        item.frameColor = color
        markDirty()
        needsDisplay = true
    }

    func setSelectedFrameWidth(_ w: CGFloat) {
        guard let item = selectedImage else { return }
        pushUndo()
        item.frameWidth = w
        markDirty()
        needsDisplay = true
    }

    func toggleFrame() {
        guard let item = selectedImage else { return }
        pushUndo()
        if item.frameColor != nil {
            item.frameColor = nil
        } else {
            item.frameColor = .black
            item.frameWidth = 1
        }
        markDirty()
        needsDisplay = true
    }

    func changePageSize(_ newSize: PageSize) {
        guard newSize != pageSize else { return }
        pushUndo()
        pageSize = newSize
        markDirty()
        onRelayout?()
        needsDisplay = true
    }

    func changeBgColor(_ color: NSColor) {
        guard color != bgColor else { return }
        pushUndo()
        bgColor = color
        markDirty()
        needsDisplay = true
    }

    func toggleGrid() {
        showGrid.toggle()
        needsDisplay = true
    }

    // ── PDF Export ──

    func exportPDF() {
        deselectAll()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "layout.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let pdfData = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: PW, height: PH)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }

        for pg in 0..<numPages {
            ctx.beginPDFPage(nil)
            ctx.translateBy(x: 0, y: PH)
            ctx.scaleBy(x: 1, y: -1)

            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            NSBezierPath(rect: NSRect(x: 0, y: 0, width: PW, height: PH)).setClip()
            bgColor.setFill()
            NSRect(x: 0, y: 0, width: PW, height: PH).fill()

            let top = CGFloat(pg) * PH

            // Lines
            for item in lines {
                let minY = min(item.y1, item.y2), maxY = max(item.y1, item.y2)
                guard maxY > top && minY < top + PH else { continue }
                item.color.setStroke()
                let path = NSBezierPath()
                path.lineWidth = item.lineWidth
                path.move(to: NSPoint(x: item.x1, y: item.y1 - top))
                path.line(to: NSPoint(x: item.x2, y: item.y2 - top))
                path.stroke()
            }

            // Images
            for item in images {
                guard item.y + item.height > top && item.y < top + PH else { continue }
                let rect = NSRect(x: item.x, y: item.y - top,
                                  width: item.width, height: item.height)
                item.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: item.opacity)

                if let fc = item.frameColor {
                    fc.setStroke()
                    let bezel = NSBezierPath(rect: rect)
                    bezel.lineWidth = item.frameWidth
                    bezel.stroke()
                }
            }

            // Texts
            for item in texts {
                let sz = item.size
                guard item.y + sz.height > top && item.y < top + PH else { continue }
                (item.text as NSString).draw(at: NSPoint(x: item.x, y: item.y - top),
                                              withAttributes: item.attrs)
            }

            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }

        ctx.closePDF()
        try? pdfData.write(to: url)
        clearDirty()
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - App Delegate
// ─────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var scrollView: NSScrollView!
    var doc: DocumentView!

    // Toolbar controls
    var pageSizePopup: NSPopUpButton!
    var bgPopup: NSPopUpButton!
    var framePopup: NSPopUpButton!
    var frameWidthPopup: NSPopUpButton!
    var opacitySlider: NSSlider!
    var opacityLabel: NSTextField!
    var gridBtn: NSButton!
    var textModeBtn: NSButton!
    var lineModeBtn: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        doc = DocumentView(frame: .zero)
        doc.onRelayout = { [weak self] in self?.relayout() }
        doc.onDirtyChanged = { [weak self] in
            self?.window.isDocumentEdited = self?.doc.isDirty ?? false
        }
        doc.onSelectionChanged = { [weak self] in self?.updateToolbarForSelection() }

        scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = doc
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.91, alpha: 1)

        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(relayout),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)

        // Build toolbar + scrollview container
        let toolbar = buildToolbar()
        let sep = NSBox(frame: .zero)
        sep.boxType = .separator

        let stack = NSStackView(views: [toolbar, sep, scrollView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.setHuggingPriority(.defaultHigh, for: .vertical)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        sep.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Constraints
        NSLayoutConstraint.activate([
            toolbar.heightAnchor.constraint(equalToConstant: 40),
            toolbar.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            sep.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            scrollView.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 880),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "A4 Layout"
        window.contentView = stack
        window.minSize = NSSize(width: 380, height: 500)
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        setupMenus()
        relayout()
        updateToolbarForSelection()
    }

    // ── Toolbar ──

    func buildToolbar() -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 40))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let scroll = NSScrollView(frame: .zero)
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        stack.alignment = .centerY
        scroll.documentView = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.heightAnchor),
        ])

        // ── Page setup group ──
        pageSizePopup = makePopup(["A4", "US Letter"], action: #selector(pageSizeChanged(_:)))
        stack.addArrangedSubview(makeLabel("Page:"))
        stack.addArrangedSubview(pageSizePopup)

        bgPopup = makePopup(["White BG", "Gray BG", "Cream BG", "Black BG"],
                             action: #selector(bgColorChanged(_:)))
        stack.addArrangedSubview(bgPopup)

        stack.addArrangedSubview(makeDivider())

        // ── Insert group ──
        let pasteBtn = makeIconBtn("doc.on.clipboard", label: "Paste",
                                    action: #selector(pasteImage))
        stack.addArrangedSubview(pasteBtn)

        textModeBtn = makeIconBtn("textformat", label: "Text",
                                   action: #selector(enterTextMode))
        stack.addArrangedSubview(textModeBtn)

        lineModeBtn = makeIconBtn("line.diagonal", label: "Line",
                                   action: #selector(enterLineMode))
        stack.addArrangedSubview(lineModeBtn)

        stack.addArrangedSubview(makeDivider())

        // ── Image properties group ──
        stack.addArrangedSubview(makeLabel("Frame:"))
        framePopup = makePopup(["None", "Black", "Gray", "Red", "Blue"],
                                action: #selector(frameChanged(_:)))
        stack.addArrangedSubview(framePopup)

        frameWidthPopup = makePopup(["0.5pt", "1pt", "2pt"],
                                     action: #selector(frameWidthChanged(_:)))
        frameWidthPopup.selectItem(at: 1)
        stack.addArrangedSubview(frameWidthPopup)

        let rotateBtn = makeIconBtn("rotate.right", label: "Rotate",
                                     action: #selector(rotateImage))
        stack.addArrangedSubview(rotateBtn)

        stack.addArrangedSubview(makeDivider())

        // ── Opacity ──
        stack.addArrangedSubview(makeLabel("Opacity:"))
        opacitySlider = NSSlider(value: 1.0, minValue: 0.05, maxValue: 1.0,
                                  target: self, action: #selector(opacityChanged(_:)))
        opacitySlider.controlSize = .small
        opacitySlider.widthAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(opacitySlider)
        opacityLabel = NSTextField(labelWithString: "100%")
        opacityLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        opacityLabel.textColor = .secondaryLabelColor
        opacityLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true
        stack.addArrangedSubview(opacityLabel)

        stack.addArrangedSubview(makeDivider())

        // ── View group ──
        gridBtn = makeIconBtn("grid", label: "Grid", action: #selector(toggleGrid))
        gridBtn.setButtonType(.toggle)
        stack.addArrangedSubview(gridBtn)

        stack.addArrangedSubview(makeDivider())

        // ── Pages ──
        let addPgBtn = makeIconBtn("plus.rectangle", label: "Page",
                                    action: #selector(addPage))
        let rmPgBtn = makeIconBtn("minus.rectangle", label: "Page",
                                   action: #selector(removePage))
        stack.addArrangedSubview(addPgBtn)
        stack.addArrangedSubview(rmPgBtn)

        stack.addArrangedSubview(makeDivider())

        // ── Save ──
        let saveBtn = makeIconBtn("square.and.arrow.down", label: "PDF",
                                   action: #selector(savePDF))
        stack.addArrangedSubview(saveBtn)

        return bar
    }

    func makeIconBtn(_ symbolName: String, label: String, action: Selector) -> NSButton {
        let btn: NSButton
        if let img = NSImage(systemSymbolName: symbolName,
                              accessibilityDescription: label) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let styled = img.withSymbolConfiguration(config) ?? img
            btn = NSButton(title: " \(label)", image: styled, target: self, action: action)
            btn.imagePosition = .imageLeading
        } else {
            btn = NSButton(title: label, target: self, action: action)
        }
        btn.controlSize = .small
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 11)
        btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return btn
    }

    func makePopup(_ items: [String], action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: 11)
        for title in items { popup.addItem(withTitle: title) }
        popup.target = self; popup.action = action
        popup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return popup
    }

    func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }

    func makeDivider() -> NSView {
        let div = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 24))
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.separatorColor.cgColor
        div.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            div.widthAnchor.constraint(equalToConstant: 1),
            div.heightAnchor.constraint(equalToConstant: 24),
        ])
        return div
    }

    func updateToolbarForSelection() {
        let hasImg = doc.selectedImage != nil
        framePopup.isEnabled = hasImg
        frameWidthPopup.isEnabled = hasImg
        opacitySlider.isEnabled = hasImg

        // Highlight active mode
        textModeBtn.state = doc.mode == .addText ? .on : .off
        lineModeBtn.state = doc.mode == .drawLine ? .on : .off

        if let item = doc.selectedImage {
            opacitySlider.doubleValue = Double(item.opacity)
            opacityLabel.stringValue = "\(Int(item.opacity * 100))%"
            if let fc = item.frameColor {
                if fc == .black { framePopup.selectItem(at: 1) }
                else if fc == NSColor.darkGray { framePopup.selectItem(at: 2) }
                else if fc == .red { framePopup.selectItem(at: 3) }
                else if fc == .blue { framePopup.selectItem(at: 4) }
                else { framePopup.selectItem(at: 1) }
            } else {
                framePopup.selectItem(at: 0)
            }
            if item.frameWidth <= 0.5 { frameWidthPopup.selectItem(at: 0) }
            else if item.frameWidth <= 1 { frameWidthPopup.selectItem(at: 1) }
            else { frameWidthPopup.selectItem(at: 2) }
        } else {
            opacitySlider.doubleValue = 1.0
            opacityLabel.stringValue = "100%"
        }
    }

    // ── Toolbar Actions ──

    @objc func pageSizeChanged(_ sender: NSPopUpButton) {
        let ps = PageSize.allCases[sender.indexOfSelectedItem]
        doc.changePageSize(ps)
    }

    @objc func bgColorChanged(_ sender: NSPopUpButton) {
        let colors: [NSColor] = [.white, NSColor(white: 0.93, alpha: 1),
                                  NSColor(red: 1, green: 0.98, blue: 0.94, alpha: 1), .black]
        doc.changeBgColor(colors[sender.indexOfSelectedItem])
    }

    @objc func frameChanged(_ sender: NSPopUpButton) {
        let colors: [NSColor?] = [nil, .black, .darkGray, .red, .blue]
        doc.setSelectedFrameColor(colors[sender.indexOfSelectedItem])
    }

    @objc func frameWidthChanged(_ sender: NSPopUpButton) {
        let widths: [CGFloat] = [0.5, 1, 2]
        doc.setSelectedFrameWidth(widths[sender.indexOfSelectedItem])
    }

    @objc func rotateImage() { doc.rotateSelected() }

    @objc func opacityChanged(_ sender: NSSlider) {
        let val = CGFloat(sender.doubleValue)
        opacityLabel.stringValue = "\(Int(val * 100))%"
        doc.setSelectedOpacity(val)
    }

    @objc func toggleGrid() {
        doc.toggleGrid()
        gridBtn.state = doc.showGrid ? .on : .off
        updateToolbarForSelection()
    }

    @objc func enterTextMode() {
        doc.mode = doc.mode == .addText ? .select : .addText
        updateToolbarForSelection()
    }

    @objc func enterLineMode() {
        doc.mode = doc.mode == .drawLine ? .select : .drawLine
        updateToolbarForSelection()
    }

    // ── Layout ──

    @objc func relayout() {
        let w = scrollView.contentView.bounds.width
        let h = max(doc.totalHeight(forWidth: w), scrollView.contentView.bounds.height)
        doc.setFrameSize(NSSize(width: w, height: h))
        doc.needsDisplay = true
    }

    // ── Menu ──

    func setupMenus() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About A4 Layout", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit A4 Layout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        let save = NSMenuItem(title: "Save as PDF\u{2026}", action: #selector(savePDF), keyEquivalent: "s")
        save.target = self
        fileMenu.addItem(save)
        fileMenu.addItem(NSMenuItem.separator())
        let newPg = NSMenuItem(title: "New Page", action: #selector(addPage), keyEquivalent: "n")
        newPg.target = self; fileMenu.addItem(newPg)
        let rmPg = NSMenuItem(title: "Remove Last Page", action: #selector(removePage), keyEquivalent: "n")
        rmPg.target = self; rmPg.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(rmPg)
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        let undoItem = NSMenuItem(title: "Undo", action: #selector(doUndo), keyEquivalent: "z")
        undoItem.target = self; editMenu.addItem(undoItem)
        let redoItem = NSMenuItem(title: "Redo", action: #selector(doRedo), keyEquivalent: "z")
        redoItem.target = self; redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        let paste = NSMenuItem(title: "Paste", action: #selector(pasteImage), keyEquivalent: "v")
        paste.target = self; editMenu.addItem(paste)
        let dup = NSMenuItem(title: "Duplicate", action: #selector(duplicateSelected), keyEquivalent: "d")
        dup.target = self; editMenu.addItem(dup)
        let del = NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: "\u{8}")
        del.target = self; del.keyEquivalentModifierMask = []; editMenu.addItem(del)
        editMenu.addItem(NSMenuItem.separator())
        let frame = NSMenuItem(title: "Toggle Frame", action: #selector(toggleFrame), keyEquivalent: "b")
        frame.target = self; editMenu.addItem(frame)
        let rotate = NSMenuItem(title: "Rotate 90° CW", action: #selector(rotateImage), keyEquivalent: "r")
        rotate.target = self; editMenu.addItem(rotate)
        let grid = NSMenuItem(title: "Toggle Grid", action: #selector(toggleGrid), keyEquivalent: "g")
        grid.target = self; editMenu.addItem(grid)
        let editItem = NSMenuItem(); editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    // ── Menu actions ──

    @objc func pasteImage() { doc.pasteImage() }
    @objc func savePDF() { doc.exportPDF() }
    @objc func deleteSelected() { doc.deleteSelected() }
    @objc func toggleFrame() { doc.toggleFrame() }
    @objc func duplicateSelected() { doc.duplicateSelected() }
    @objc func doUndo() { doc.undo() }
    @objc func doRedo() { doc.redo() }

    @objc func addPage() {
        doc.pushUndo(); doc.addPage(); relayout()
        DispatchQueue.main.async { [self] in
            doc.scrollToVisible(doc.pageRect(for: doc.numPages - 1))
        }
    }

    @objc func removePage() { doc.removePage(); relayout() }

    // ── Window delegate (unsaved changes) ──

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard doc.isDirty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes."
        alert.informativeText = "Do you want to save as PDF before quitting?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don\u{2019}t Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            doc.exportPDF()
            return doc.isDirty ? .terminateCancel : .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// ─────────────────────────────────────────────────────────────
// MARK: - Main
// ─────────────────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
