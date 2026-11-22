#!/usr/bin/env swift

import AppKit
import Foundation

struct Panel {
  let label: String
  let path: String
  let image: NSImage
}

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("[visual-comparison][FAIL] \(message)\n".utf8))
  exit(1)
}

private func draw(
  _ text: String,
  in rect: NSRect,
  font: NSFont,
  color: NSColor,
  alignment: NSTextAlignment = .left
) {
  let style = NSMutableParagraphStyle()
  style.alignment = alignment
  style.lineBreakMode = .byTruncatingTail
  (text as NSString).draw(
    in: rect,
    withAttributes: [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: style,
    ]
  )
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3 else {
  fail(
    "usage: build_visual_comparison.swift OUTPUT TITLE LABEL=IMAGE [LABEL=IMAGE ...]"
  )
}

let outputPath = arguments[0]
let title = arguments[1]
let panels: [Panel] = arguments.dropFirst(2).map { argument in
  guard let separator = argument.firstIndex(of: "=") else {
    fail("panel must use LABEL=IMAGE: \(argument)")
  }
  let label = String(argument[..<separator])
  let path = String(argument[argument.index(after: separator)...])
  guard !label.isEmpty, !path.isEmpty else {
    fail("panel label and path must be non-empty: \(argument)")
  }
  guard
    FileManager.default.fileExists(atPath: path),
    let image = NSImage(contentsOfFile: path)
  else {
    fail("image is unavailable or unreadable: \(path)")
  }
  return Panel(label: label, path: path, image: image)
}

let panelSize = NSSize(width: 316, height: 696)
let outerMargin: CGFloat = 24
let panelGap: CGFloat = 18
let titleHeight: CGFloat = 52
let labelHeight: CGFloat = 42
let footerHeight: CGFloat = 28
let canvasWidth =
  (outerMargin * 2) +
  (panelSize.width * CGFloat(panels.count)) +
  (panelGap * CGFloat(max(0, panels.count - 1)))
let canvasHeight =
  outerMargin + titleHeight + labelHeight + panelSize.height + footerHeight
let canvas = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight))

canvas.lockFocus()

NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
NSRect(origin: .zero, size: canvas.size).fill()

draw(
  title,
  in: NSRect(
    x: outerMargin,
    y: canvasHeight - outerMargin - titleHeight + 8,
    width: canvasWidth - (outerMargin * 2),
    height: titleHeight
  ),
  font: .systemFont(ofSize: 23, weight: .semibold),
  color: .white
)

let imageY = footerHeight
let labelY = imageY + panelSize.height + 8
for (index, panel) in panels.enumerated() {
  let x =
    outerMargin +
    (CGFloat(index) * (panelSize.width + panelGap))
  let panelRect = NSRect(
    x: x,
    y: imageY,
    width: panelSize.width,
    height: panelSize.height
  )

  NSColor.black.setFill()
  panelRect.fill()
  panel.image.draw(
    in: panelRect,
    from: NSRect(origin: .zero, size: panel.image.size),
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
  )
  NSColor(calibratedWhite: 0.34, alpha: 1).setStroke()
  let border = NSBezierPath(roundedRect: panelRect, xRadius: 8, yRadius: 8)
  border.lineWidth = 1
  border.stroke()

  draw(
    panel.label,
    in: NSRect(x: x, y: labelY, width: panelSize.width, height: labelHeight),
    font: .systemFont(ofSize: 15, weight: .medium),
    color: NSColor(calibratedWhite: 0.84, alpha: 1),
    alignment: .center
  )
}

draw(
  "Viewport normalized to 316 × 696 per panel. Labels identify evidence, not feature equivalence.",
  in: NSRect(
    x: outerMargin,
    y: 5,
    width: canvasWidth - (outerMargin * 2),
    height: footerHeight - 5
  ),
  font: .systemFont(ofSize: 10, weight: .regular),
  color: NSColor(calibratedWhite: 0.62, alpha: 1),
  alignment: .center
)

canvas.unlockFocus()

guard
  let tiff = canvas.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiff),
  let png = bitmap.representation(using: .png, properties: [:])
else {
  fail("could not encode comparison PNG")
}

let outputURL = URL(fileURLWithPath: outputPath)
do {
  try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try png.write(to: outputURL, options: .atomic)
} catch {
  fail("could not write \(outputPath): \(error.localizedDescription)")
}

print(
  "[visual-comparison] panels=\(panels.count) output=\(outputPath) size=\(Int(canvasWidth))x\(Int(canvasHeight))"
)
