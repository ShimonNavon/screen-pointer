import AppKit
import Carbon.HIToolbox

// Screen Pointer: a capturable, never-focus-stealing highlight that follows the cursor.
// Menu bar item (◉) toggles it; ⌃⌥H does the same from any app without switching focus.

final class HighlightView: NSView {
    var mode: Mode = .ring
    enum Mode { case spotlight, ring }

    struct Shape {
        enum Kind { case pen, arrow, rect, highlight }
        var kind: Kind
        var points: [CGPoint]
        var color: NSColor
    }

    var tool: Shape.Kind = .arrow
    var drawing = false                  // when true the overlay takes the mouse
    var shapes: [Shape] = []
    private var current: Shape?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let p = convert(NSEvent.mouseLocation, from: nil)  // screen -> window
        let hole = 76.0

        if mode == .spotlight {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRoundedRect(in: CGRect(x: p.x - hole, y: p.y - hole, width: hole * 2, height: hole * 2),
                                cornerWidth: 22, cornerHeight: 22)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fillPath(using: .evenOdd)
        }

        for shape in shapes { stroke(shape, in: ctx) }
        if let current { stroke(current, in: ctx) }

        // the marker itself: a warm ring, deliberately visible in screenshots
        let ring = CGRect(x: p.x - 44, y: p.y - 44, width: 88, height: 88)
        ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(4)
        ctx.strokeEllipse(in: ring)
        ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(12)
        ctx.strokeEllipse(in: ring.insetBy(dx: -6, dy: -6))
    }
}

extension HighlightView {
    func clearShapes() { shapes.removeAll(); current = nil; needsDisplay = true }

    private func stroke(_ shape: Shape, in ctx: CGContext) {
        guard let first = shape.points.first else { return }
        let path = CGMutablePath()
        switch shape.kind {
        case .pen, .highlight:
            path.move(to: first)
            for p in shape.points.dropFirst() { path.addLine(to: p) }
            ctx.addPath(path)
            ctx.setStrokeColor(shape.color.cgColor)
            ctx.setLineWidth(shape.kind == .highlight ? 26 : 3)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            if shape.kind == .highlight { ctx.setBlendMode(.multiply) }
            ctx.strokePath()
            ctx.setBlendMode(.normal)
        case .rect:
            guard let last = shape.points.last else { return }
            let r = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                           width: abs(last.x - first.x), height: abs(last.y - first.y))
            ctx.setStrokeColor(shape.color.cgColor)
            ctx.setLineWidth(4)
            ctx.stroke(r)
        case .arrow:
            guard let last = shape.points.last else { return }
            ctx.setStrokeColor(shape.color.cgColor)
            ctx.setLineWidth(4)
            ctx.setLineCap(.round)
            ctx.move(to: first)
            ctx.addLine(to: last)
            ctx.strokePath()
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = 18.0
            for side in [angle + .pi * 0.85, angle - .pi * 0.85] {
                ctx.move(to: last)
                ctx.addLine(to: CGPoint(x: last.x + cos(side) * head, y: last.y + sin(side) * head))
            }
            ctx.strokePath()
        }
    }

    private func point(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard drawing else { return super.mouseDown(with: event) }
        current = Shape(kind: tool, points: [point(event)], color: NSColor.systemYellow)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard drawing, var shape = current else { return super.mouseDragged(with: event) }
        if shape.kind == .pen || shape.kind == .highlight { shape.points.append(point(event)) }
        else { shape.points = [shape.points[0], point(event)] }
        current = shape
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard drawing else { return super.mouseUp(with: event) }
        if let shape = current, shape.points.count > 1 { shapes.append(shape) }
        current = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        if drawing { addCursorRect(bounds, cursor: .crosshair) }
    }
}

final class PointerWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [PointerWindow] = []
    private var timer: Timer?
    private var status: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var recordKey: EventHotKeyRef?
    private var drawKey: EventHotKeyRef?
    private var drawMode = false
    private var active = false
    var mode: HighlightView.Mode = .ring
    private var recorder: Process?
    private var recordingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "◉"
        status.button?.toolTip = "Screen Pointer (⌃⌥H)"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show highlight", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Dim the rest (spotlight)", action: #selector(cycleMode), keyEquivalent: "")
        menu.addItem(withTitle: "Record screen", action: #selector(toggleRecording), keyEquivalent: "")
        menu.addItem(withTitle: "Annotate (⌃⌥D: the overlay takes the mouse)", action: #selector(toggleDrawMode), keyEquivalent: "")
        let tools = NSMenu()
        for title in ["Arrow", "Pen", "Highlight", "Rectangle"] {
            let item = NSMenuItem(title: title, action: #selector(pickTool(_:)), keyEquivalent: "")
            item.representedObject = title
            item.target = self
            tools.addItem(item)
        }
        let toolItem = NSMenuItem(title: "Tool", action: nil, keyEquivalent: "")
        toolItem.submenu = tools
        menu.addItem(toolItem)
        menu.addItem(withTitle: "Clear annotations", action: #selector(clearShapes), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        status.menu = menu

        registerHotKey()
        if ProcessInfo.processInfo.environment["PTR_ON"] == "1" { toggle() }
        if ProcessInfo.processInfo.environment["PTR_DRAW"] == "1" { toggleDrawMode() }
        if let secs = Double(ProcessInfo.processInfo.environment["PTR_REC_SECONDS"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) { self.stopRecording() }
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                switch hk.id {
                case 2: delegate.toggleRecording()
                case 3: delegate.toggleDrawMode()
                default: delegate.toggle()
                }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x50545231), id: 1)  // 'PTR1'
        RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKey)

        let recID = EventHotKeyID(signature: OSType(0x50545231), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey), recID,
                            GetApplicationEventTarget(), 0, &recordKey)

        let drawID = EventHotKeyID(signature: OSType(0x50545231), id: 3)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), drawID,
                            GetApplicationEventTarget(), 0, &drawKey)
    }

    @objc func toggle() {
        active.toggle()
        status.button?.title = active ? "◉" : "○"
        if active { showWindows() } else { hideWindows() }
    }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func toggleDrawMode() {
        drawMode.toggle()
        if drawMode && !active { toggle() }       // drawing implies the overlay is visible
        windows.forEach { w in
            w.ignoresMouseEvents = !drawMode
            (w.contentView as? HighlightView)?.drawing = drawMode
            w.invalidateCursorRects(for: w.contentView!)
        }
        status.button?.title = drawMode ? "✎" : (recorder != nil ? "⏺" : (active ? "◉" : "○"))
    }

    @objc func pickTool(_ sender: NSMenuItem) {
        let kinds: [String: HighlightView.Shape.Kind] = ["Arrow": .arrow, "Pen": .pen,
                                                         "Highlight": .highlight, "Rectangle": .rect]
        guard let kind = kinds[sender.title] else { return }
        windows.compactMap { $0.contentView as? HighlightView }.forEach { $0.tool = kind }
    }

    @objc func clearShapes() {
        windows.compactMap { $0.contentView as? HighlightView }.forEach { $0.clearShapes() }
    }

    @objc func cycleMode() {
        mode = mode == .spotlight ? .ring : .spotlight
        windows.compactMap { $0.contentView as? HighlightView }.forEach { $0.mode = mode; $0.needsDisplay = true }
    }

    // MARK: - recording

    private static let recordingsDir: URL = {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let dir = movies.appendingPathComponent("Screen Pointer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }

    @objc func toggleRecording() {
        if recorder != nil { stopRecording() } else { startRecording() }
    }

    func startRecording() {
        let url = AppDelegate.recordingsDir.appendingPathComponent("Screen \(stamp()).mov")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-v", "-x", url.path]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.finishRecording() }
        }
        do {
            try p.run()
            recorder = p
            recordingURL = url
            status.button?.title = "⏺"
            status.button?.toolTip = "Recording to \(url.lastPathComponent) — ⌃⌥R to stop"
        } catch {
            NSLog("Screen Pointer: cannot start recording: \(error)")
        }
    }

    func stopRecording() {
        recorder?.interrupt()   // SIGINT finalises the movie
    }

    private func finishRecording() {
        recorder = nil
        status.button?.title = active ? "◉" : "○"
        status.button?.toolTip = "Screen Pointer (⌃⌥H)"
        if let url = recordingURL {
            try? url.path.write(to: AppDelegate.recordingsDir.appendingPathComponent("last-recording.txt"),
                                atomically: true, encoding: .utf8)
            NSLog("Screen Pointer: saved \(url.path)")
        }
        recordingURL = nil
    }

    private func showWindows() {
        hideWindows()
        for screen in NSScreen.screens {
            let w = PointerWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            w.level = .floating
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = !drawMode     // clicks pass straight through unless annotating
            // .transient keeps it out of Mission Control / Show All Windows, .canJoinAllSpaces keeps
            // the pointer with Simon on every desktop (he runs six).
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let v = HighlightView(frame: screen.frame)
            v.mode = mode
            v.drawing = drawMode
            w.contentView = v
            w.orderFrontRegardless()
            windows.append(w)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.windows.compactMap { $0.contentView as? HighlightView }.forEach { $0.needsDisplay = true }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func hideWindows() {
        timer?.invalidate(); timer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    @objc private func screensChanged() { if active { showWindows() } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
