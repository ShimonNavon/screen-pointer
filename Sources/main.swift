import AppKit
import Carbon.HIToolbox
import SwiftUI

// Screen Pointer — a capturable, never-focus-stealing highlight for macOS.
//
// The ring follows the cursor so a person on the other end (or an agent reading a screenshot) can see
// what is being pointed at. ⌃⌥H highlights, ⌃⌥D hands the mouse to the overlay for arrows and notes,
// ⌃⌥R records the screen. Everything lives in a menu-bar popover.

// MARK: - state

final class AppModel: ObservableObject {
    @Published var highlightOn = false { didSet { save("highlight", highlightOn); changed() } }
    @Published var drawMode = false { didSet { save("draw", drawMode); changed() } }
    @Published var spotlight = false { didSet { save("spotlight", spotlight); changed() } }
    @Published var toolName = "arrow" { didSet { save("tool", toolName); changed() } }
    @Published var colorIndex = 0 { didSet { save("color", colorIndex); changed() } }
    @Published var lineWidth = 4.0 { didSet { save("width", lineWidth); changed() } }
    @Published var recording = false
    @Published var elapsed = 0.0
    @Published var lastClip: String?

    var changed: () -> Void = {}

    static let colors: [(String, NSColor)] = [
        ("Yellow", .systemYellow), ("Red", .systemRed),
        ("Green", .systemGreen), ("Blue", .systemBlue),
    ]
    var color: NSColor { Self.colors[min(colorIndex, Self.colors.count - 1)].1 }

    init() {
        let d = UserDefaults.standard
        highlightOn = d.bool(forKey: "sp.highlight")
        drawMode = d.bool(forKey: "sp.draw")
        spotlight = d.object(forKey: "sp.spotlight") as? Bool ?? false
        toolName = d.string(forKey: "sp.tool") ?? "arrow"
        colorIndex = d.integer(forKey: "sp.color")
        lineWidth = d.object(forKey: "sp.width") as? Double ?? 4
    }

    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: "sp." + key) }
}

// MARK: - overlay

final class HighlightView: NSView {
    struct Shape {
        enum Kind: String { case pen, arrow, rect, highlight }
        var kind: Kind
        var points: [CGPoint]
        var color: NSColor
        var width: Double
    }

    weak var model: AppModel?
    var shapes: [Shape] = []
    private var current: Shape?

    override var isOpaque: Bool { false }

    private var mouse: CGPoint { convert(NSEvent.mouseLocation, from: nil) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let model else { return }

        if model.spotlight {
            let hole = 76.0
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRoundedRect(in: CGRect(x: mouse.x - hole, y: mouse.y - hole, width: hole * 2, height: hole * 2),
                                cornerWidth: 22, cornerHeight: 22)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fillPath(using: .evenOdd)
        }

        for shape in shapes { stroke(shape, in: ctx) }
        if let current { stroke(current, in: ctx) }

        let p = mouse
        let ring = CGRect(x: p.x - 44, y: p.y - 44, width: 88, height: 88)
        ctx.setStrokeColor(model.color.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(4)
        ctx.strokeEllipse(in: ring)
        ctx.setStrokeColor(model.color.withAlphaComponent(0.30).cgColor)
        ctx.setLineWidth(12)
        ctx.strokeEllipse(in: ring.insetBy(dx: -6, dy: -6))
    }

    func clearShapes() { shapes.removeAll(); current = nil; needsDisplay = true }
    func undo() { if !shapes.isEmpty { shapes.removeLast(); needsDisplay = true } }

    private func stroke(_ shape: Shape, in ctx: CGContext) {
        guard let first = shape.points.first else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch shape.kind {
        case .pen, .highlight:
            let path = CGMutablePath()
            path.move(to: first)
            for p in shape.points.dropFirst() { path.addLine(to: p) }
            ctx.addPath(path)
            ctx.setStrokeColor(shape.color.withAlphaComponent(shape.kind == .highlight ? 0.45 : 1).cgColor)
            ctx.setLineWidth(shape.kind == .highlight ? shape.width * 6 : shape.width)
            ctx.strokePath()
        case .rect:
            guard let last = shape.points.last else { return }
            let r = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                           width: abs(last.x - first.x), height: abs(last.y - first.y))
            ctx.setStrokeColor(shape.color.cgColor)
            ctx.setLineWidth(shape.width)
            ctx.stroke(r)
        case .arrow:
            guard let last = shape.points.last else { return }
            ctx.setStrokeColor(shape.color.cgColor)
            ctx.setLineWidth(shape.width)
            ctx.move(to: first); ctx.addLine(to: last); ctx.strokePath()
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = 10.0 + shape.width * 3
            for side in [angle + .pi * 0.85, angle - .pi * 0.85] {
                ctx.move(to: last)
                ctx.addLine(to: CGPoint(x: last.x + cos(side) * head, y: last.y + sin(side) * head))
            }
            ctx.strokePath()
        }
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        guard model?.drawMode == true else { return }
        let kind = Shape.Kind(rawValue: model?.toolName ?? "arrow") ?? .arrow
        current = Shape(kind: kind, points: [point(event)], color: model?.color ?? .systemYellow,
                        width: model?.lineWidth ?? 4)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard model?.drawMode == true, var shape = current else { return }
        if shape.kind == .pen || shape.kind == .highlight { shape.points.append(point(event)) }
        else { shape.points = [shape.points[0], point(event)] }
        current = shape
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard model?.drawMode == true else { return }
        if let shape = current, shape.points.count > 1 { shapes.append(shape) }
        current = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        if model?.drawMode == true { addCursorRect(bounds, cursor: .crosshair) }
    }
}

final class PointerWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - popover

struct MenuView: View {
    @ObservedObject var model: AppModel
    let onQuit: () -> Void
    let onOpenClip: () -> Void
    let onClear: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Screen Pointer").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(statusText).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }

            Toggle(isOn: $model.highlightOn) { Label("Highlight cursor", systemImage: "circle.dashed") }
                .toggleStyle(.switch)
            Toggle(isOn: $model.spotlight) { Label("Dim the rest", systemImage: "spotlight") }
                .toggleStyle(.switch)

            Divider()

            Text("Annotate").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Toggle(isOn: $model.drawMode) { Label("Draw over the screen", systemImage: "pencil.tip") }
                .toggleStyle(.switch)
            Picker("Tool", selection: $model.toolName) {
                Label("Arrow", systemImage: "arrow.up.right").tag("arrow")
                Label("Pen", systemImage: "scribble").tag("pen")
                Label("Highlight", systemImage: "highlighter").tag("highlight")
                Label("Box", systemImage: "rectangle").tag("rect")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                ForEach(Array(AppModel.colors.enumerated()), id: \.offset) { i, c in
                    Circle()
                        .fill(Color(nsColor: c.1))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.primary.opacity(model.colorIndex == i ? 0.55 : 0), lineWidth: 2))
                        .onTapGesture { model.colorIndex = i }
                }
                Spacer()
                Slider(value: $model.lineWidth, in: 2...12).frame(width: 90)
            }
            HStack {
                Button("Undo", action: onUndo)
                Button("Clear", action: onClear)
                Spacer()
            }
            .buttonStyle(.link)

            Divider()

            HStack(spacing: 8) {
                Button(role: nil, action: {
                    model.recording ? NotificationCenter.default.post(name: .stopRecording, object: nil)
                                    : NotificationCenter.default.post(name: .startRecording, object: nil)
                }) {
                    Label(model.recording ? "Stop · \(time(model.elapsed))" : "Record screen",
                          systemImage: model.recording ? "stop.circle.fill" : "record.circle")
                }
                .tint(model.recording ? .red : .accentColor)
                if model.lastClip != nil { Button("Last clip", action: onOpenClip) }
            }
            .buttonStyle(.bordered)

            Text("⌃⌥H highlight · ⌃⌥D draw · ⌃⌥R record")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Divider()
            HStack { Spacer(); Button("Quit", action: onQuit) }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var statusText: String {
        if model.recording { return "recording" }
        if model.drawMode { return "drawing" }
        return model.highlightOn ? "pointing" : "idle"
    }

    private func time(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Notification.Name {
    static let startRecording = Notification.Name("sp.startRecording")
    static let stopRecording = Notification.Name("sp.stopRecording")
}

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var windows: [PointerWindow] = []
    private var timer: Timer?
    private var recordTimer: Timer?
    private var status: NSStatusItem!
    private var panel: NSPanel!
    private var hotKey: EventHotKeyRef?
    private var recordKey: EventHotKeyRef?
    private var drawKey: EventHotKeyRef?
    private var recorder: Process?
    private var recordingURL: URL?
    private var recordStarted = Date()

    private static let clips: URL = {
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Screen Pointer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.autosaveName = "sp.status"
        status.button?.image = NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "Screen Pointer")
        status.button?.imagePosition = .imageOnly
        status.button?.target = self
        status.button?.action = #selector(togglePanel)

        let host = NSHostingController(rootView: MenuView(
            model: model,
            onQuit: { NSApp.terminate(nil) },
            onOpenClip: { [weak self] in self?.openLastClip() },
            onClear: { [weak self] in self?.allViews { $0.clearShapes() } },
            onUndo: { [weak self] in self?.allViews { $0.undo() } }
        ))
        let panel = NSPanel(contentViewController: host)
        panel.title = "Screen Pointer"
        panel.styleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        model.changed = { [weak self] in self?.applyModel() }
        NotificationCenter.default.addObserver(self, selector: #selector(startRecording),
                                               name: .startRecording, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopRecording),
                                               name: .stopRecording, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        registerHotKeys()
        model.lastClip = try? String(contentsOf: Self.clips.appendingPathComponent("last-recording.txt"),
                                     encoding: .utf8)

        let env = ProcessInfo.processInfo.environment
        if env["PTR_ON"] == "1" { model.highlightOn = true }
        if env["PTR_DRAW"] == "1" { model.drawMode = true }
        if env["PTR_POPOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showPanel() }
        }
        if let secs = Double(env["PTR_REC_SECONDS"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) { self.stopRecording() }
            }
        }
        applyModel()
    }

    // MARK: state -> UI

    private func applyModel() {
        if model.highlightOn || model.drawMode { showWindows() } else { hideWindows() }
        windows.forEach { w in
            w.ignoresMouseEvents = !model.drawMode
            w.contentView?.needsDisplay = true
            w.invalidateCursorRects(for: w.contentView!)
        }
        status.button?.image = NSImage(
            systemSymbolName: model.recording ? "record.circle.fill"
                : model.drawMode ? "pencil.tip"
                : model.highlightOn ? "circle.dashed.inset.filled" : "circle.dashed",
            accessibilityDescription: "Screen Pointer")
        status.button?.appearsDisabled = !(model.highlightOn || model.drawMode || model.recording)
    }

    @objc private func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
    }

    private func showPanel() {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - size.width - 20, y: f.maxY - size.height - 12))
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWindows() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = PointerWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .floating
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = !model.drawMode
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let v = HighlightView(frame: screen.frame)
            v.model = model
            w.contentView = v
            w.orderFrontRegardless()
            windows.append(w)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.contentView?.needsDisplay = true }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func hideWindows() {
        timer?.invalidate(); timer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func allViews(_ body: (HighlightView) -> Void) {
        windows.compactMap { $0.contentView as? HighlightView }.forEach(body)
    }

    @objc private func screensChanged() {
        guard !windows.isEmpty else { return }
        hideWindows(); showWindows()
    }

    // MARK: hotkeys

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                switch hk.id {
                case 2: delegate.startRecording()          // ⌃⌥R (toggles in its own handler)
                case 3: delegate.toggleDraw()
                default: delegate.toggleHighlight()
                }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let sig = OSType(0x50545231)  // 'PTR1'
        RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: sig, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: sig, id: 2), GetApplicationEventTarget(), 0, &recordKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: sig, id: 3), GetApplicationEventTarget(), 0, &drawKey)
    }

    private func toggleHighlight() {
        model.highlightOn.toggle()
    }

    private func toggleDraw() {
        model.drawMode.toggle()
        if model.drawMode { model.highlightOn = true }
    }

    // MARK: recording

    @objc func startRecording() {
        if recorder != nil { stopRecording(); return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = Self.clips.appendingPathComponent("Screen \(f.string(from: Date())).mov")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-v", "-x", url.path]
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.finishedRecording() } }
        do {
            try p.run()
            recorder = p
            recordingURL = url
            recordStarted = Date()
            model.recording = true
            model.elapsed = 0
            recordTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.model.elapsed = Date().timeIntervalSince(self.recordStarted)
            }
            RunLoop.main.add(recordTimer!, forMode: .common)
            applyModel()
        } catch {
            NSLog("Screen Pointer: cannot record: \(error)")
        }
    }

    @objc func stopRecording() {
        guard let recorder else { return }
        recorder.interrupt()
    }

    private func finishedRecording() {
        recordTimer?.invalidate(); recordTimer = nil
        recorder = nil
        model.recording = false
        if let url = recordingURL {
            try? url.path.write(to: Self.clips.appendingPathComponent("last-recording.txt"),
                                atomically: true, encoding: .utf8)
            model.lastClip = url.path
            NSLog("Screen Pointer: saved \(url.path)")
        }
        recordingURL = nil
        applyModel()
    }

    private func openLastClip() {
        guard let path = model.lastClip else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
