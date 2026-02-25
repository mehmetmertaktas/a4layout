import AppKit
import UniformTypeIdentifiers

let A4W: CGFloat = 595
let A4H: CGFloat = 842

// MARK: - Image Item (continuous A4 coordinate space)

class ImageItem {
    let image: NSImage
    var x: CGFloat
    var y: CGFloat      // continuous: page 0 = 0…842, page 1 = 842…1684, etc.
    var width: CGFloat
    var height: CGFloat
    var isSelected = false
    var hasFrame = false
    let aspectRatio: CGFloat

    init(image: NSImage, x: CGFloat, y: CGFloat, width: CGFloat) {
        self.image = image
        self.aspectRatio = image.size.width / image.size.height
        self.x = x
        self.y = y
        self.width = width
        self.height = width / aspectRatio
    }
}

// MARK: - Snap Guides

enum GuideAxis { case vertical, horizontal }

struct SnapGuide {
    let axis: GuideAxis
    let a4Pos: CGFloat   // x for vertical, page-local y for horizontal
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
            if d < bestDist && d <= threshold {
                bestDist = d
                bestDelta = te - de
            }
        }
    }

    guard bestDist <= threshold else { return SnapResult() }

    // After snap, collect all aligned positions
    let adjusted = dragEdges.map { $0 + bestDelta }
    var positions = Set<CGFloat>()
    for te in targetEdges {
        for ae in adjusted {
            if abs(te - ae) < 0.5 { positions.insert(te); break }
        }
    }

    return SnapResult(delta: bestDelta, positions: Array(positions))
}

// MARK: - Document View (scrollable, multi-page)

class DocumentView: NSView {
    var items: [ImageItem] = []
    var selectedItem: ImageItem?
    var numPages = 1
    var onRelayout: (() -> Void)?

    private var isDragging = false
    private var isResizing = false
    private var dragStartScreen = NSPoint.zero
    private var itemStartPos = NSPoint.zero
    private var itemStartWidth: CGFloat = 0
    private var pasteCount = 0
    private var activeGuides: [SnapGuide] = []

    private let handleR: CGFloat = 5
    let pad: CGFloat = 28
    let gap: CGFloat = 24
    private let addBtnSize: CGFloat = 32
    private let snapThreshold: CGFloat = 5  // A4 points

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var pageW: CGFloat { max(100, bounds.width - pad * 2) }
    var scale: CGFloat { pageW / A4W }
    var pageH: CGFloat { A4H * scale }

    func totalHeight(forWidth w: CGFloat) -> CGFloat {
        let pw = max(100, w - pad * 2)
        let ph = A4H * (pw / A4W)
        return pad + CGFloat(numPages) * ph + CGFloat(max(0, numPages - 1)) * gap + pad + addBtnSize + 24
    }

    func pageRect(for i: Int) -> NSRect {
        NSRect(x: pad, y: pad + CGFloat(i) * (pageH + gap), width: pageW, height: pageH)
    }

    var addButtonRect: NSRect {
        let lastPage = pageRect(for: numPages - 1)
        let btnY = lastPage.maxY + gap * 0.5
        return NSRect(x: bounds.midX - addBtnSize / 2, y: btnY,
                      width: addBtnSize, height: addBtnSize)
    }

    // Screen → continuous A4
    func toA4(_ sp: NSPoint) -> NSPoint {
        for i in 0..<numPages {
            let r = pageRect(for: i)
            if sp.y < r.maxY + gap / 2 || i == numPages - 1 {
                let lx = (sp.x - r.minX) / scale
                let ly = (sp.y - r.minY) / scale
                return NSPoint(x: lx, y: CGFloat(i) * A4H + ly)
            }
        }
        return .zero
    }

    // Continuous A4 → screen
    func toScreen(_ a4: NSPoint) -> NSPoint {
        let pg = min(max(0, Int(a4.y / A4H)), numPages - 1)
        let ly = a4.y - CGFloat(pg) * A4H
        let r = pageRect(for: pg)
        return NSPoint(x: r.minX + a4.x * scale, y: r.minY + ly * scale)
    }

    func screenFrame(for item: ImageItem) -> NSRect {
        let o = toScreen(NSPoint(x: item.x, y: item.y))
        return NSRect(x: o.x, y: o.y, width: item.width * scale, height: item.height * scale)
    }

    // MARK: Snap computation

    func computeSnaps(for item: ImageItem) -> (dx: CGFloat, dy: CGFloat, guides: [SnapGuide]) {
        let page = min(max(0, Int(item.y / A4H)), numPages - 1)
        let localY = item.y - CGFloat(page) * A4H

        // Dragged item edges
        let dxEdges = [item.x, item.x + item.width / 2, item.x + item.width]
        let dyEdges = [localY, localY + item.height / 2, localY + item.height]

        // Target edges: page boundaries + center
        var txEdges: [CGFloat] = [0, A4W / 2, A4W]
        var tyEdges: [CGFloat] = [0, A4H / 2, A4H]

        // Other items on the same page
        for other in items where other !== item {
            let op = min(max(0, Int(other.y / A4H)), numPages - 1)
            guard op == page else { continue }
            let oly = other.y - CGFloat(op) * A4H
            txEdges.append(contentsOf: [other.x, other.x + other.width / 2, other.x + other.width])
            tyEdges.append(contentsOf: [oly, oly + other.height / 2, oly + other.height])
        }

        let sx = snapAxis(dragEdges: dxEdges, targetEdges: txEdges, threshold: snapThreshold)
        let sy = snapAxis(dragEdges: dyEdges, targetEdges: tyEdges, threshold: snapThreshold)

        var guides: [SnapGuide] = []
        for pos in sx.positions {
            guides.append(SnapGuide(axis: .vertical, a4Pos: pos, page: page))
        }
        for pos in sy.positions {
            guides.append(SnapGuide(axis: .horizontal, a4Pos: pos, page: page))
        }

        return (sx.snapped ? sx.delta : 0, sy.snapped ? sy.delta : 0, guides)
    }

    // MARK: Drawing

    let guideColor = NSColor(red: 1, green: 0.22, blue: 0.38, alpha: 0.85)

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.91, alpha: 1).setFill()
        dirtyRect.fill()

        for i in 0..<numPages {
            let r = pageRect(for: i)
            guard dirtyRect.intersects(r.insetBy(dx: -16, dy: -16)) else { continue }

            // Shadow + white page
            NSGraphicsContext.saveGraphicsState()
            let shd = NSShadow()
            shd.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shd.shadowOffset = NSSize(width: 0, height: -1)
            shd.shadowBlurRadius = 8
            shd.set()
            NSColor.white.setFill()
            r.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Clip to page
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: r).setClip()

            // Hint on first page when empty
            if i == 0 && items.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor(white: 0.72, alpha: 1),
                    .font: NSFont.systemFont(ofSize: 15, weight: .light)
                ]
                let text = "Paste an image  \u{2318}V" as NSString
                let sz = text.size(withAttributes: attrs)
                text.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2),
                          withAttributes: attrs)
            }

            // Draw images overlapping this page
            let pageTop = CGFloat(i) * A4H
            let pageBot = pageTop + A4H
            for item in items {
                guard item.y + item.height > pageTop && item.y < pageBot else { continue }
                let f = screenFrame(for: item)
                item.image.draw(in: f)

                if item.hasFrame {
                    NSColor.black.setStroke()
                    let bezel = NSBezierPath(rect: f)
                    bezel.lineWidth = max(1, 0.75 * scale)
                    bezel.stroke()
                }

                if item.isSelected {
                    NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
                    let border = NSBezierPath(rect: f.insetBy(dx: -1, dy: -1))
                    border.lineWidth = 1.5
                    border.stroke()

                    let c = NSPoint(x: f.maxX, y: f.maxY)
                    let ov = NSRect(x: c.x - handleR, y: c.y - handleR,
                                    width: handleR * 2, height: handleR * 2)
                    NSColor.controlAccentColor.setFill()
                    NSBezierPath(ovalIn: ov).fill()
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: ov.insetBy(dx: 1.5, dy: 1.5)).fill()
                }
            }

            // Draw snap guide lines on this page
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

        // "+" button below last page
        let btnR = addButtonRect
        if dirtyRect.intersects(btnR.insetBy(dx: -8, dy: -8)) {
            NSColor(white: 0.82, alpha: 1).setStroke()
            let circle = NSBezierPath(ovalIn: btnR.insetBy(dx: 2, dy: 2))
            circle.lineWidth = 1.5
            circle.stroke()
            let plus = "+" as NSString
            let pAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(white: 0.62, alpha: 1),
                .font: NSFont.systemFont(ofSize: 18, weight: .light)
            ]
            let psz = plus.size(withAttributes: pAttrs)
            plus.draw(at: NSPoint(x: btnR.midX - psz.width / 2, y: btnR.midY - psz.height / 2),
                      withAttributes: pAttrs)
        }
    }

    // MARK: Hit testing

    private func hitItem(at a4: NSPoint) -> ImageItem? {
        for item in items.reversed() {
            if NSRect(x: item.x, y: item.y, width: item.width, height: item.height).contains(a4) {
                return item
            }
        }
        return nil
    }

    private func isOnHandle(screen sp: NSPoint, item: ImageItem) -> Bool {
        let f = screenFrame(for: item)
        return hypot(sp.x - f.maxX, sp.y - f.maxY) < handleR + 6
    }

    // MARK: Mouse events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let sp = convert(event.locationInWindow, from: nil)

        if addButtonRect.insetBy(dx: -4, dy: -4).contains(sp) {
            addPage()
            onRelayout?()
            DispatchQueue.main.async { [self] in
                scrollToVisible(pageRect(for: numPages - 1))
            }
            return
        }

        let a4 = toA4(sp)

        if let item = selectedItem, isOnHandle(screen: sp, item: item) {
            isResizing = true
            dragStartScreen = sp
            itemStartWidth = item.width
        } else if let hit = hitItem(at: a4) {
            select(hit)
            isDragging = true
            dragStartScreen = sp
            itemStartPos = NSPoint(x: hit.x, y: hit.y)
        } else {
            select(nil)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let item = selectedItem else { return }
        let sp = convert(event.locationInWindow, from: nil)
        let dx = (sp.x - dragStartScreen.x) / scale
        let dy = (sp.y - dragStartScreen.y) / scale

        if isResizing {
            item.width = max(20, itemStartWidth + dx)
            item.height = item.width / item.aspectRatio
            activeGuides = []
        } else if isDragging {
            // Set raw position first
            item.x = itemStartPos.x + dx
            item.y = itemStartPos.y + dy

            // Compute and apply snaps
            let (sdx, sdy, guides) = computeSnaps(for: item)
            item.x += sdx
            item.y += sdy
            activeGuides = guides
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isResizing = false
        activeGuides = []
        needsDisplay = true
    }

    func select(_ item: ImageItem?) {
        selectedItem?.isSelected = false
        selectedItem = item
        item?.isSelected = true
        activeGuides = []
        needsDisplay = true
    }

    // MARK: Actions

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
        var w = image.size.width
        if w > A4W * 0.6 { w = A4W * 0.6 }
        let pg = visiblePage()
        let off = CGFloat(pasteCount % 5) * 18
        let item = ImageItem(image: image,
                             x: (A4W - w) / 2 + off,
                             y: CGFloat(pg) * A4H + 80 + off,
                             width: w)
        items.append(item)
        pasteCount += 1
        select(item)
    }

    func addPage() {
        numPages += 1
    }

    func removePage() {
        guard numPages > 1 else { return }
        let top = CGFloat(numPages - 1) * A4H
        items.removeAll { $0.y >= top }
        if let sel = selectedItem, sel.y >= top { selectedItem = nil }
        numPages -= 1
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        items.removeAll { $0 === item }
        selectedItem = nil
        needsDisplay = true
    }

    func toggleFrame() {
        guard let item = selectedItem else { return }
        item.hasFrame.toggle()
        needsDisplay = true
    }

    func exportPDF() {
        select(nil)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "layout.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let pdfData = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: A4W, height: A4H)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }

        for pg in 0..<numPages {
            ctx.beginPDFPage(nil)
            ctx.translateBy(x: 0, y: A4H)
            ctx.scaleBy(x: 1, y: -1)

            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            NSBezierPath(rect: NSRect(x: 0, y: 0, width: A4W, height: A4H)).setClip()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: A4W, height: A4H).fill()

            let top = CGFloat(pg) * A4H
            for item in items {
                if item.y + item.height > top && item.y < top + A4H {
                    let rect = NSRect(x: item.x, y: item.y - top,
                                      width: item.width, height: item.height)
                    item.image.draw(in: rect)

                    if item.hasFrame {
                        NSColor.black.setStroke()
                        let bezel = NSBezierPath(rect: rect)
                        bezel.lineWidth = 0.75
                        bezel.stroke()
                    }
                }
            }

            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }

        ctx.closePDF()
        try? pdfData.write(to: url)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var scrollView: NSScrollView!
    var doc: DocumentView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        doc = DocumentView(frame: .zero)
        doc.onRelayout = { [weak self] in self?.relayout() }

        scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = doc
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.91, alpha: 1)
        scrollView.autoresizingMask = [.width, .height]

        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(relayout),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 860),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "A4 Layout"
        window.contentView = scrollView
        window.minSize = NSSize(width: 320, height: 450)
        window.center()
        window.makeKeyAndOrderFront(nil)
        setupMenus()
        relayout()
    }

    @objc func relayout() {
        let w = scrollView.contentView.bounds.width
        let h = max(doc.totalHeight(forWidth: w), scrollView.contentView.bounds.height)
        doc.setFrameSize(NSSize(width: w, height: h))
        doc.needsDisplay = true
    }

    func setupMenus() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit A4 Layout",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileMenu = NSMenu(title: "File")
        let save = NSMenuItem(title: "Save as PDF\u{2026}", action: #selector(savePDF), keyEquivalent: "s")
        save.target = self
        fileMenu.addItem(save)
        fileMenu.addItem(NSMenuItem.separator())
        let newPg = NSMenuItem(title: "New Page", action: #selector(addPage), keyEquivalent: "n")
        newPg.target = self
        fileMenu.addItem(newPg)
        let rmPg = NSMenuItem(title: "Remove Last Page", action: #selector(removePage), keyEquivalent: "n")
        rmPg.target = self; rmPg.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(rmPg)
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editMenu = NSMenu(title: "Edit")
        let paste = NSMenuItem(title: "Paste", action: #selector(pasteImage), keyEquivalent: "v")
        paste.target = self
        editMenu.addItem(paste)
        let del = NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: "\u{8}")
        del.target = self; del.keyEquivalentModifierMask = []
        editMenu.addItem(del)
        editMenu.addItem(NSMenuItem.separator())
        let frame = NSMenuItem(title: "Toggle Frame", action: #selector(toggleFrame), keyEquivalent: "b")
        frame.target = self
        editMenu.addItem(frame)
        let editItem = NSMenuItem(); editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc func pasteImage() { doc.pasteImage() }
    @objc func savePDF() { doc.exportPDF() }
    @objc func deleteSelected() { doc.deleteSelected() }
    @objc func toggleFrame() { doc.toggleFrame() }
    @objc func addPage() {
        doc.addPage()
        relayout()
        DispatchQueue.main.async { [self] in
            doc.scrollToVisible(doc.pageRect(for: doc.numPages - 1))
        }
    }
    @objc func removePage() { doc.removePage(); relayout() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
