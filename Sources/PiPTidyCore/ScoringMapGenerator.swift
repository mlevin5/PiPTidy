import CoreGraphics
import Foundation

public enum ScoringMapGenerator {
    /// Produces a point-resolution obstruction map. Detailed, bright, saturated, and central pixels cost more to cover.
    public static func make(image: CGImage, bounds: CGRect) -> PlacementMap? {
        // A bounded saliency grid keeps placement analysis effectively constant-time
        // across Retina and very large displays. Results are mapped back to screen points.
        let width = max(1, min(320, Int(bounds.width.rounded())))
        let height = max(1, Int((CGFloat(width) * bounds.height / max(bounds.width, 1)).rounded()))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func channels(_ x: Int, _ y: Int) -> (Float, Float, Float) { let i=(y*width+x)*4; return (Float(rgba[i])/255,Float(rgba[i+1])/255,Float(rgba[i+2])/255) }
        var luminance=[Float](repeating:0,count:width*height),edges=[Float](repeating:0,count:width*height)
        for y in 0..<height {for x in 0..<width {let c=channels(x,y);luminance[y*width+x]=0.2126*c.0+0.7152*c.1+0.0722*c.2}}
        for y in 0..<height {for x in 0..<width {let value=luminance[y*width+x];edges[y*width+x]=abs(value-luminance[y*width+min(x+1,width-1)])+abs(value-luminance[min(y+1,height-1)*width+x])}}
        var horizontalPeak=[Float](repeating:0,count:width*height),edgeIntegral=[Float](repeating:0,count:(width+1)*(height+1))
        for y in 0..<height {for x in 0..<width {var peak:Float=0;for sampleX in max(0,x-2)...min(width-1,x+2){peak=max(peak,edges[y*width+sampleX])};horizontalPeak[y*width+x]=peak;let integralIndex=(y+1)*(width+1)+x+1;edgeIntegral[integralIndex]=edges[y*width+x]+edgeIntegral[y*(width+1)+x+1]+edgeIntegral[(y+1)*(width+1)+x]-edgeIntegral[y*(width+1)+x]}}
        var costs=[Float](repeating:0,count:width*height)
        for y in 0..<height { for x in 0..<width {
            let c=channels(x,y), light=luminance[y*width+x]
            var edgePeak:Float=0;for sampleY in max(0,y-2)...min(height-1,y+2){edgePeak=max(edgePeak,horizontalPeak[sampleY*width+x])}
            let x0=max(0,x-2),x1=min(width,x+3),y0=max(0,y-2),y1=min(height,y+3)
            let edgeTotal=edgeIntegral[y1*(width+1)+x1]-edgeIntegral[y0*(width+1)+x1]-edgeIntegral[y1*(width+1)+x0]+edgeIntegral[y0*(width+1)+x0]
            let edgeDensity=edgeTotal/Float((x1-x0)*(y1-y0))
            let saturation=max(c.0,c.1,c.2)-min(c.0,c.1,c.2)
            let nx=(Float(x)/Float(width)-0.5)*2, ny=(Float(y)/Float(height)-0.5)*2
            let center=max(0,1-sqrt(nx*nx+ny*ny))
            costs[y*width+x]=min(1,0.42*min(1,edgePeak*5)+0.22*min(1,edgeDensity*8)+0.14*light+0.12*saturation+0.10*center)
        } }
        return PlacementMap(bounds:bounds,width:width,height:height,costs:costs)
    }

    /// Adds a z-order prior. Core Graphics inventory is front-to-back, so compact
    /// visible foreground windows cost more to cover. Windows hidden behind an
    /// earlier fullscreen window do not leave stale geometry in the map.
    public static func applyingForegroundPriority(_ map: PlacementMap, windows: [CGWindowSnapshot], excludingPID: pid_t, excludingWindowID: CGWindowID?, clearance: CGFloat = 16) -> PlacementMap {
        let cellWidth=map.bounds.width/CGFloat(map.width),cellHeight=map.bounds.height/CGFloat(map.height)
        var costs=map.costs,occluded=[Bool](repeating:false,count:map.width*map.height),rank=0
        func cells(for frame:CGRect)->(Int,Int,Int,Int) { let clipped=frame.intersection(map.bounds); return (max(0,Int((clipped.minX-map.bounds.minX)/cellWidth)),min(map.width,Int(ceil((clipped.maxX-map.bounds.minX)/cellWidth))),max(0,Int((clipped.minY-map.bounds.minY)/cellHeight)),min(map.height,Int(ceil((clipped.maxY-map.bounds.minY)/cellHeight)))) }
        for window in windows {
            let coverage=(window.frame.width*window.frame.height)/(map.bounds.width*map.bounds.height)
            guard window.pid != excludingPID,window.id != excludingWindowID,window.frame.intersects(map.bounds),(window.layer == 0 || coverage < 0.90) else{continue}
            let actual=cells(for:window.frame)
            if window.layer == 0,coverage < 0.90,rank < 4 {
                let protected=cells(for:window.frame.insetBy(dx:-clearance,dy:-clearance)),penalty=Float(0.30/Double(rank+1))
                var hasVisibleCell=false
                for y in protected.2..<protected.3 { for x in protected.0..<protected.1 where !occluded[y*map.width+x] {costs[y*map.width+x]=min(1,costs[y*map.width+x]+penalty);hasVisibleCell=true} }
                if hasVisibleCell {rank += 1}
            }
            for y in actual.2..<actual.3 {for x in actual.0..<actual.1 {occluded[y*map.width+x]=true}}
        }
        return PlacementMap(bounds:map.bounds,width:map.width,height:map.height,costs:costs)
    }

    /// Treats wallpaper-only cells as genuinely empty even when a detailed or
    /// high-contrast desktop image would otherwise look visually important.
    public static func applyingDesktopClearance(_ map: PlacementMap, windows: [CGWindowSnapshot], excludingPID: pid_t, excludingWindowID: CGWindowID?, clearance: CGFloat = 16) -> PlacementMap {
        let visibleWindows = windows.filter {
            let coverage = ($0.frame.width * $0.frame.height) / (map.bounds.width * map.bounds.height)
            return $0.pid != excludingPID && $0.id != excludingWindowID && $0.frame.intersects(map.bounds)
                && ($0.layer == 0 || coverage < 0.90)
        }
        var covered = [Bool](repeating: false, count: map.width * map.height)
        let cellWidth = map.bounds.width / CGFloat(map.width)
        let cellHeight = map.bounds.height / CGFloat(map.height)
        for window in visibleWindows {
            let clipped = window.frame.insetBy(dx: -clearance, dy: -clearance).intersection(map.bounds)
            let minX = max(0, Int((clipped.minX - map.bounds.minX) / cellWidth))
            let maxX = min(map.width, Int(ceil((clipped.maxX - map.bounds.minX) / cellWidth)))
            let minY = max(0, Int((clipped.minY - map.bounds.minY) / cellHeight))
            let maxY = min(map.height, Int(ceil((clipped.maxY - map.bounds.minY) / cellHeight)))
            for y in minY..<maxY {
                for x in minX..<maxX { covered[y * map.width + x] = true }
            }
        }
        var costs = map.costs
        for index in costs.indices where !covered[index] { costs[index] = 0 }
        return PlacementMap(bounds: map.bounds, width: map.width, height: map.height, costs: costs)
    }

    public static func heatmap(_ map: PlacementMap, placement: CGRect?) -> CGImage? {
        var pixels=[UInt8](repeating:0,count:map.width*map.height*4)
        for y in 0..<map.height { for x in 0..<map.width { let i=(y*map.width+x)*4, value=max(0,min(1,map.cost(atX:x,y:y))); pixels[i]=UInt8(255*value); pixels[i+1]=UInt8(180*(1-value)); pixels[i+2]=40; pixels[i+3]=190 } }
        if let p=placement { let sx=CGFloat(map.width)/map.bounds.width,sy=CGFloat(map.height)/map.bounds.height; let r=CGRect(x:(p.minX-map.bounds.minX)*sx,y:(p.minY-map.bounds.minY)*sy,width:p.width*sx,height:p.height*sy).integral; for y in max(0,Int(r.minY))..<min(map.height,Int(r.maxY)) { for x in max(0,Int(r.minX))..<min(map.width,Int(r.maxX)) where abs(x-Int(r.minX))<3||abs(x-(Int(r.maxX)-1))<3||abs(y-Int(r.minY))<3||abs(y-(Int(r.maxY)-1))<3 { let i=(y*map.width+x)*4; pixels[i]=0;pixels[i+1]=0;pixels[i+2]=0;pixels[i+3]=255 } } }
        guard let provider=CGDataProvider(data:Data(pixels) as CFData) else{return nil}
        return CGImage(width:map.width,height:map.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:map.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }
}
