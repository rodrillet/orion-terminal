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
    let claro = Color(nsColor: base.blended(withFraction: 0.38, of: .white) ?? base)
    let escuro = Color(nsColor: base.blended(withFraction: 0.32, of: .black) ?? base)
    let corpo = FormaMascote(forma: forma)
    let p = pose ?? PoseMascote()
    let abertura = min(piscando ? 0.12 : 1, p.piscar)
    return ZStack {
      if halo && humor == .focado && tamanho >= 18 && partes == .tudo {
        // Halo: estático parado; com animação, pulsa devagar.
        Circle().fill(RadialGradient(colors: [Color(nsColor: base).opacity(pose == nil ? 0.45 : p.halo + 0.1), Color(nsColor: base).opacity(0)],
                                     center: .center, startRadius: tamanho * 0.3, endRadius: tamanho * 0.72))
          .frame(width: tamanho * 1.45, height: tamanho * 1.45)
          .allowsHitTesting(false)
      }
      Group {
        if partes != .soOlhos {
        corpo.fill(LinearGradient(colors: [claro, Color(nsColor: base), escuro], startPoint: .topLeading, endPoint: .bottomTrailing))
        // Brilho no alto e sombra embaixo: dão volume sem textura. O brilho segue a virada.
        corpo.fill(RadialGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                                  center: UnitPoint(x: 0.34 - p.olhar.width * 2, y: 0.22), startRadius: 0, endRadius: tamanho * 0.42))
        corpo.fill(LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.16)], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom))
        }
        if partes != .semOlhos {
          Olhos(forma: forma, tamanho: tamanho, humor: humor, piscando: abertura < 0.5, extra: p.olhar, feliz: p.feliz && humor == .normal)
        }
        if partes != .soOlhos && tamanho >= 20 { Boca(forma: forma, tamanho: tamanho, humor: p.feliz && humor == .normal ? .normal : humor).offset(x: p.olhar.width * tamanho * 0.6) }
        if partes != .soOlhos && acessorio != .nenhum && tamanho >= 16 { DesenhoAcessorio(acessorio: acessorio, forma: forma, tamanho: tamanho, luz: p.luz) }
      }
      .frame(width: tamanho, height: tamanho)
      .scaleEffect(x: 1 + 0.035 * p.respiro, y: 1 - 0.045 * p.respiro, anchor: .bottom)
      .rotationEffect(.degrees(Double(p.giro) * 0.08), anchor: .bottom)
      .offset(y: pulo)
      if p.zz > 0 && tamanho >= 20 { Zz(tamanho: tamanho, quantos: p.zz) }
    }
    .frame(width: tamanho, height: tamanho)
    // Rasteriza o mascote numa camada só (Metal): redesenhar a cada quadro fica barato.
    .compositingGroup()
    .shadow(color: Color(nsColor: base).opacity(partes == .soOlhos ? 0 : 0.28), radius: max(1, tamanho * 0.05), y: max(0.5, tamanho * 0.03))
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

/// Onde ficam os olhos em cada forma (fração da altura) — a boca e os óculos seguem.
private func alturaOlhos(_ forma: String) -> CGFloat {
  ["gota": 0.6, "fantasma": 0.47, "nuvem": 0.56, "flor": 0.53, "pilula": 0.42][forma] ?? 0.48
}
private func distanciaOlhos(_ forma: String) -> CGFloat { forma == "pilula" ? 0.13 : 0.15 }

private struct Olhos: View {
  let forma: String
  let tamanho: CGFloat
  let humor: Humor
  var piscando = false
  var extra: CGSize = .zero
  var feliz = false

  var body: some View {
    let s = tamanho
    let y = alturaOlhos(forma)
    let distancia = distanciaOlhos(forma)
    // Metade das formas tem olhos "de botão" (escuros e cheios); a outra metade, olhos com pupila.
    let botao = (Mascote.formas.firstIndex(of: forma) ?? 0) % 2 == 1
    let tinta = Color(white: 0.09)
    // Focado olha para o lado (lendo o trabalho); atento olha para cima (para você).
    let base: CGSize = extra != .zero ? .zero : (humor == .focado ? CGSize(width: 0.035, height: 0.015) : (humor == .atento ? CGSize(width: 0, height: -0.025) : .zero))
    let olhar = CGSize(width: base.width + extra.width, height: base.height + extra.height)
    ZStack {
    ForEach([-1.0, 1.0], id: \.self) { lado in
      let cx = s * (0.5 + CGFloat(lado) * distancia) + olhar.width * s * 0.6, cy = s * y + olhar.height * s * 0.4
      Group {
        if feliz {
          // Olhos sorrindo (∩).
          Path { c in
            c.move(to: CGPoint(x: cx - s * 0.06, y: cy + s * 0.02))
            c.addQuadCurve(to: CGPoint(x: cx + s * 0.06, y: cy + s * 0.02), control: CGPoint(x: cx, y: cy - s * 0.07))
          }
          .stroke(tinta, style: StrokeStyle(lineWidth: max(1.2, s * 0.045), lineCap: .round))
        } else if humor == .dormindo {
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
            .scaleEffect(x: 1, y: piscando ? 0.12 : 1)
            .position(x: cx + olhar.width * s * 0.4, y: cy + olhar.height * s * 0.6)
        } else {
          let w = s * (humor == .atento ? 0.19 : 0.16), h = s * (humor == .atento ? 0.22 : (humor == .focado ? 0.15 : 0.19))
          Ellipse().fill(Color.white)
            .frame(width: w, height: h)
            .overlay {
              Circle().fill(tinta).frame(width: s * 0.085, height: s * 0.085)
                .offset(x: olhar.width * s * 1.4, y: olhar.height * s * 1.4)
            }
            .scaleEffect(x: 1, y: piscando ? 0.1 : 1)
            .position(x: cx, y: cy)
        }
      }
    }
    }
    .frame(width: s, height: s)
  }
}

/// Boca pequena: sorriso em repouso, "o" quando espera você, reta quando concentrado.
private struct Boca: View {
  let forma: String
  let tamanho: CGFloat
  let humor: Humor

  var body: some View {
    let s = tamanho
    let cy = s * (alturaOlhos(forma) + 0.15)
    let tinta = Color(white: 0.09).opacity(0.78)
    let traco = StrokeStyle(lineWidth: max(1, s * 0.032), lineCap: .round)
    Group {
      switch humor {
      case .atento:
        Ellipse().fill(tinta).frame(width: s * 0.07, height: s * 0.08).position(x: s * 0.5, y: cy + s * 0.01)
      case .focado:
        Path { c in c.move(to: CGPoint(x: s * 0.46, y: cy)); c.addLine(to: CGPoint(x: s * 0.54, y: cy)) }.stroke(tinta, style: traco)
      case .dormindo:
        Path { c in c.move(to: CGPoint(x: s * 0.47, y: cy)); c.addLine(to: CGPoint(x: s * 0.53, y: cy)) }.stroke(tinta.opacity(0.6), style: traco)
      case .normal:
        Path { c in
          c.move(to: CGPoint(x: s * 0.445, y: cy - s * 0.01))
          c.addQuadCurve(to: CGPoint(x: s * 0.555, y: cy - s * 0.01), control: CGPoint(x: s * 0.5, y: cy + s * 0.05))
        }.stroke(tinta, style: traco)
      }
    }
    .frame(width: s, height: s)
    .allowsHitTesting(false)
  }
}

/// O acessório do papel, em traço escuro (lê bem sobre qualquer cor do corpo).
private struct DesenhoAcessorio: View {
  let acessorio: Acessorio
  let forma: String
  let tamanho: CGFloat
  var luz = false

  var body: some View {
    let s = tamanho
    let tinta = Color(white: 0.1)
    let ouro = Color(hex: "#ffc94a")
    let topo = s * (forma == "gota" ? 0.12 : (forma == "fantasma" ? 0.1 : 0.06))
    ZStack {
      switch acessorio {
      case .coroa:
        Path { c in
          let w = s * 0.34, h = s * 0.2, x0 = s * 0.5 - w / 2, y0 = topo + s * 0.04
          c.move(to: CGPoint(x: x0, y: y0))
          c.addLine(to: CGPoint(x: x0 + w * 0.12, y: y0 - h))
          c.addLine(to: CGPoint(x: x0 + w * 0.32, y: y0 - h * 0.45))
          c.addLine(to: CGPoint(x: x0 + w * 0.5, y: y0 - h * 1.15))
          c.addLine(to: CGPoint(x: x0 + w * 0.68, y: y0 - h * 0.45))
          c.addLine(to: CGPoint(x: x0 + w * 0.88, y: y0 - h))
          c.addLine(to: CGPoint(x: x0 + w, y: y0))
          c.closeSubpath()
        }
        .fill(ouro)
        .overlay(Path { c in
          let w = s * 0.34, h = s * 0.2, x0 = s * 0.5 - w / 2, y0 = topo + s * 0.04
          c.move(to: CGPoint(x: x0, y: y0))
          c.addLine(to: CGPoint(x: x0 + w * 0.12, y: y0 - h))
          c.addLine(to: CGPoint(x: x0 + w * 0.32, y: y0 - h * 0.45))
          c.addLine(to: CGPoint(x: x0 + w * 0.5, y: y0 - h * 1.15))
          c.addLine(to: CGPoint(x: x0 + w * 0.68, y: y0 - h * 0.45))
          c.addLine(to: CGPoint(x: x0 + w * 0.88, y: y0 - h))
          c.addLine(to: CGPoint(x: x0 + w, y: y0))
          c.closeSubpath()
        }.stroke(Color(hex: "#9a6a00"), style: StrokeStyle(lineWidth: max(0.6, s * 0.018), lineJoin: .round)))
      case .oculos:
        let y = s * alturaOlhos(forma), d = s * distanciaOlhos(forma), r = s * 0.115
        Path { c in
          c.addEllipse(in: CGRect(x: s * 0.5 - d - r, y: y - r, width: 2 * r, height: 2 * r))
          c.addEllipse(in: CGRect(x: s * 0.5 + d - r, y: y - r, width: 2 * r, height: 2 * r))
          c.move(to: CGPoint(x: s * 0.5 - d + r, y: y - r * 0.2))
          c.addQuadCurve(to: CGPoint(x: s * 0.5 + d - r, y: y - r * 0.2), control: CGPoint(x: s * 0.5, y: y - r * 0.7))
        }
        .stroke(tinta, style: StrokeStyle(lineWidth: max(1, s * 0.04), lineCap: .round))
      case .antena:
        Path { c in
          c.move(to: CGPoint(x: s * 0.5, y: topo + s * 0.04))
          c.addQuadCurve(to: CGPoint(x: s * 0.6, y: topo - s * 0.15), control: CGPoint(x: s * 0.49, y: topo - s * 0.08))
        }
        .stroke(tinta.opacity(0.85), style: StrokeStyle(lineWidth: max(1.2, s * 0.05), lineCap: .round))
        Circle().fill(luz ? Color(hex: "#ff6b5e") : ouro).overlay(Circle().strokeBorder(tinta.opacity(0.7), lineWidth: max(0.6, s * 0.022)))
          .frame(width: s * 0.17, height: s * 0.17).position(x: s * 0.61, y: topo - s * 0.17)
      case .fones:
        let y = s * alturaOlhos(forma)
        Path { c in
          c.addArc(center: CGPoint(x: s * 0.5, y: y), radius: s * 0.4, startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
        }
        .stroke(tinta.opacity(0.85), style: StrokeStyle(lineWidth: max(1, s * 0.045), lineCap: .round))
        ForEach([-1.0, 1.0], id: \.self) { lado in
          RoundedRectangle(cornerRadius: s * 0.04, style: .continuous).fill(tinta.opacity(0.9))
            .frame(width: s * 0.1, height: s * 0.2)
            .position(x: s * (0.5 + CGFloat(lado) * 0.39), y: y + s * 0.02)
        }
      case .lupa:
        // Na mão esquerda (o canto direito de baixo é do ponto de estado).
        let c0 = CGPoint(x: s * 0.2, y: s * 0.74)
        Path { c in
          c.addEllipse(in: CGRect(x: c0.x - s * 0.11, y: c0.y - s * 0.11, width: s * 0.22, height: s * 0.22))
          c.move(to: CGPoint(x: c0.x - s * 0.08, y: c0.y + s * 0.08))
          c.addLine(to: CGPoint(x: c0.x - s * 0.18, y: c0.y + s * 0.18))
        }
        .stroke(tinta, style: StrokeStyle(lineWidth: max(1, s * 0.045), lineCap: .round))
        Circle().fill(Color.white.opacity(0.6)).frame(width: s * 0.17, height: s * 0.17).position(c0)
      case .boina:
        Ellipse().fill(Color(hex: "#3a3f58"))
          .frame(width: s * 0.46, height: s * 0.18)
          .rotationEffect(.degrees(-10))
          .position(x: s * 0.46, y: topo + s * 0.02)
        Capsule().fill(Color(hex: "#3a3f58")).frame(width: s * 0.025, height: s * 0.07).position(x: s * 0.47, y: topo - s * 0.08)
      case .nenhum:
        EmptyView()
      }
    }
    .frame(width: s, height: s)
    .allowsHitTesting(false)
  }
}
