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

  /// Medida que acompanha o ajuste "Tamanho dos mascotes" (a coluna do avatar nas listas).
  static func lado(_ base: CGFloat) -> CGFloat { (base * Aparencia.atual.mascote).rounded() }

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

/// Pose de um quadro: para onde olha, quanto o corpo respira e se pisca. Tudo derivado do tempo e
/// de uma semente por agente (vizinhos não piscam juntos).
struct PoseMascote: Equatable {
  var olhar = CGSize.zero        // fração do lado
  var respiro: CGFloat = 0       // -1…1
  var piscar: CGFloat = 1        // 1 = aberto, ~0.1 = fechado
  var giro: CGFloat = 0          // graus
  var feliz = false
  var halo: CGFloat = 0.45       // opacidade do halo de trabalhando
  var luz = false                // luz da antena acesa
  var zz: Int = 0                // quantos "z" (dormindo)

  static func ruido(_ n: Int, _ semente: Double) -> CGFloat {
    let x = sin(Double(n) * 12.9898 + semente * 78.233) * 43758.5453
    return CGFloat((x - x.rounded(.down)) * 2 - 1)
  }
}

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

/// Acessório do mascote, tirado do papel: diz de relance o que cada um faz na equipe.
enum Acessorio: String {
  case nenhum, coroa, oculos, antena, fones, lupa, boina

  static func de(papel: String, maestro: Bool) -> Acessorio {
    if maestro { return .coroa }
    switch papel.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
    case "maestro", "lider", "líder", "pm": return .coroa
    case "revisor", "review", "testes", "qa": return .oculos
    case "dev", "infra", "dados", "backend", "frontend": return .antena
    case "conteudo", "copy", "redator", "suporte": return .fones
    case "pesquisa", "analista": return .lupa
    case "design", "designer": return .boina
    default: return .nenhum
    }
  }
}

/// O mascote desenhado: corpo com volume, olhos e boca com humor e o acessório do papel.
///
/// Movimento só por evento, nunca em loop (a CPU parada continua em 0%): pisca quando o mouse
/// passa por cima e quando o humor muda, e dá um pulinho quando começa a esperar você.
/// Com "Reduzir movimento" do macOS ligado, nada se mexe.
struct DesenhoMascote: View {
  let forma: String
  let cor: String
  var tamanho: CGFloat = 34
  var humor: Humor = .normal
  var acessorio: Acessorio = .nenhum
  /// Liga o halo de "trabalhando" atrás do corpo (as listas grandes desligam para não pesar).
  var halo = true
  /// Vivo: segue o relógio dos mascotes (pisca, olha em volta, respira). Parado: uma pose só.
  var animado = false
  /// Semente da animação (o nome do agente): cada um no seu ritmo.
  var semente: Double = 0
  @Estado private var piscando = false
  @Estado private var pulo: CGFloat = 0
  @Environment(\.displayScale) private var escalaTela

  static var semMovimento: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  var body: some View {
    if animado && !Self.semMovimento {
      MascoteVivo(d: self).frame(width: tamanho, height: tamanho)
    } else {
      desenho(pose: nil)
    }
  }

  enum Partes { case tudo, semOlhos, soOlhos }

  /// O desenho num quadro. `pose` nil = parado (com o piscar e o pulo por evento). `partes`
  /// separa os olhos do resto para o mascote vivo (cada um vira uma camada do Core Animation).
  func desenho(pose: PoseMascote?, partes: Partes = .tudo) -> some View {
    let base = NSColor(hex: cor)
    let p = pose ?? PoseMascote()
    let s = tamanho
    let pad = s * VistaMascoteVivo.margem
    let escala = escalaTela
    let feliz = p.feliz && humor == .normal
    func img(_ parte: MascotePixel.Parte) -> CGImage? {
      MascotePixel.imagem(forma: forma, cor: cor, lado: s, margem: pad, humor: humor, acessorio: acessorio, feliz: feliz, parte: parte, escala: escala)
    }
    let corpo = partes == .soOlhos ? nil : img(.corpo)
    let olhos = partes == .semOlhos ? nil : img(.olhos)
    let linha = MascotePixel.linhaOlhos(forma, humor: humor)
    return ZStack {
      if halo && humor == .focado && s >= 18 && partes == .tudo {
        // Halo: estático parado; com animação, pulsa devagar.
        Circle().fill(RadialGradient(colors: [Color(nsColor: base).opacity(pose == nil ? 0.4 : p.halo), Color(nsColor: base).opacity(0)],
                                     center: .center, startRadius: s * 0.3, endRadius: s * 0.72))
          .frame(width: s * 1.45, height: s * 1.45)
          .allowsHitTesting(false)
      }
      ZStack {
        if let corpo { Image(decorative: corpo, scale: escala).interpolation(.none) }
        if let olhos {
          Image(decorative: olhos, scale: escala).interpolation(.none)
            .offset(x: p.olhar.width * s, y: p.olhar.height * s)
            .scaleEffect(x: 1, y: piscando ? 0.12 : max(0.12, p.piscar), anchor: UnitPoint(x: 0.5, y: (pad + s * linha) / (s + 2 * pad)))
        }
      }
      .frame(width: s + 2 * pad, height: s + 2 * pad)
      .frame(width: s, height: s)
      .scaleEffect(x: 1 + 0.035 * p.respiro, y: 1 - 0.045 * p.respiro, anchor: .bottom)
      .offset(y: pulo)
      if p.zz > 0 && s >= 20 { Zz(tamanho: s, quantos: p.zz) }
    }
    .frame(width: s, height: s)
    .onHover { if $0 { piscar() } }
    .onChange(of: humor) { antes, agora in
      piscar()
      if agora == .atento && antes != .atento { pular() }
    }
  }

  private func piscar() {
    guard !Self.semMovimento, !piscando, humor != .dormindo else { return }
    withAnimation(.easeIn(duration: 0.06)) { piscando = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { withAnimation(.easeOut(duration: 0.09)) { piscando = false } }
  }

  private func pular() {
    guard !Self.semMovimento else { return }
    withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { pulo = -tamanho * 0.14 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { pulo = 0 } }
  }
}

/// "z z" subindo de quem dorme.
private struct Zz: View {
  let tamanho: CGFloat
  let quantos: Int
  var body: some View {
    let s = tamanho
    ZStack {
      Text("z").font(.system(size: max(7, s * 0.24), weight: .heavy, design: .rounded)).position(x: s * 0.86, y: s * 0.12)
      if quantos > 1 {
        Text("z").font(.system(size: max(6, s * 0.18), weight: .heavy, design: .rounded)).position(x: s * 1.02, y: -s * 0.06)
      }
    }
    .foregroundStyle(Cor.texto2)
    .frame(width: s, height: s)
    .allowsHitTesting(false)
  }
}
