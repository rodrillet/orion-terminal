import SwiftUI
import AppKit

// MARK: - Mascote: o rosto de cada agente
//
// Personagens desenhados em vetor (nada de emoji): um corpo com forma própria, volume (degradê +
// brilho) e dois olhos que mudam com o estado — focados quando ele trabalha, arregalados quando
// espera você, fechados quando dorme. O campo `avatar` da Persona guarda o nome da forma.

enum Mascote {
  static let formas = ["gota", "bolha", "nuvem", "pilula", "hexa", "flor", "fantasma", "losango"]
  static let nomes = ["gota": "Gota", "bolha": "Bolha", "nuvem": "Nuvem", "pilula": "Pílula",
                      "hexa": "Hexágono", "flor": "Flor", "fantasma": "Fantasma", "losango": "Losango"]

  /// Forma de uma persona. Avatares antigos (emoji) caem numa forma fixa, tirada do nome.
  static func forma(_ p: Persona) -> String {
    if formas.contains(p.avatar) { return p.avatar }
    let base = p.nome.split(separator: " ").first.map(String.init) ?? p.nome
    if let e = Persona.elenco.first(where: { $0.nome == base }) { return e.avatar }
    return formas[Int(hashEstavel(p.nome + p.avatar) % UInt64(formas.count))]
  }

  static func proxima(_ atual: String) -> String {
    let i = formas.firstIndex(of: atual) ?? -1
    return formas[(i + 1) % formas.count]
  }

  /// djb2 — `String.hashValue` muda a cada execução, este não.
  static func hashEstavel(_ s: String) -> UInt64 {
    var h: UInt64 = 5381
    for b in s.utf8 { h = (h &<< 5) &+ h &+ UInt64(b) }
    return h
  }
}

enum Humor { case normal, focado, atento, dormindo }

extension EstadoPainel {
  var humor: Humor {
    switch self {
    case .trabalhando, .rodando: return .focado
    case .esperando: return .atento
    case .saiu, .dormindo: return .dormindo
    case .pronto: return .normal
    }
  }
}

/// Corpo do mascote, num quadrado unitário.
struct FormaMascote: Shape {
  let forma: String

  func path(in r: CGRect) -> Path {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
    var c = Path()
    switch forma {
    case "gota":
      c.move(to: p(0.5, 0.04))
      c.addCurve(to: p(0.9, 0.63), control1: p(0.62, 0.2), control2: p(0.9, 0.4))
      c.addCurve(to: p(0.5, 0.97), control1: p(0.9, 0.84), control2: p(0.72, 0.97))
      c.addCurve(to: p(0.1, 0.63), control1: p(0.28, 0.97), control2: p(0.1, 0.84))
      c.addCurve(to: p(0.5, 0.04), control1: p(0.1, 0.4), control2: p(0.38, 0.2))
      c.closeSubpath()
    case "nuvem":
      for (x, y, raio) in [(0.5, 0.42, 0.29), (0.27, 0.6, 0.23), (0.73, 0.6, 0.23), (0.5, 0.66, 0.28)] as [(CGFloat, CGFloat, CGFloat)] {
        c.addEllipse(in: CGRect(x: r.minX + (x - raio) * r.width, y: r.minY + (y - raio) * r.height, width: 2 * raio * r.width, height: 2 * raio * r.height))
      }
    case "pilula":
      c.addRoundedRect(in: CGRect(x: r.minX + 0.2 * r.width, y: r.minY + 0.05 * r.height, width: 0.6 * r.width, height: 0.9 * r.height),
                       cornerSize: CGSize(width: 0.3 * r.width, height: 0.3 * r.width), style: .continuous)
    case "hexa":
      c = FormaMascote.poligono(r, lados: 6, rotacao: .pi / 6, raio: 0.47, curva: 0.1)
    case "losango":
      c = FormaMascote.poligono(r, lados: 4, rotacao: 0, raio: 0.5, curva: 0.13)
    case "flor":
      for i in 0..<5 {
        let a = CGFloat(i) * 2 * .pi / 5 - .pi / 2
        let x = 0.5 + cos(a) * 0.24, y = 0.53 + sin(a) * 0.24, raio: CGFloat = 0.22
        c.addEllipse(in: CGRect(x: r.minX + (x - raio) * r.width, y: r.minY + (y - raio) * r.height, width: 2 * raio * r.width, height: 2 * raio * r.height))
      }
      c.addEllipse(in: CGRect(x: r.minX + 0.24 * r.width, y: r.minY + 0.27 * r.height, width: 0.52 * r.width, height: 0.52 * r.height))
    case "fantasma":
      c.move(to: p(0.13, 0.48))
      c.addArc(center: p(0.5, 0.48), radius: 0.37 * r.width, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
      c.addLine(to: p(0.87, 0.88))
      let ondas: [CGFloat] = [0.87, 0.745, 0.62, 0.5, 0.38, 0.255, 0.13]
      for i in 1..<ondas.count {
        let meio = (ondas[i - 1] + ondas[i]) / 2
        c.addQuadCurve(to: p(ondas[i], i % 2 == 1 ? 0.82 : 0.88), control: p(meio, i % 2 == 1 ? 0.97 : 0.8))
      }
      c.closeSubpath()
    default: // bolha
      c.addRoundedRect(in: r.insetBy(dx: r.width * 0.07, dy: r.height * 0.07),
                       cornerSize: CGSize(width: r.width * 0.36, height: r.height * 0.36), style: .continuous)
    }
    return c
  }

  /// Polígono regular com cantos arredondados.
  static func poligono(_ r: CGRect, lados: Int, rotacao: CGFloat, raio: CGFloat, curva: CGFloat) -> Path {
    let centro = CGPoint(x: r.midX, y: r.midY)
    let pts = (0..<lados).map { i -> CGPoint in
      let a = rotacao + CGFloat(i) * 2 * .pi / CGFloat(lados) - .pi / 2
      return CGPoint(x: centro.x + cos(a) * raio * r.width, y: centro.y + sin(a) * raio * r.height)
    }
    var c = Path()
    let meio = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    c.move(to: meio(pts[lados - 1], pts[0]))
    for i in 0..<lados {
      c.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % lados], radius: curva * r.width)
    }
    c.closeSubpath()
    return c
  }
}

/// O mascote desenhado: corpo com volume e olhos com humor.
struct DesenhoMascote: View {
  let forma: String
  let cor: String
  var tamanho: CGFloat = 34
  var humor: Humor = .normal

  var body: some View {
    let base = NSColor(hex: cor)
    let claro = Color(nsColor: base.blended(withFraction: 0.38, of: .white) ?? base)
    let escuro = Color(nsColor: base.blended(withFraction: 0.32, of: .black) ?? base)
    let corpo = FormaMascote(forma: forma)
    ZStack {
      corpo.fill(LinearGradient(colors: [claro, Color(nsColor: base), escuro], startPoint: .topLeading, endPoint: .bottomTrailing))
      // Brilho no alto e sombra embaixo: dão volume sem textura.
      corpo.fill(RadialGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)], center: UnitPoint(x: 0.34, y: 0.22),
                                startRadius: 0, endRadius: tamanho * 0.42))
      corpo.fill(LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.16)], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom))
      Olhos(forma: forma, tamanho: tamanho, humor: humor)
    }
    .frame(width: tamanho, height: tamanho)
    .compositingGroup()
    .shadow(color: Color(nsColor: base).opacity(0.28), radius: max(1, tamanho * 0.05), y: max(0.5, tamanho * 0.03))
  }
}

private struct Olhos: View {
  let forma: String
  let tamanho: CGFloat
  let humor: Humor

  var body: some View {
    let s = tamanho
    // Altura dos olhos por forma (a gota tem a cabeça embaixo, o fantasma em cima).
    let y: CGFloat = ["gota": 0.6, "fantasma": 0.47, "nuvem": 0.56, "flor": 0.53, "pilula": 0.42][forma] ?? 0.48
    let distancia: CGFloat = forma == "pilula" ? 0.13 : 0.15
    // Metade das formas tem olhos "de botão" (escuros e cheios); a outra metade, olhos com pupila.
    let botao = (Mascote.formas.firstIndex(of: forma) ?? 0) % 2 == 1
    let tinta = Color(white: 0.09)
    let olhar: CGSize = humor == .focado ? CGSize(width: 0.03, height: 0.02) : (humor == .atento ? CGSize(width: 0, height: -0.02) : .zero)
    ZStack {
    ForEach([-1.0, 1.0], id: \.self) { lado in
      let cx = s * (0.5 + CGFloat(lado) * distancia), cy = s * y
      Group {
        if humor == .dormindo {
          Path { c in
            c.move(to: CGPoint(x: cx - s * 0.06, y: cy))
            c.addQuadCurve(to: CGPoint(x: cx + s * 0.06, y: cy), control: CGPoint(x: cx, y: cy + s * 0.05))
          }
          .stroke(tinta.opacity(0.8), style: StrokeStyle(lineWidth: max(1, s * 0.035), lineCap: .round))
        } else if botao {
          let alto = s * (humor == .atento ? 0.2 : (humor == .focado ? 0.13 : 0.17))
          Capsule().fill(tinta)
            .frame(width: s * 0.095, height: alto)
            .overlay(alignment: .top) { Circle().fill(Color.white.opacity(0.85)).frame(width: s * 0.04, height: s * 0.04).padding(.top, s * 0.02) }
            .position(x: cx + olhar.width * s, y: cy + olhar.height * s)
        } else {
          let w = s * (humor == .atento ? 0.19 : 0.16), h = s * (humor == .atento ? 0.22 : (humor == .focado ? 0.15 : 0.19))
          Ellipse().fill(Color.white)
            .frame(width: w, height: h)
            .overlay {
              Circle().fill(tinta).frame(width: s * 0.085, height: s * 0.085)
                .offset(x: olhar.width * s * 1.4, y: olhar.height * s * 1.4)
            }
            .position(x: cx, y: cy)
        }
      }
    }
    }
    .frame(width: s, height: s)
  }
}
