#!/usr/bin/env swift
// Builds the app icon and every robot a person can pick from the Icons8 artwork in
// Design/robot. Voxel robots keep their shapes; only the blue face is recolored.
// Run from the project folder:
//   swift scripts/make-icon.swift
import AppKit
import AVFoundation
import ImageIO

/// Face colors of the voxel variants; nil keeps the original blue.
let voxels: [(name: String, face: (r: Double, g: Double, b: Double)?)] = [
    ("paper", (1.0, 0.975, 0.935)),
    ("blue", nil),
    ("coral", (0.93, 0.50, 0.33)),
    ("green", (0.36, 0.72, 0.52)),
    ("violet", (0.55, 0.49, 0.98)),
]
/// Brightness of the lit blue face in the original, which maps to full paper.
let litBlue = 0.93
let tileColor = CGColor(srgbRed: 0xF2 / 255, green: 0xF0 / 255, blue: 0xE9 / 255, alpha: 1)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func bitmap(_ width: Int, _ height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    return context
}

/// Replaces blue with paper, keeping each pixel's shading. Grey cubes are untouched.
func recolor(_ image: CGImage, _ face: (r: Double, g: Double, b: Double)?) -> CGImage {
    guard let face else { return image }
    let context = bitmap(image.width, image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = context.data!.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    for i in stride(from: 0, to: image.width * image.height * 4, by: 4) {
        let alpha = Double(bytes[i + 3]) / 255
        if alpha == 0 { continue }
        let r = Double(bytes[i]) / 255 / alpha, g = Double(bytes[i + 1]) / 255 / alpha, b = Double(bytes[i + 2]) / 255 / alpha
        let value = max(r, g, b)
        guard value > 0, b > r else { continue }
        // How much of this pixel is blue; partial at the edges between cubes.
        let weight = min(1, max(0, (b - r) / value / 0.8))
        let light = min(1, value / litBlue)
        for (offset, pair) in [(r, face.r), (g, face.g), (b, face.b)].enumerated() {
            let mixed = (1 - weight) * min(pair.0, r + 0.02) + weight * pair.1 * light
            bytes[i + offset] = UInt8((min(1, max(0, mixed)) * alpha * 255).rounded())
        }
    }
    return context.makeImage()!
}

/// The area holding any visible pixel, in image coordinates (origin top left).
func bounds(_ image: CGImage) -> CGRect {
    let context = bitmap(image.width, image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = context.data!.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    var minX = image.width, minY = image.height, maxX = 0, maxY = 0
    for y in 0..<image.height {
        for x in 0..<image.width where bytes[(y * image.width + x) * 4 + 3] > 24 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// A square around `area` with a little room, so the robot sits centred.
func square(_ image: CGImage, _ area: CGRect) -> CGImage {
    let side = Int(max(area.width, area.height) * 1.04)
    let context = bitmap(side, side)
    let x = (CGFloat(side) - area.width) / 2, y = (CGFloat(side) - area.height) / 2
    context.draw(image.cropping(to: area)!, in: CGRect(x: x, y: y, width: area.width, height: area.height))
    return context.makeImage()!
}

func png(_ image: CGImage) -> Data { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])! }

func source(_ name: String) -> CGImageSource {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "Design/robot/\(name)") as CFURL, nil)
    else { fatalError("Design/robot/\(name) is missing.") }
    return source
}

func scaled(_ image: CGImage, _ size: Int) -> CGImage {
    let context = bitmap(size, size)
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
}

/// A Mac app icon: the robot on a rounded paper tile.
func icon(_ art: CGImage, _ size: Int) -> CGImage {
    let context = bitmap(size, size)
    let tile = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: CGFloat(size) * 0.09, dy: CGFloat(size) * 0.09)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil))
    context.setFillColor(tileColor)
    context.fillPath()
    context.draw(art, in: tile.insetBy(dx: tile.width * 0.1, dy: tile.width * 0.1))
    return context.makeImage()!
}

let assets = URL(fileURLWithPath: "Expo/Assets.xcassets")

func imageset(_ name: String, _ art: CGImage, points: Int, icon asIcon: Bool = false) throws {
    let folder = assets.appendingPathComponent("Bots/\(name).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var images: [String] = []
    for scale in [1, 2] {
        let file = "\(name.lowercased())@\(scale)x.png"
        let size = points * scale
        try png(asIcon ? icon(art, size) : scaled(art, size)).write(to: folder.appendingPathComponent(file))
        images.append("    { \"filename\": \"\(file)\", \"idiom\": \"universal\", \"scale\": \"\(scale)x\" }")
    }
    let json = "{\n  \"images\": [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\": { \"author\": \"xcode\", \"version\": 1 },\n  \"properties\": { \"template-rendering-intent\": \"original\" }\n}\n"
    try json.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func variant(_ name: String, _ art: CGImage) throws {
    try imageset("Mark-\(name)", art, points: 200)
    try imageset("Menu-\(name)", art, points: 18)
    try imageset("Icon-\(name)", art, points: 512, icon: true)
}

func still(_ file: String, _ face: (r: Double, g: Double, b: Double)?) -> CGImage {
    let art = recolor(CGImageSourceCreateImageAtIndex(source(file), 0, nil)!, face)
    return square(art, bounds(art))
}

/// The animation, cropped by one shared area so the robot does not jump, as HEVC with alpha.
func movie(_ name: String, _ frames: [CGImage], _ area: CGRect, _ face: (r: Double, g: Double, b: Double)?) throws {
    let side = 256
    let url = URL(fileURLWithPath: "Expo/Resources/Robots/robot-\(name).mov")
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha, AVVideoWidthKey: side, AVVideoHeightKey: side,
    AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.8],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: side, kCVPixelBufferHeightKey as String: side,
])
writer.add(input)
guard writer.startWriting() else { fatalError("\(writer.error!)") }
writer.startSession(atSourceTime: .zero)
for (index, frame) in frames.enumerated() {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    CVPixelBufferLockBaseAddress(buffer!, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer!), width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: side, height: side))
    context.draw(square(recolor(frame, face), area), in: CGRect(x: 0, y: 0, width: side, height: side))
    CVPixelBufferUnlockBaseAddress(buffer!, [])
    adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30))
}
input.markAsFinished()
writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames.count), timescale: 30))
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("\(String(describing: writer.error))") }
}

let appIcon = assets.appendingPathComponent("AppIcon.appiconset")
let standard = still("robot.png", voxels[0].face)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points).png" : "icon_\(points)@2x.png"
        try png(icon(standard, points * scale)).write(to: appIcon.appendingPathComponent(name))
    }
}

let gif = source("robot.gif")
let frames = (0..<CGImageSourceGetCount(gif)).map { CGImageSourceCreateImageAtIndex(gif, $0, nil)! }
let area = frames.map(bounds).reduce(CGRect.null) { $0.union($1) }
for (name, face) in voxels {
    let art = still("robot.png", face)
    try variant(name, art)
    try png(scaled(art, 256)).write(to: URL(fileURLWithPath: "Expo/Resources/Robots/robot-\(name)-poster.png"))
    try movie(name, frames, area, face)
}
print("App icon and \(voxels.count) robots written from Design/robot.")
