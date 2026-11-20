import AppKit
import SwiftUI

// MARK: - Mascote em pixel
//
// O mascote desenhado numa grade de 16 × 16 células, como sprite: a forma de cada personagem
// (gota, bolha, nuvem…) vira células; o volume sai de cinco tons da cor dele misturados por
// pontilhado ordenado (Bayer 4 × 4), com brilho no alto à esquerda e a borda de baixo mais funda.
// Olhos são pílulas brancas de célula inteira; acessórios são pequenos mapas de células.
//
// Tudo em CoreGraphics, direto num bitmap com a célula em pixels inteiros (nada de borrão): o
// mesmo desenho serve às listas paradas e às camadas do mascote vivo (corpo e olhos separados).

enum MascotePixel {
  static let grade = 16

  enum Parte { case tudo, corpo, olhos }

  /// Onde ficam os olhos em cada forma (fração da altura do corpo).
  static func alturaOlhos(_ forma: String) -> CGFloat {
    ["gota": 0.6, "fantasma": 0.47, "nuvem": 0.58, "flor": 0.55, "pilula": 0.42, "hexa": 0.5, "losango": 0.5][forma] ?? 0.48
  }

  // MARK: Máscara da forma

  private static var mascaras: [String: [[Bool]]] = [:]

  /// Células dentro da forma (linha, coluna), amostradas no centro de cada célula.
  static func mascara(_ forma: String) -> [[Bool]] {
    if let m = mascaras[forma] { return m }
    let n = grade
    let caminho = FormaMascote(forma: forma).path(in: CGRect(x: 0, y: 0, width: 1, height: 1)).cgPath
    var m = Array(repeating: Array(repeating: false, count: n), count: n)
    for j in 0..<n {
      for i in 0..<n {
        let p = CGPoint(x: (CGFloat(i) + 0.5) / CGFloat(n), y: (CGFloat(j) + 0.5) / CGFloat(n))
        m[j][i] = caminho.contains(p, using: .winding)
      }
    }
    mascaras[forma] = m
    return m
  }

  // MARK: Tons

  private static let bayer: [[CGFloat]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]].map { $0.map { ($0 + 0.5) / 16 } }

  /// Cinco tons, do brilho à sombra: claros puxam para o branco; escuros ficam mais saturados
  /// (o pastel do personagem ganha corpo embaixo, em vez de acinzentar).
  static func tons(_ hex: String) -> [NSColor] {
    let base = (NSColor(hex: hex).usingColorSpace(.sRGB) ?? .gray)
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    func fundo(_ k: CGFloat) -> NSColor {
      NSColor(calibratedHue: h, saturation: min(1, s * (1 + 0.35 * k) + 0.1 * k), brightness: b * (1 - 0.3 * k), alpha: 1)
    }
    return [base.blended(withFraction: 0.42, of: .white) ?? base, base.blended(withFraction: 0.16, of: .white) ?? base,
            base, fundo(0.55), fundo(1)]
  }

  // MARK: Olhos

  /// Células acesas de um olho (coluna, linha) relativas ao canto do olho, e o tamanho dele.
  private static func olho(_ humor: Humor, feliz: Bool) -> (w: Int, h: Int, dy: Int, celulas: [(Int, Int)]) {
    func bloco(_ w: Int, _ h: Int) -> [(Int, Int)] { (0..<h).flatMap { y in (0..<w).map { x in (x, y) } } }
    if feliz && humor == .normal { return (3, 2, 0, [(0, 1), (1, 0), (2, 1)]) }
    switch humor {
    case .normal: return (1, 3, 0, bloco(1, 3))
    case .focado: return (2, 1, 1, bloco(2, 1))      // apertados, olhando para o que escreve
    case .atento: return (2, 3, -1, bloco(2, 3))     // arregalados, olhando para você
    case .dormindo: return (2, 1, 1, bloco(2, 1))    // fechados
    }
  }

  private static func distanciaOlhos(_ forma: String) -> CGFloat { forma == "pilula" ? 0.13 : 0.15 }

  /// Colunas e linha de cima de cada olho, espelhados para ficarem simétricos.
  private static func posicaoOlhos(_ forma: String, w: Int, h: Int, dy: Int) -> (esq: Int, dir: Int, topo: Int) {
    let n = CGFloat(grade)
    let cx = n * (0.5 - distanciaOlhos(forma))
    let esq = Int((cx - CGFloat(w) / 2).rounded())
    let dir = grade - esq - w
    let topo = Int((n * alturaOlhos(forma) - CGFloat(h) / 2).rounded()) + dy
    return (esq, dir, topo)
  }

  // MARK: Acessórios (mapas de células)

  private static let paleta: [Character: NSColor] = [
    "Y": NSColor(hex: "#ffd25e"), "y": NSColor(hex: "#d39a2c"), "R": NSColor(hex: "#ff6b6b"),
    "K": NSColor(hex: "#25252e"), "k": NSColor(hex: "#4a4a58"), "W": NSColor(hex: "#e7e9f0"), "w": NSColor(hex: "#9aa0ae"),
    "B": NSColor(hex: "#3b3f8f"), "b": NSColor(hex: "#2a2d6b"), "M": NSColor(hex: "#9a6b45"), "A": NSColor(hex: "#ffcf5a"),
  ]

  /// (coluna, linha, cor) de cada célula do acessório, na grade do corpo (pode sair dela).
  private static func acessorio(_ a: Acessorio, forma: String, mascara m: [[Bool]], olhos: (esq: Int, dir: Int, topo: Int, w: Int, h: Int)) -> [(Int, Int, NSColor)] {
    var out: [(Int, Int, NSColor)] = []
    func mapa(_ linhas: [String], x: Int, y: Int) {
      for (j, l) in linhas.enumerated() {
        for (i, ch) in l.enumerated() { if let c = paleta[ch] { out.append((x + i, y + j, c)) } }
      }
    }
    let topo = (0..<grade).first { m[$0][7] || m[$0][8] } ?? 1
    func bordas(_ linha: Int) -> (Int, Int) {
      let l = max(0, min(grade - 1, linha))
      let dentro = (0..<grade).filter { m[l][$0] }
      return (dentro.first ?? 2, dentro.last ?? 13)
    }
    switch a {
    case .nenhum: break
    case .coroa:
      mapa(["Y..YY..Y", "YY.YY.YY", "YYYRRYYY", "yyyyyyyy"], x: 4, y: topo - 3)
    case .boina:
      mapa(["......BB..", "..BBBBBBB.", ".BBBBBBBBB", "bbbbbbbbbb"], x: 3, y: topo - 3)
    case .antena:
      mapa(["AA", "AA", ".K", ".K"], x: 8, y: topo - 4)
    case .fones:
      let (e, d) = bordas(olhos.topo + 1)
      for i in stride(from: e + 1, through: d - 1, by: 1) { out.append((i, topo - 1, paleta["k"]!)) }
      out.append((e, topo, paleta["k"]!)); out.append((d, topo, paleta["k"]!))
      for y in stride(from: topo + 1, to: olhos.topo, by: 1) { out.append((e - 1, y, paleta["k"]!)); out.append((d + 1, y, paleta["k"]!)) }
      for y in olhos.topo...(olhos.topo + 2) {
        for x in [e - 2, e - 1] { out.append((x, y, x == e - 2 ? paleta["K"]! : paleta["R"]!)) }
        for x in [d + 1, d + 2] { out.append((x, y, x == d + 2 ? paleta["K"]! : paleta["R"]!)) }
      }
    case .oculos:
      let y0 = olhos.topo - 1, y1 = olhos.topo + olhos.h
      for x0 in [olhos.esq - 1, olhos.dir - 1] {
        let x1 = x0 + olhos.w + 1
        for x in x0...x1 { out.append((x, y0, paleta["K"]!)); out.append((x, y1, paleta["K"]!)) }
        for y in y0...y1 { out.append((x0, y, paleta["K"]!)); out.append((x1, y, paleta["K"]!)) }
      }
      for x in stride(from: olhos.esq + olhos.w + 1, through: olhos.dir - 2, by: 1) { out.append((x, y0 + 1, paleta["K"]!)) }
    case .lupa:
      mapa([".WW.", "W..W", "W..W", ".WWM", "....M", ".....M"], x: 10, y: 9)
    }
    return out
  }

  // MARK: Desenho

  private static let cache = NSCache<NSString, CGImage>()

  /// O mascote num quadro de lado `lado + 2·margem` (pontos), em pixels de `escala`.
  static func imagem(forma: String, cor: String, lado: CGFloat, margem: CGFloat, humor: Humor, acessorio a: Acessorio,
                     feliz: Bool, parte: Parte, escala: CGFloat) -> CGImage? {
    let chave = "\(forma)|\(cor)|\(lado)|\(margem)|\(humor)|\(a)|\(feliz)|\(parte)|\(escala)" as NSString
    if let c = cache.object(forKey: chave) { return c }
    let n = grade
    let total = Int(((lado + 2 * margem) * escala).rounded())
    // O corpo ocupa ~88% do quadro: sobra ar para a sombra e o acessório não cola no vizinho.
    let cel = max(1, Int((lado * 0.88 * escala / CGFloat(n)).rounded()))
    let origem = (total - cel * n) / 2
    guard total > 0, let ctx = CGContext(data: nil, width: total, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    // Linha 0 em cima, como nas máscaras.
    func pinta(_ i: Int, _ j: Int, _ c: NSColor) {
      ctx.setFillColor(c.cgColor)
      ctx.fill(CGRect(x: origem + i * cel, y: total - origem - (j + 1) * cel, width: cel, height: cel))
    }
    let m = mascara(forma)
    let tons = tons(cor)
    let olhoForma = olho(humor, feliz: feliz)
    let pos = posicaoOlhos(forma, w: olhoForma.w, h: olhoForma.h, dy: olhoForma.dy)

    if parte != .olhos {
      // Sombra no chão: uma faixa translúcida sob a base.
      let base = (0..<n).last { j in m[j].contains(true) } ?? (n - 1)
      let largura = m[base].filter { $0 }.count
      let x0 = (n - max(6, Int(Double(largura) * 0.8))) / 2
      for i in x0..<(n - x0) { pinta(i, base + 1, NSColor.black.withAlphaComponent(i == x0 || i == n - x0 - 1 ? 0.1 : 0.2)) }
      // Corpo.
      let linhas = (0..<n).filter { m[$0].contains(true) }
      let (vTopo, vBase) = (CGFloat(linhas.first ?? 0), CGFloat(linhas.last ?? n - 1))
      for j in 0..<n {
        for i in 0..<n where m[j][i] {
          let u = CGFloat(i) / CGFloat(n - 1)
          let v = (CGFloat(j) - vTopo) / max(1, vBase - vTopo)
          var nivel = (0.3 * u + 0.7 * v) * 2.7
          let fundoFora = j + 1 >= n || !m[j + 1][i]
          let direitaFora = i + 1 >= n || !m[j][i + 1]
          if fundoFora { nivel += 1.1 } else if direitaFora { nivel += 0.6 }
          if j == 0 || !m[j - 1][i] { nivel -= 0.6 }
          // Faixas sólidas; o pontilhado só aparece na passagem de um tom para o outro.
          let inteiro = nivel.rounded(.down), resto = nivel - inteiro
          let mistura = min(1, max(0, (resto - 0.3) / 0.4))
          var t = Int(inteiro) + (bayer[j % 4][i % 4] < mistura ? 1 : 0)
          // Brilho: um ponto no alto à esquerda.
          let du = u - 0.3, dv = v - 0.18
          if du * du + dv * dv < 0.012 { t = 0 }
          pinta(i, j, tons[max(0, min(4, t))])
        }
      }
      if a != .nenhum && lado >= 15 {
        for (i, j, c) in acessorio(a, forma: forma, mascara: m, olhos: (pos.esq, pos.dir, pos.topo, olhoForma.w, olhoForma.h)) {
          let x = origem + i * cel, y = origem + j * cel
          guard x >= 0, y >= 0, x + cel <= total, y + cel <= total else { continue }
          pinta(i, j, c)
        }
      }
    }
    if parte != .corpo {
      // Olho branco, ou escuro sobre corpo muito claro. Dormindo, a pálpebra é o tom mais fundo.
      let claro = NSColor(hex: cor).luminancia > 0.8
      let corOlho: NSColor = humor == .dormindo ? tons[4] : (claro ? NSColor(hex: "#1d1d26") : .white)
      for x0 in [pos.esq, pos.dir] {
        for (dx, dy) in olhoForma.celulas { pinta(x0 + dx, pos.topo + dy, corOlho) }
      }
    }
    guard let img = ctx.makeImage() else { return nil }
    cache.setObject(img, forKey: chave)
    return img
  }

  /// Linha do meio dos olhos, em fração do corpo (o piscar fecha em volta dela).
  static func linhaOlhos(_ forma: String, humor: Humor) -> CGFloat {
    let o = olho(humor, feliz: false)
    let p = posicaoOlhos(forma, w: o.w, h: o.h, dy: o.dy)
    return (CGFloat(p.topo) + CGFloat(o.h) / 2) / CGFloat(grade)
  }
}
