import AppKit

// Original geometric artwork: a calendar page folding into a video camera.
// No Google logo or third-party assets.
let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 218, yRadius: 218)
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.05, green: 0.20, blue: 0.30, alpha: 1), ending: NSColor(calibratedRed: 0.05, green: 0.48, blue: 0.47, alpha: 1))!
gradient.draw(in: background, angle: 40)
NSColor(calibratedWhite: 0, alpha: 0.16).setFill()
NSBezierPath(roundedRect: NSRect(x: 214, y: 201, width: 540, height: 580), xRadius: 86, yRadius: 86).fill()
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 200, y: 225, width: 540, height: 580), xRadius: 86, yRadius: 86).fill()
NSColor(calibratedRed: 0.73, green: 0.94, blue: 0.88, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 200, y: 652, width: 540, height: 153), xRadius: 72, yRadius: 72).fill()
NSBezierPath(rect: NSRect(x: 200, y: 650, width: 540, height: 70)).fill()
NSColor(calibratedRed: 0.07, green: 0.29, blue: 0.35, alpha: 1).setStroke()
let rings = NSBezierPath(); rings.lineWidth = 32; rings.lineCapStyle = .round
for x in [332, 606] { rings.move(to: NSPoint(x: x, y: 750)); rings.line(to: NSPoint(x: x, y: 842)) }; rings.stroke()
NSColor(calibratedRed: 0.05, green: 0.46, blue: 0.43, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 351, width: 280, height: 205), xRadius: 48, yRadius: 48).fill()
let lens = NSBezierPath(); lens.move(to: NSPoint(x: 597, y: 494)); lens.line(to: NSPoint(x: 719, y: 570)); lens.line(to: NSPoint(x: 719, y: 339)); lens.line(to: NSPoint(x: 597, y: 415)); lens.close(); lens.fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
