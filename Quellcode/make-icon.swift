import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for (pointSize, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let size = pointSize * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = NSGraphicsContext.current!.cgContext; c.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let base = NSBezierPath(roundedRect: NSRect(x:66,y:66,width:892,height:892),xRadius:210,yRadius:210)
    NSGradient(starting: NSColor(red:0.12,green:0.24,blue:0.39,alpha:1), ending:NSColor(red:0.27,green:0.45,blue:0.64,alpha:1))!.draw(in:base,angle:70)
    c.saveGState(); c.translateBy(x: 512, y: 512); c.rotate(by: -0.08); c.translateBy(x: -512, y: -512)
    NSColor.white.withAlphaComponent(0.22).setFill(); NSBezierPath(roundedRect:NSRect(x:201,y:235,width:638,height:548),xRadius:45,yRadius:45).fill(); c.restoreGState()
    NSColor.white.setFill(); NSBezierPath(roundedRect:NSRect(x:185,y:215,width:654,height:554),xRadius:46,yRadius:46).fill()
    let photo = NSBezierPath(roundedRect:NSRect(x:221,y:293,width:582,height:440),xRadius:16,yRadius:16)
    c.saveGState(); photo.addClip()
    NSGradient(starting: NSColor(red:0.39,green:0.65,blue:0.76,alpha:1),ending:NSColor(red:0.81,green:0.87,blue:0.83,alpha:1))!.draw(in:photo,angle:90)
    NSColor(red:1,green:0.85,blue:0.50,alpha:1).setFill(); NSBezierPath(ovalIn:NSRect(x:616,y:558,width:105,height:105)).fill()
    NSColor(red:0.24,green:0.43,blue:0.48,alpha:1).setFill(); let p=NSBezierPath(); p.move(to:NSPoint(x:200,y:280)); p.line(to:NSPoint(x:200,y:400)); p.line(to:NSPoint(x:392,y:601)); p.line(to:NSPoint(x:550,y:435)); p.line(to:NSPoint(x:660,y:520)); p.line(to:NSPoint(x:824,y:346)); p.line(to:NSPoint(x:824,y:280)); p.close(); p.fill(); c.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output).appendingPathComponent("icon_\(pointSize)x\(pointSize)\(suffix).png"))
}
