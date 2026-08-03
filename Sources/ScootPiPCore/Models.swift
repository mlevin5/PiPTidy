import Foundation
import CoreGraphics

public struct WindowCapabilities: Sendable, Equatable, Codable {
    public var movable: Bool?; public var resizable: Bool?
    public init(movable: Bool? = nil, resizable: Bool? = nil) { self.movable = movable; self.resizable = resizable }
}
public struct AXWindowSnapshot: Sendable, Equatable, Identifiable {
    public let id: String; public let pid: pid_t; public let owner: String; public let title: String?
    public let role: String?; public let subrole: String?; public let frame: CGRect?; public let capabilities: WindowCapabilities
    public init(id: String, pid: pid_t, owner: String, title: String? = nil, role: String? = nil, subrole: String? = nil, frame: CGRect? = nil, capabilities: WindowCapabilities = .init()) { self.id=id; self.pid=pid; self.owner=owner; self.title=title; self.role=role; self.subrole=subrole; self.frame=frame; self.capabilities=capabilities }
}
public struct CGWindowSnapshot: Sendable, Equatable, Identifiable {
    public let id: CGWindowID; public let pid: pid_t; public let owner: String; public let frame: CGRect; public let layer: Int
    public init(id: CGWindowID, pid: pid_t, owner: String, frame: CGRect, layer: Int) { self.id=id; self.pid=pid; self.owner=owner; self.frame=frame; self.layer=layer }
}
public struct ScoreComponent: Sendable, Equatable, Identifiable { public let id: String; public let points: Double; public let reason: String; public init(_ id: String, _ points: Double, _ reason: String) { self.id=id; self.points=points; self.reason=reason } }
public struct CandidateScore: Sendable, Equatable { public let total: Double; public let components: [ScoreComponent]; public init(_ components: [ScoreComponent]) { self.components=components; total=components.reduce(0) { $0+$1.points } } }
public struct WindowSnapshot: Sendable, Identifiable {
    public let ax: AXWindowSnapshot; public let cg: CGWindowSnapshot?; public let score: CandidateScore
    public var id: String { ax.id }
    public init(ax: AXWindowSnapshot, cg: CGWindowSnapshot?, score: CandidateScore) { self.ax=ax; self.cg=cg; self.score=score }
}
public enum AccessibilityError: Error, Sendable, Equatable, CustomStringConvertible {
    case notAuthorized, api(operation: String, code: Int32), missingAttribute(String), unsupported(String), ambiguousMatch, verification(expected: CGRect, actual: CGRect?)
    public var description: String { switch self { case .notAuthorized: "Accessibility permission not granted"; case let .api(op,c): "\(op) failed (AX \(c))"; case let .missingAttribute(a): "Missing \(a)"; case let .unsupported(a): "\(a) is not settable"; case .ambiguousMatch: "Ambiguous AX/CG match"; case let .verification(e,a): "Geometry verification failed; expected \(e), got \(String(describing:a))" } }
}
public struct ScreenGeometry: Sendable, Equatable { public let frame: CGRect; public let visibleFrame: CGRect; public let scale: CGFloat; public init(frame: CGRect, visibleFrame: CGRect, scale: CGFloat = 1) { self.frame=frame; self.visibleFrame=visibleFrame; self.scale=scale } }

public protocol AuthorizationProviding: Sendable { var isTrusted: Bool { get }; func request() }
public protocol AXInventoryProviding: Sendable { func enumerate() throws -> [AXWindowSnapshot] }
public protocol CGInventoryProviding: Sendable { func enumerate() -> [CGWindowSnapshot] }
public protocol WindowMutating: Sendable { func setFrame(id: String, frame: CGRect) throws }
public protocol CandidateScoring: Sendable { func score(_ ax: AXWindowSnapshot, cg: CGWindowSnapshot?) -> CandidateScore }
public protocol MovementObserving: Sendable { func observe(windowID: String, handler: @escaping @Sendable (CGRect) -> Void) throws }
