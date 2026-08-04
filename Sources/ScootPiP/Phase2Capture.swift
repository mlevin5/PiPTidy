import AppKit
import ScreenCaptureKit
import ScootPiPCore

enum Phase2Capture {
    static func captureMap(excluding windowID: CGWindowID?) async throws -> PlacementMap {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let desktop = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        guard let screen = NSScreen.main, let display = content.displays.first(where: { $0.frame.intersects(CoordinateConverter.appKitToGlobalTopLeft(screen.frame, desktop:desktop)) }) ?? content.displays.first else { throw CaptureError.noDisplay }
        let exclusions = content.windows.filter { $0.owningApplication?.processID == getpid() || $0.windowID == windowID }
        let filter = SCContentFilter(display: display, excludingWindows: exclusions)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.frame.width)
        configuration.height = Int(display.frame.height)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let baseMap = ScoringMapGenerator.make(image: image, bounds: display.frame) else { throw CaptureError.mapFailed }
        let map = ScoringMapGenerator.applyingForegroundPriority(baseMap, windows:SystemCGInventory().enumerate(), excludingPID:getpid(), excludingWindowID:windowID)
        let visible = CoordinateConverter.appKitToGlobalTopLeft(screen.visibleFrame, desktop:desktop)
        let cellWidth=map.bounds.width/CGFloat(map.width),cellHeight=map.bounds.height/CGFloat(map.height)
        let costs=map.costs.enumerated().map { index,value in let x=index%map.width,y=index/map.width; let point=CGPoint(x:map.bounds.minX+(CGFloat(x)+0.5)*cellWidth,y:map.bounds.minY+(CGFloat(y)+0.5)*cellHeight); return visible.contains(point) ? value : 1 }
        return PlacementMap(bounds:map.bounds,width:map.width,height:map.height,costs:costs)
    }
    enum CaptureError: Error { case noDisplay, mapFailed }
}
