import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate_community_icon.swift SOURCE.svg OUTPUT.png\n".utf8))
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = NSSize(width: 1024, height: 1024)

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("could not decode \(sourceURL.path)\n".utf8))
    exit(65)
}

let rendered = NSImage(size: size)
rendered.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
source.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
rendered.unlockFocus()

guard let tiff = rendered.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not render PNG\n".utf8))
    exit(66)
}

try png.write(to: outputURL, options: [.atomic])
