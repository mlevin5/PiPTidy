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
        func luminance(_ x: Int, _ y: Int) -> Float { let c=channels(x,y); return 0.2126*c.0+0.7152*c.1+0.0722*c.2 }
        var costs=[Float](repeating:0,count:width*height)
        for y in 0..<height { for x in 0..<width {
            let c=channels(x,y), light=luminance(x,y)
            let gradient=abs(light-luminance(min(x+1,width-1),y))+abs(light-luminance(x,min(y+1,height-1)))
            let saturation=max(c.0,c.1,c.2)-min(c.0,c.1,c.2)
            let nx=(Float(x)/Float(width)-0.5)*2, ny=(Float(y)/Float(height)-0.5)*2
            let center=max(0,1-sqrt(nx*nx+ny*ny))
            costs[y*width+x]=min(1,0.48*min(1,gradient*4)+0.24*light+0.18*saturation+0.10*center)
        } }
        return PlacementMap(bounds:bounds,width:width,height:height,costs:costs)
    }

    /// Adds a z-order prior. Core Graphics inventory is front-to-back, so compact
    /// foreground windows cost more to cover; nearly full-display windows are ignored.
    public static func applyingForegroundPriority(_ map: PlacementMap, windows: [CGWindowSnapshot], excludingPID: pid_t, excludingWindowID: CGWindowID?) -> PlacementMap {
        let eligible=windows.filter { $0.pid != excludingPID && $0.id != excludingWindowID && $0.layer == 0 && $0.frame.intersects(map.bounds) && ($0.frame.width*$0.frame.height)/(map.bounds.width*map.bounds.height) < 0.90 }.prefix(4)
        guard !eligible.isEmpty else{return map}
        let cellWidth=map.bounds.width/CGFloat(map.width),cellHeight=map.bounds.height/CGFloat(map.height)
        var costs=map.costs
        for (rank,window) in eligible.enumerated() { let penalty=Float(0.30/Double(rank+1)); let clipped=window.frame.intersection(map.bounds); let minX=max(0,Int((clipped.minX-map.bounds.minX)/cellWidth)),maxX=min(map.width,Int(ceil((clipped.maxX-map.bounds.minX)/cellWidth))); let minY=max(0,Int((clipped.minY-map.bounds.minY)/cellHeight)),maxY=min(map.height,Int(ceil((clipped.maxY-map.bounds.minY)/cellHeight))); for y in minY..<maxY { for x in minX..<maxX { costs[y*map.width+x]=min(1,costs[y*map.width+x]+penalty) } } }
        return PlacementMap(bounds:map.bounds,width:map.width,height:map.height,costs:costs)
    }

    public static func heatmap(_ map: PlacementMap, placement: CGRect?) -> CGImage? {
        var pixels=[UInt8](repeating:0,count:map.width*map.height*4)
        for y in 0..<map.height { for x in 0..<map.width { let i=(y*map.width+x)*4, value=max(0,min(1,map.cost(atX:x,y:y))); pixels[i]=UInt8(255*value); pixels[i+1]=UInt8(180*(1-value)); pixels[i+2]=40; pixels[i+3]=190 } }
        if let p=placement { let sx=CGFloat(map.width)/map.bounds.width,sy=CGFloat(map.height)/map.bounds.height; let r=CGRect(x:(p.minX-map.bounds.minX)*sx,y:(p.minY-map.bounds.minY)*sy,width:p.width*sx,height:p.height*sy).integral; for y in max(0,Int(r.minY))..<min(map.height,Int(r.maxY)) { for x in max(0,Int(r.minX))..<min(map.width,Int(r.maxX)) where abs(x-Int(r.minX))<3||abs(x-(Int(r.maxX)-1))<3||abs(y-Int(r.minY))<3||abs(y-(Int(r.maxY)-1))<3 { let i=(y*map.width+x)*4; pixels[i]=0;pixels[i+1]=0;pixels[i+2]=0;pixels[i+3]=255 } } }
        guard let provider=CGDataProvider(data:Data(pixels) as CFData) else{return nil}
        return CGImage(width:map.width,height:map.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:map.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }
}
