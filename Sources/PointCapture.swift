import AppKit
import ScreenCaptureKit

// Only a user-triggered capture is made available to agents. No background screen stream.
@MainActor
final class PointCapture {
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Screen Pointer/Points", isDirectory: true)

    static func region(point: CGPoint, size: CGSize) -> CGRect {
        let width = min(960.0, size.width), height = min(640.0, size.height)
        return CGRect(x: max(0, min(point.x - width / 2, size.width - width)),
                      y: max(0, min(point.y - height / 2, size.height - height)), width: width, height: height)
    }

    static func status(_ state: String, id: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data: [String: Any] = ["state": state, "id": id, "at": ISO8601DateFormatter().string(from: Date())]
        if let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: directory.appendingPathComponent("status.json"), options: .atomic)
        }
    }

    @available(macOS 14.0, *)
    static func capture() async throws -> URL {
        let id = UUID().uuidString.lowercased()
        status("capturing", id: id)
        do {
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { throw NSError(domain: "ScreenPointer", code: 1) }
            // AppKit: bottom-left global points. ScreenCaptureKit: top-left display points.
            let point = CGPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y)
            let region = region(point: point, size: screen.frame.size)
            let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app"
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == number.uint32Value })
            else { throw NSError(domain: "ScreenPointer", code: 2) }
            // Exclude this app's moving ring and panel; draw a fixed target into the saved image.
            let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let config = SCStreamConfiguration()
            config.sourceRect = region
            config.width = Int(region.width)
            config.height = Int(region.height)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw NSError(domain: "ScreenPointer", code: 3) }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let x = (point.x - region.minX) * Double(image.width) / region.width
            let y = (point.y - region.minY) * Double(image.height) / region.height
            let target = CGRect(x: x - 18, y: Double(image.height) - y - 18, width: 36, height: 36)
            context.setStrokeColor(NSColor.black.cgColor); context.setLineWidth(6); context.strokeEllipse(in: target)
            context.setStrokeColor(NSColor.systemYellow.cgColor); context.setLineWidth(3); context.strokeEllipse(in: target)
            guard let marked = context.makeImage(),
                  let png = NSBitmapImageRep(cgImage: marked).representation(using: .png, properties: [:])
            else { throw NSError(domain: "ScreenPointer", code: 4) }
            let url = directory.appendingPathComponent(id + ".png")
            try png.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let metadata: [String: Any] = ["schema": 1, "id": id, "image": url.lastPathComponent,
                "captured_at": ISO8601DateFormatter().string(from: Date()), "app": app,
                "display_id": number.uint32Value, "width": image.width, "height": image.height,
                "pointer": ["x": x, "y": y, "origin": "top-left", "unit": "image pixels"],
                "region": ["x": region.minX, "y": region.minY, "width": region.width, "height": region.height]]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
            status("ready", id: id)
            return url
        } catch {
            status("failed", id: id)
            throw error
        }
    }
}
