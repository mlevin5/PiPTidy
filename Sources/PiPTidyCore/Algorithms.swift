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
public enum PiPDetector {
    public static func isCandidate(_ snapshot:AXWindowSnapshot)->Bool { let normalized=(snapshot.title ?? "").lowercased().replacingOccurrences(of:"-",with:" ").replacingOccurrences(of:"_",with:" "); return normalized.contains("picture in picture") || normalized.trimmingCharacters(in:.whitespacesAndNewlines) == "pip" }
    public static func isCandidate(_ snapshot:WindowSnapshot)->Bool {isCandidate(snapshot.ax)}
    public static func detect(in windows:[WindowSnapshot])->WindowSnapshot? {
        let titled=windows.filter(isCandidate)
        return titled.sorted { left,right in left.score.total == right.score.total ? left.id < right.id : left.score.total > right.score.total }.first
    }
}
public struct PlacementMap: Sendable { public let bounds:CGRect; public let width:Int; public let height:Int; public let costs:[Float]; public init(bounds:CGRect,width:Int,height:Int,costs:[Float]) { precondition(costs.count==width*height); self.bounds=bounds;self.width=width;self.height=height;self.costs=costs }; public func cost(atX x:Int,y:Int)->Float { costs[y*width+x] } }
public struct TemporalStalenessState: Sendable, Equatable {
    public let bounds:CGRect; public let width:Int; public let height:Int; public let rawCosts:[Float]; public let unchangedCounts:[UInt16]; public let historicalCosts:[Float]
    public init(bounds:CGRect,width:Int,height:Int,rawCosts:[Float],unchangedCounts:[UInt16],historicalCosts:[Float]?=nil) { self.bounds=bounds;self.width=width;self.height=height;self.rawCosts=rawCosts;self.unchangedCounts=unchangedCounts;self.historicalCosts=historicalCosts ?? rawCosts }
}
public enum TemporalStaleness {
    /// Discounts unchanged visual regions over time, with a floor so static UI is never ignored.
    public static func applying(to map:PlacementMap,previous:TemporalStalenessState?,tolerance:Float=0.025,decayPerObservation:Float=0.035,floorMultiplier:Float=0.55)->(map:PlacementMap,state:TemporalStalenessState) {
        let compatible=previous.map{$0.bounds==map.bounds && $0.width==map.width && $0.height==map.height && $0.rawCosts.count==map.costs.count && $0.unchangedCounts.count==map.costs.count && $0.historicalCosts.count==map.costs.count} == true
        guard compatible,let previous else{return(map,.init(bounds:map.bounds,width:map.width,height:map.height,rawCosts:map.costs,unchangedCounts:[UInt16](repeating:0,count:map.costs.count)))}
        var counts=[UInt16](repeating:0,count:map.costs.count),costs=map.costs,history=map.costs
        for index in map.costs.indices where abs(map.costs[index]-previous.rawCosts[index])<=tolerance {let count=previous.unchangedCounts[index] == .max ? UInt16.max : previous.unchangedCounts[index]+1;counts[index]=count;costs[index] *= max(floorMultiplier,1-Float(count)*decayPerObservation)}
        for index in map.costs.indices {history[index]=max(map.costs[index],previous.historicalCosts[index]*0.94);if history[index]>map.costs[index]+tolerance {costs[index]=max(costs[index],history[index]*0.75)}}
        let state=TemporalStalenessState(bounds:map.bounds,width:map.width,height:map.height,rawCosts:map.costs,unchangedCounts:counts,historicalCosts:history)
        return(.init(bounds:map.bounds,width:map.width,height:map.height,costs:costs),state)
    }
}
public struct PlacementResult: Sendable, Equatable { public let frame:CGRect; public let occlusionCost:Double; public let area:CGFloat }
public enum PlacementStability {
    /// Prevents small optimizer variations from visibly nudging an already-good PiP.
    public static func shouldMove(from current:CGRect,to proposed:CGRect,minimumOriginDelta:CGFloat=24,minimumSizeDelta:CGFloat=14)->Bool {
        let originDelta=hypot(current.minX-proposed.minX,current.minY-proposed.minY)
        let sizeDelta=hypot(current.width-proposed.width,current.height-proposed.height)
        return originDelta>=minimumOriginDelta || sizeDelta>=minimumSizeDelta
    }
}
public enum PlacementOptimizer {
    public struct CostStatistics:Sendable,Equatable {public let mean:Double;public let highFraction:Double}
    public static func statistics(map:PlacementMap,frame:CGRect,highCostThreshold:Float=1)->CostStatistics? {
        guard map.bounds.contains(frame),map.width>0,map.height>0 else{return nil}
        let sx=CGFloat(map.width)/map.bounds.width,sy=CGFloat(map.height)/map.bounds.height
        let minX=max(0,Int(floor((frame.minX-map.bounds.minX)*sx))),maxX=min(map.width,Int(ceil((frame.maxX-map.bounds.minX)*sx)))
        let minY=max(0,Int(floor((frame.minY-map.bounds.minY)*sy))),maxY=min(map.height,Int(ceil((frame.maxY-map.bounds.minY)*sy)))
        guard minX<maxX,minY<maxY else{return nil};var total:Double=0,high=0,count=0
        for y in minY..<maxY {for x in minX..<maxX {let value=map.cost(atX:x,y:y);total += Double(value);high += value>=highCostThreshold ? 1:0;count += 1}}
        return .init(mean:total/Double(count),highFraction:Double(high)/Double(count))
    }
    public static func meaningfullyImproves(map:PlacementMap,from current:CGRect,to proposed:CGRect,highCostThreshold:Float=1,minimumMeanImprovement:Double=0.04,minimumHighFractionImprovement:Double=0.01)->Bool {
        guard let current=statistics(map:map,frame:current,highCostThreshold:highCostThreshold),let proposed=statistics(map:map,frame:proposed,highCostThreshold:highCostThreshold) else{return true}
        return current.mean-proposed.mean>=minimumMeanImprovement || current.highFraction-proposed.highFraction>=minimumHighFractionImprovement
    }
    public static func isAcceptable(map:PlacementMap,frame:CGRect,minSize:CGSize?=nil,maxSize:CGSize?=nil,costBudget:Double,highCostThreshold:Float=1,maxHighCostFraction:Double=1)->Bool {
        guard map.bounds.contains(frame),map.width>0,map.height>0 else{return false}
        if let minSize,frame.width<minSize.width-2 || frame.height<minSize.height-2 {return false}
        if let maxSize,frame.width>maxSize.width+2 || frame.height>maxSize.height+2 {return false}
        guard let statistics=statistics(map:map,frame:frame,highCostThreshold:highCostThreshold) else{return false}
        return statistics.mean<=costBudget && statistics.highFraction<=maxHighCostFraction
    }

    /// Returns the least harmful minimum-sized placement when no candidate can
    /// satisfy the strict budget. High-importance coverage wins before mean cost.
    public static func leastCost(map:PlacementMap,aspectRatio:CGFloat,minSize:CGSize,maxSize:CGSize?=nil,highCostThreshold:Float=1,highCostTolerance:Double=0.01,meanCostTolerance:Double=0.05)->PlacementResult? {
        guard map.width>0,map.height>0,aspectRatio>0 else{return nil}
        let sx=map.bounds.width/CGFloat(map.width),sy=map.bounds.height/CGFloat(map.height)
        var integral=[Double](repeating:0,count:(map.width+1)*(map.height+1)),highIntegral=[Int](repeating:0,count:(map.width+1)*(map.height+1))
        for y in 0..<map.height {for x in 0..<map.width {let index=(y+1)*(map.width+1)+x+1,value=map.cost(atX:x,y:y);integral[index]=Double(value)+integral[y*(map.width+1)+x+1]+integral[(y+1)*(map.width+1)+x]-integral[y*(map.width+1)+x];highIntegral[index]=(value>=highCostThreshold ? 1:0)+highIntegral[y*(map.width+1)+x+1]+highIntegral[(y+1)*(map.width+1)+x]-highIntegral[y*(map.width+1)+x]}}
        func bestCandidate(width:Int,height:Int)->(x:Int,y:Int,highFraction:Double,mean:Double)? {
            guard width<=map.width,height<=map.height else{return nil};var best:(x:Int,y:Int,highFraction:Double,mean:Double)?;let count=Double(width*height)
            for y in 0...(map.height-height) {for x in 0...(map.width-width) {let sum=integral[(y+height)*(map.width+1)+x+width]-integral[y*(map.width+1)+x+width]-integral[(y+height)*(map.width+1)+x]+integral[y*(map.width+1)+x],high=highIntegral[(y+height)*(map.width+1)+x+width]-highIntegral[y*(map.width+1)+x+width]-highIntegral[(y+height)*(map.width+1)+x]+highIntegral[y*(map.width+1)+x],candidate=(x,y,Double(high)/count,sum/count);if best == nil || candidate.2<best!.highFraction || (candidate.2==best!.highFraction && (candidate.3<best!.mean || (candidate.3==best!.mean && (y<best!.y || (y==best!.y && x<best!.x))))) {best=candidate}}};return best
        }
        func result(_ candidate:(x:Int,y:Int,highFraction:Double,mean:Double),width:Int,height:Int)->PlacementResult {let frame=CGRect(x:map.bounds.minX+CGFloat(candidate.x)*sx,y:map.bounds.minY+CGFloat(candidate.y)*sy,width:CGFloat(width)*sx,height:CGFloat(height)*sy);return PlacementResult(frame:frame,occlusionCost:candidate.mean,area:frame.width*frame.height)}
        let minWidth=max(1,Int(ceil(minSize.width/sx))),minHeight=max(1,Int(round(CGFloat(minWidth)*sx/aspectRatio/sy)))
        guard let baseline=bestCandidate(width:minWidth,height:minHeight) else{return nil}
        let configuredMax=maxSize ?? minSize,maxWidth=min(map.width,Int(configuredMax.width/sx))
        if maxWidth>minWidth {for width in stride(from:maxWidth,through:minWidth+1,by:-1) {let height=Int(round(CGFloat(width)*sx/aspectRatio/sy));guard height>=minHeight,height<=map.height,CGFloat(height)*sy<=configuredMax.height else{continue};if let candidate=bestCandidate(width:width,height:height),candidate.highFraction<=baseline.highFraction+highCostTolerance,candidate.mean<=baseline.mean+meanCostTolerance {return result(candidate,width:width,height:height)}}}
        return result(baseline,width:minWidth,height:minHeight)
    }

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
