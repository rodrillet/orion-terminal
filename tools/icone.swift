// Desenha o ícone do Orion Terminal (1024 px) no padrão do macOS: placa "squircle" grafite com
// profundidade sutil, o prompt ">" e, no lugar do cursor, a estrela da família Orion em azul.
// Uso: swift tools/icone.swift saida.png
import Cocoa

let lado: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(lado), pixelsHigh: Int(lado), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let cs = CGColorSpaceCreateDeviceRGB()
func cor(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
}
func gradiente(_ cores: [CGColor], _ pontos: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cores as CFArray, locations: pontos)! }

// Grade de ícones do macOS: placa de 824 px, margem de 100 px, cantos contínuos (superelipse).
let placa = CGRect(x: 100, y: 100, width: 824, height: 824)
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
  let p = CGMutablePath()
  let a = r.width / 2, b = r.height / 2
  let passos = 720
  for i in 0...passos {
    let t = CGFloat(i) / CGFloat(passos) * 2 * .pi
    let c = cos(t), s = sin(t)
    let x = r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
    let y = r.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
  }
  p.closeSubpath()
  return p
}
let forma = squircle(placa)

// Sombra da placa.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: cor(0x000000, 0.34))
ctx.addPath(forma); ctx.setFillColor(cor(0x1b1d22)); ctx.fillPath()
ctx.restoreGState()

// Corpo: grafite, mais claro em cima.
ctx.saveGState()
ctx.addPath(forma); ctx.clip()
ctx.drawLinearGradient(gradiente([cor(0x3b404a), cor(0x23262d), cor(0x15171b)], [0, 0.55, 1]),
                       start: CGPoint(x: 0, y: placa.maxY), end: CGPoint(x: 0, y: placa.minY), options: [])
// Luz suave vinda de cima à esquerda (profundidade, sem brilho exagerado).
ctx.drawRadialGradient(gradiente([cor(0xffffff, 0.10), cor(0xffffff, 0)], [0, 1]),
                       startCenter: CGPoint(x: 330, y: 900), startRadius: 0, endCenter: CGPoint(x: 330, y: 900), endRadius: 620, options: [])
ctx.restoreGState()

// Filete: claro em cima, escuro embaixo (borda chanfrada).
ctx.saveGState()
ctx.addPath(squircle(placa.insetBy(dx: 3, dy: 3))); ctx.setLineWidth(6); ctx.replacePathWithStrokedPath(); ctx.clip()
ctx.drawLinearGradient(gradiente([cor(0xffffff, 0.30), cor(0xffffff, 0.05), cor(0x000000, 0.35)], [0, 0.5, 1]),
                       start: CGPoint(x: 0, y: placa.maxY), end: CGPoint(x: 0, y: placa.minY), options: [])
ctx.restoreGState()

// Prompt ">" em branco, com uma sombra curta para descolar da placa.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: cor(0x000000, 0.45))
ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(66)
ctx.setStrokeColor(cor(0xf4f6fa))
ctx.move(to: CGPoint(x: 258, y: 652)); ctx.addLine(to: CGPoint(x: 402, y: 512)); ctx.addLine(to: CGPoint(x: 258, y: 372))
ctx.strokePath()
ctx.restoreGState()

// A estrela da família Orion (a do Orion App / OrionHub), em azul, onde ficaria o cursor.
let centro = CGPoint(x: 664, y: 512)
let escala: CGFloat = 7.7
let pontos: [(CGFloat, CGFloat)] = [(0, 23), (7, 7), (23, 0), (7, -7), (0, -23), (-7, -7), (-23, 0), (-7, 7)]
let estrela = CGMutablePath()
for (i, p) in pontos.enumerated() {
  let q = CGPoint(x: centro.x + p.0 * escala, y: centro.y + p.1 * escala)
  if i == 0 { estrela.move(to: q) } else { estrela.addLine(to: q) }
}
estrela.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: cor(0x000000, 0.45))
ctx.addPath(estrela); ctx.setFillColor(cor(0x2f7bea)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(estrela); ctx.clip()
ctx.drawLinearGradient(gradiente([cor(0x6fb4ff), cor(0x2f7bea), cor(0x1a5fd0)], [0, 0.55, 1]),
                       start: CGPoint(x: 0, y: centro.y + 23 * escala), end: CGPoint(x: 0, y: centro.y - 23 * escala), options: [])
ctx.restoreGState()
// Miolo claro, como no ícone do Orion App.
let r: CGFloat = 5 * escala
ctx.setFillColor(cor(0xdbe9ff))
ctx.fillEllipse(in: CGRect(x: centro.x - r, y: centro.y - r, width: 2 * r, height: 2 * r))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
