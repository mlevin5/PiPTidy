import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

public struct SystemAuthorization: AuthorizationProviding {
    public init() {}
    public var isTrusted: Bool { AXIsProcessTrusted() }
    public func request() { AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
}

private func attribute<T>(_ element: AXUIElement, _ name: CFString, as: T.Type) throws -> T? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name, &value)
    if error == .noValue || error == .attributeUnsupported { return nil }
    guard error == .success else { throw AccessibilityError.api(operation: "read \(name)", code: error.rawValue) }
    return value as? T
}
private func point(_ value: AXValue?) -> CGPoint? { guard let value else { return nil }; var result = CGPoint.zero; return AXValueGetValue(value, .cgPoint, &result) ? result : nil }
private func size(_ value: AXValue?) -> CGSize? { guard let value else { return nil }; var result = CGSize.zero; return AXValueGetValue(value, .cgSize, &result) ? result : nil }

public final class SystemAXService: AXInventoryProviding, WindowMutating, @unchecked Sendable {
    private let log = Logger(subsystem: "app.scootpip.ScootPiP", category: "mutation")
    private let enumerationLog = Logger(subsystem: "app.scootpip.ScootPiP", category: "enumeration")
    public init() {}
    public func enumerate() throws -> [AXWindowSnapshot] {
        guard AXIsProcessTrusted() else { throw AccessibilityError.notAuthorized }
        var output: [AXWindowSnapshot] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            let windows: [AXUIElement]
            do {
                guard let appWindows = try attribute(root, kAXWindowsAttribute as CFString, as: [AXUIElement].self) else { continue }
                windows = appWindows
            } catch {
                enumerationLog.debug("Skipping unresponsive application pid \(app.processIdentifier): \(String(describing: error), privacy: .public)")
                continue
            }
            for (index, window) in windows.enumerated() {
                let p = point(safelyRead(window, kAXPositionAttribute as CFString, as: AXValue.self, pid: app.processIdentifier))
                let s = size(safelyRead(window, kAXSizeAttribute as CFString, as: AXValue.self, pid: app.processIdentifier))
                var movable = DarwinBoolean(false), resizable = DarwinBoolean(false)
                AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable)
                AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable)
                output.append(.init(
                    id: "\(app.processIdentifier):\(index)",
                    pid: app.processIdentifier,
                    owner: app.localizedName ?? "Unknown",
                    title: safelyRead(window, kAXTitleAttribute as CFString, as: String.self, pid: app.processIdentifier),
                    role: safelyRead(window, kAXRoleAttribute as CFString, as: String.self, pid: app.processIdentifier),
                    subrole: safelyRead(window, kAXSubroleAttribute as CFString, as: String.self, pid: app.processIdentifier),
                    frame: p.flatMap { p in s.map { CGRect(origin: p, size: $0) } },
                    capabilities: .init(movable: movable.boolValue, resizable: resizable.boolValue)
                ))
            }
        }
        return output
    }
    private func safelyRead<T>(_ element: AXUIElement, _ name: CFString, as: T.Type, pid: pid_t) -> T? {
        do { return try attribute(element, name, as: T.self) }
        catch {
            enumerationLog.debug("Ignoring failed window attribute for pid \(pid): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
    public func setFrame(id: String, frame: CGRect) throws {
        let parts = id.split(separator: ":")
        guard parts.count == 2, let pid = pid_t(parts[0]), let index = Int(parts[1]) else { throw AccessibilityError.missingAttribute("window id") }
        let root = AXUIElementCreateApplication(pid)
        guard let windows = try attribute(root, kAXWindowsAttribute as CFString, as: [AXUIElement].self), windows.indices.contains(index) else { throw AccessibilityError.missingAttribute("window") }
        let window = windows[index]
        var origin = frame.origin, dimensions = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &dimensions) else { throw AccessibilityError.missingAttribute("geometry") }
        for (name, value) in [(kAXPositionAttribute as CFString, position), (kAXSizeAttribute as CFString, sizeValue)] {
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window, name, &settable) == .success, settable.boolValue else { throw AccessibilityError.unsupported(name as String) }
            let error = AXUIElementSetAttributeValue(window, name, value)
            guard error == .success else { log.error("AX write failed code \(error.rawValue)"); throw AccessibilityError.api(operation: "write \(name)", code: error.rawValue) }
        }
        let p = point(try attribute(window, kAXPositionAttribute as CFString, as: AXValue.self))
        let s = size(try attribute(window, kAXSizeAttribute as CFString, as: AXValue.self))
        let actual = p.flatMap { p in s.map { CGRect(origin: p, size: $0) } }
        guard actual.map({ abs($0.minX-frame.minX)<2 && abs($0.minY-frame.minY)<2 && abs($0.width-frame.width)<2 && abs($0.height-frame.height)<2 }) == true else { throw AccessibilityError.verification(expected: frame, actual: actual) }
    }
}

public struct SystemCGInventory: CGInventoryProviding {
    public init() {}
    public func enumerate() -> [CGWindowSnapshot] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { item in
            guard let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let owner = item[kCGWindowOwnerName as String] as? String,
                  let dictionary = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
            return .init(id: id, pid: pid, owner: owner, frame: frame, layer: (item[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0)
        }
    }
}
