import Foundation

public enum CoordinateConverter {
    public static func appKitToGlobalTopLeft(_ rect: CGRect, desktop: CGRect) -> CGRect { CGRect(x: rect.minX, y: desktop.maxY - rect.maxY, width: rect.width, height: rect.height) }
    public static func globalTopLeftToAppKit(_ rect: CGRect, desktop: CGRect) -> CGRect { CGRect(x: rect.minX, y: desktop.maxY - rect.maxY, width: rect.width, height: rect.height) }
    public static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect { CGRect(x: min(max(frame.minX,visible.minX),visible.maxX-frame.width), y: min(max(frame.minY,visible.minY),visible.maxY-frame.height), width:min(frame.width,visible.width), height:min(frame.height,visible.height)) }
    public static func corner(_ corner: Int, size: CGSize, visible: CGRect, margin: CGFloat = 12) -> CGRect { let x = corner % 2 == 0 ? visible.minX+margin : visible.maxX-size.width-margin; let y = corner < 2 ? visible.minY+margin : visible.maxY-size.height-margin; return clamp(CGRect(origin:.init(x:x,y:y),size:size),to:visible) }
}
public struct DefaultCandidateScorer: CandidateScoring {
    public init() {}
    public func score(_ ax: AXWindowSnapshot, cg: CGWindowSnapshot?) -> CandidateScore { var c:[ScoreComponent]=[]; if let f=ax.frame { let ratio=f.width/max(f.height,1); c.append(.init("visible", f.width>=160 && f.height>=90 ? 15:-30,"usable dimensions")); c.append(.init("aspect", ratio >= 1.3 && ratio <= 2.4 ? 30:-15,"video-like aspect ratio")); c.append(.init("compact", f.width < 1000 && f.height < 700 ? 12:-8,"floating-sized window")) } else { c.append(.init("geometry",-50,"missing geometry")) }; c.append(.init("movable",ax.capabilities.movable == true ? 15:-20,"movability")); c.append(.init("resizable",ax.capabilities.resizable == true ? 15:-10,"resizability")); if let cg { c.append(.init("layer",cg.layer>0 ? 12:2,"window-server layer \(cg.layer)")) }; if ax.subrole == "AXFloatingWindow" { c.append(.init("floating",20,"floating subrole")) }; return .init(c) }
}
public enum WindowCorrelator {
    public static func match(_ ax: AXWindowSnapshot, cg: [CGWindowSnapshot], tolerance: CGFloat = 3) -> CGWindowSnapshot? { guard let frame=ax.frame else{return nil}; let candidates=cg.filter{$0.pid==ax.pid && abs($0.frame.minX-frame.minX)<=tolerance && abs($0.frame.minY-frame.minY)<=tolerance && abs($0.frame.width-frame.width)<=tolerance && abs($0.frame.height-frame.height)<=tolerance}; return candidates.count == 1 ? candidates[0] : nil }
}
public struct PlacementMap: Sendable { public let bounds:CGRect; public let width:Int; public let height:Int; public let costs:[Float]; public init(bounds:CGRect,width:Int,height:Int,costs:[Float]) { precondition(costs.count==width*height); self.bounds=bounds;self.width=width;self.height=height;self.costs=costs }; public func cost(atX x:Int,y:Int)->Float { costs[y*width+x] } }
public struct PlacementResult: Sendable, Equatable { public let frame:CGRect; public let occlusionCost:Double; public let area:CGFloat }
public enum PlacementOptimizer {
    /// Exhaustively searches pixel-aligned positions, preferring the largest rectangle whose mean map cost is within the budget.
    public static func best(map:PlacementMap, aspectRatio:CGFloat, minSize:CGSize, maxSize:CGSize, costBudget:Double, highCostThreshold:Float = 1, maxHighCostFraction:Double = 1) -> PlacementResult? {
        guard map.width>0,map.height>0,aspectRatio>0 else{return nil}; var integral=[Double](repeating:0,count:(map.width+1)*(map.height+1)),highIntegral=[Int](repeating:0,count:(map.width+1)*(map.height+1)); for y in 0..<map.height { for x in 0..<map.width { let index=(y+1)*(map.width+1)+x+1,value=map.cost(atX:x,y:y); integral[index]=Double(value)+integral[y*(map.width+1)+x+1]+integral[(y+1)*(map.width+1)+x]-integral[y*(map.width+1)+x]; highIntegral[index]=(value>=highCostThreshold ? 1:0)+highIntegral[y*(map.width+1)+x+1]+highIntegral[(y+1)*(map.width+1)+x]-highIntegral[y*(map.width+1)+x] } }
        func sum(_ x:Int,_ y:Int,_ w:Int,_ h:Int)->Double { integral[(y+h)*(map.width+1)+x+w]-integral[y*(map.width+1)+x+w]-integral[(y+h)*(map.width+1)+x]+integral[y*(map.width+1)+x] }
        func highCount(_ x:Int,_ y:Int,_ w:Int,_ h:Int)->Int { highIntegral[(y+h)*(map.width+1)+x+w]-highIntegral[y*(map.width+1)+x+w]-highIntegral[(y+h)*(map.width+1)+x]+highIntegral[y*(map.width+1)+x] }
        let sx=map.bounds.width/CGFloat(map.width), sy=map.bounds.height/CGFloat(map.height); var best:PlacementResult?
        let maxW=min(map.width,Int(maxSize.width/sx)); let minW=max(1,Int(ceil(minSize.width/sx)))
        guard minW<=maxW else{return nil}; for w in stride(from:maxW,through:minW,by:-1) { let h=Int(round(CGFloat(w)*sx/aspectRatio/sy)); if h<1 || h>map.height || CGFloat(h)*sy>maxSize.height || CGFloat(h)*sy<minSize.height {continue}; for y in 0...(map.height-h) { for x in 0...(map.width-w) { let count=Double(w*h),mean=sum(x,y,w,h)/count,highFraction=Double(highCount(x,y,w,h))/count; if mean<=costBudget && highFraction<=maxHighCostFraction { let frame=CGRect(x:map.bounds.minX+CGFloat(x)*sx,y:map.bounds.minY+CGFloat(y)*sy,width:CGFloat(w)*sx,height:CGFloat(h)*sy); let r=PlacementResult(frame:frame,occlusionCost:mean,area:frame.width*frame.height); if best == nil || r.area > best!.area || (r.area == best!.area && (mean < best!.occlusionCost || (mean == best!.occlusionCost && (frame.minY < best!.frame.minY || (frame.minY == best!.frame.minY && frame.minX < best!.frame.minX))))) {best=r} } } }; if best != nil {break} }; return best
    }
}
