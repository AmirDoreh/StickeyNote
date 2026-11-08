import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
let catalog = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let iconset = root.appendingPathComponent("Assets/AppIcon.iconset")
try fm.createDirectory(at: catalog, withIntermediateDirectories: true)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.90, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0,y: 0,width: 1024,height: 1024), xRadius: 210,yRadius: 210).fill()
let shadow=NSShadow(); shadow.shadowColor=NSColor.black.withAlphaComponent(0.12); shadow.shadowBlurRadius=40; shadow.shadowOffset=NSSize(width: 0,height: -20); shadow.set()
NSColor(calibratedRed: 0.85,green: 0.91,blue: 0.51,alpha: 1).setFill()
let note=NSBezierPath();note.move(to: NSPoint(x: 212,y: 770));note.curve(to: NSPoint(x: 254,y: 812),controlPoint1: NSPoint(x: 212,y: 795),controlPoint2: NSPoint(x: 229,y: 812));note.line(to: NSPoint(x: 770,y: 812));note.curve(to: NSPoint(x: 812,y: 770),controlPoint1: NSPoint(x: 795,y: 812),controlPoint2: NSPoint(x: 812,y: 795));note.line(to: NSPoint(x: 812,y: 360));note.line(to: NSPoint(x: 654,y: 202));note.line(to: NSPoint(x: 254,y: 202));note.curve(to: NSPoint(x: 212,y: 244),controlPoint1: NSPoint(x: 229,y: 202),controlPoint2: NSPoint(x: 212,y: 219));note.close();note.fill()
NSShadow().set()
NSColor(calibratedRed: 0.64,green: 0.71,blue: 0.34,alpha: 1).setFill()
let fold=NSBezierPath();fold.move(to:NSPoint(x:654,y:202));fold.line(to:NSPoint(x:654,y:318));fold.curve(to:NSPoint(x:696,y:360),controlPoint1:NSPoint(x:654,y:344),controlPoint2:NSPoint(x:672,y:360));fold.line(to:NSPoint(x:812,y:360));fold.close();fold.fill()
NSColor(calibratedRed: 0.19,green: 0.23,blue: 0.14,alpha: 1).setStroke()
for (y,width) in [(650.0,350.0),(536.0,350.0),(422.0,220.0)] { let p=NSBezierPath(); p.lineWidth=28;p.lineCapStyle = .round;p.move(to:NSPoint(x:320,y:y));p.line(to:NSPoint(x:320+width,y:y));p.stroke() }
NSGraphicsContext.restoreGraphicsState()
let source=NSImage(size:NSSize(width:1024,height:1024));source.addRepresentation(bitmap)
func png(_ pixels: Int)->Data {
    let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:b);NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels));NSGraphicsContext.restoreGraphicsState()
    return b.representation(using:.png,properties:[:])!
}
var entries:[[String:String]]=[]
for points in [16,32,128,256,512] { for scale in [1,2] { let name="icon_\(points)x\(points)\(scale==2 ? "@2x" : "").png";let data=png(points*scale);try data.write(to:iconset.appendingPathComponent(name));try data.write(to:catalog.appendingPathComponent(name));entries.append(["idiom":"mac","size":"\(points)x\(points)","scale":"\(scale)x","filename":name]) } }
try png(1024).write(to:catalog.appendingPathComponent("ios-1024.png"))
entries.append(["idiom":"universal","platform":"ios","size":"1024x1024","filename":"ios-1024.png"])
try JSONSerialization.data(withJSONObject:["images":entries,"info":["author":"xcode","version":1]],options:.prettyPrinted).write(to:catalog.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject:["info":["author":"xcode","version":1]]).write(to:catalog.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Generated app icons")
