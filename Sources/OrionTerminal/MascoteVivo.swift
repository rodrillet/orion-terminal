import SwiftUI
import AppKit
import QuartzCore

// MARK: - Mascote vivo: o mesmo desenho, animado pelo Core Animation
//
// Animar o mascote redesenhando o SwiftUI a cada quadro custava ~15% de CPU (cada quadro
// refazia o layout da janela). Aqui o desenho é feito uma vez só, em imagens (corpo e olhos
// separados), e o movimento — piscar, olhar em volta, respirar, o halo de quem trabalha, o "zz" de
// quem dorme — são animações de camada que rodam no servidor de janelas, sem acordar o app.
// Com o app em segundo plano as camadas congelam (speed 0); com "Reduzir movimento", nem existem.

/// Liga e desliga todos os mascotes vivos de uma vez (ajuste, app na frente ou não).
@MainActor
final class RelogioMascote {
  static let shared = RelogioMascote()
  static let mudou = Notification.Name("orion.mascotes.rodando")
  /// Só na cópia de desenvolvimento (testes sem o app na frente).
  static let sempre = Armazem.desenvolvimento && ProcessInfo.processInfo.environment["ORION_ANIMAR_SEMPRE"] == "1"
  var ligado = true { didSet { if ligado != oldValue { avisar() } } }
  var rodando: Bool { ligado && (NSApp.isActive || Self.sempre) && !DesenhoMascote.semMovimento }

  private init() {
    for n in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
      NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in MainActor.assumeIsolated { RelogioMascote.shared.avisar() } }
    }
  }

  private func avisar() { NotificationCenter.default.post(name: Self.mudou, object: nil) }
}

struct MascoteVivo: NSViewRepresentable {
  let d: DesenhoMascote

  func makeNSView(context: Context) -> VistaMascoteVivo { VistaMascoteVivo() }

  func updateNSView(_ v: VistaMascoteVivo, context: Context) {
    v.configurar(d, escala: v.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
  }
}

final class VistaMascoteVivo: NSView {
  private let raiz = CALayer()        // pulo
  private let folego = CALayer()      // respiração (escala ancorada na base)
  private let corpo = CALayer()
  private let olhosFora = CALayer()   // para onde olha
  private let olhosDentro = CALayer() // piscar e expressão
  private let halo = CAGradientLayer()
  private var zs: [CATextLayer] = []
  private var chave = ""
  private var humor: Humor?
  private var observador: NSObjectProtocol?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = false
    layer?.addSublayer(raiz)
    raiz.addSublayer(halo)
    raiz.addSublayer(folego)
    folego.addSublayer(corpo)
    folego.addSublayer(olhosFora)
    olhosFora.addSublayer(olhosDentro)
    halo.type = .radial
    halo.startPoint = CGPoint(x: 0.5, y: 0.5)
    halo.endPoint = CGPoint(x: 1, y: 1)
    observador = NotificationCenter.default.addObserver(forName: RelogioMascote.mudou, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.aplicarRodando() }
    }
  }

  required init?(coder: NSCoder) { fatalError() }
  deinit { if let o = observador { NotificationCenter.default.removeObserver(o) } }

  override var isFlipped: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }     // cliques e hover passam para o SwiftUI

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    aplicarRodando()
  }

  // MARK: Montagem

  func configurar(_ d: DesenhoMascote, escala: CGFloat) {
    let s = d.tamanho
    let nova = "\(d.forma)|\(d.cor)|\(s)|\(d.humor)|\(d.acessorio)|\(escala)|\(d.semente)"
    guard nova != chave else { return }
    let humorAntes = humor
    chave = nova
    humor = d.humor
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let pad = s * VistaMascoteVivo.margem
    let lado = s + 2 * pad
    let quadro = CGRect(x: -pad, y: -pad, width: lado, height: lado)
    for l in [raiz, folego] { l.frame = bounds.isEmpty ? CGRect(x: 0, y: 0, width: s, height: s) : bounds }
    raiz.frame = CGRect(x: 0, y: 0, width: s, height: s)
    folego.frame = raiz.bounds
    folego.anchorPoint = CGPoint(x: 0.5, y: 0)
    folego.position = CGPoint(x: s / 2, y: 0)
    corpo.frame = quadro
    corpo.contents = VistaMascoteVivo.imagem(d, partes: .semOlhos, feliz: false, escala: escala)
    corpo.contentsScale = escala
    olhosFora.frame = quadro
    olhosDentro.frame = olhosFora.bounds
    // O piscar fecha os olhos em volta da linha deles.
    let yOlho = 1 - (pad + s * VistaMascoteVivo.alturaOlhos(d.forma)) / lado
    olhosDentro.anchorPoint = CGPoint(x: 0.5, y: yOlho)
    olhosDentro.position = CGPoint(x: lado / 2, y: yOlho * lado)
    let olhos = VistaMascoteVivo.imagem(d, partes: .soOlhos, feliz: false, escala: escala)
    olhosDentro.contents = olhos
    olhosDentro.contentsScale = escala
    let base = NSColor(hex: d.cor)
    halo.colors = [base.withAlphaComponent(0.5).cgColor, base.withAlphaComponent(0).cgColor]
    halo.locations = [0.42, 1]
    halo.frame = CGRect(x: -s * 0.225, y: -s * 0.225, width: s * 1.45, height: s * 1.45)
    halo.isHidden = !(d.humor == .focado && d.halo && s >= 18)
    zs.forEach { $0.removeFromSuperlayer() }
    zs = []
    if d.humor == .dormindo && s >= 20 {
      for (i, f) in [0.24, 0.18].enumerated() {
        let z = CATextLayer()
        z.string = "z"
        z.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
        z.fontSize = max(7, s * f)
        z.foregroundColor = NSColor.secondaryLabelColor.cgColor
        z.contentsScale = escala
        z.alignmentMode = .center
        z.frame = CGRect(x: s * (i == 0 ? 0.74 : 0.9), y: s * (i == 0 ? 0.78 : 0.96), width: s * 0.3, height: s * 0.3)
        raiz.addSublayer(z)
        zs.append(z)
      }
    }
    CATransaction.commit()
    animar(d, s: s, lado: lado, olhos: olhos, escala: escala)
    if d.humor == .atento, let antes = humorAntes, antes != .atento { pular(s) }
    aplicarRodando()
  }

  /// Respiro, olhar, piscar, expressão, halo e "zz" de cada humor.
  private func animar(_ d: DesenhoMascote, s: CGFloat, lado: CGFloat, olhos: CGImage?, escala: CGFloat) {
    for l in [folego, olhosFora, olhosDentro, halo] { l.removeAllAnimations() }
    let semente = d.semente
    let agora = CACurrentMediaTime()

    // Respiração: escala ancorada na base.
    let (periodo, amplitude): (Double, Double) = {
      switch d.humor {
      case .focado: return (2 * .pi / 4, 0.7)
      case .dormindo: return (2 * .pi / 1.1, 0.3)
      default: return (2 * .pi / 2.1, 0.35)
      }
    }()
    let resp = CAKeyframeAnimation(keyPath: "transform")
    let n = 16
    resp.values = (0...n).map { i -> NSValue in
      let sq = sin(Double(i) / Double(n) * 2 * .pi) * amplitude
      return NSValue(caTransform3D: CATransform3DMakeScale(1 + 0.035 * sq, 1 - 0.045 * sq, 1))
    }
    resp.duration = periodo
    resp.repeatCount = .infinity
    resp.timeOffset = semente.truncatingRemainder(dividingBy: periodo)
    folego.add(resp, forKey: "respiro")

    // Para onde olha.
    switch d.humor {
    case .normal, .focado:
      let passo = d.humor == .focado ? 1.2 : 2.6
      let ax = (d.humor == .focado ? 0.04 : 0.035) * s * 0.9, ay = (d.humor == .focado ? 0.015 : 0.02) * s * 0.7
      let alvos = 12
      var valores: [NSValue] = [], tempos: [NSNumber] = []
      var anterior = CGPoint.zero
      for k in 0..<alvos {
        let alvo = CGPoint(x: PoseMascote.ruido(k, semente) * ax, y: -PoseMascote.ruido(k + 100, semente) * ay)
        let t0 = Double(k) / Double(alvos)
        valores.append(NSValue(point: anterior)); tempos.append(NSNumber(value: t0))
        valores.append(NSValue(point: alvo)); tempos.append(NSNumber(value: t0 + 0.4 / Double(alvos)))
        anterior = alvo
      }
      valores.append(NSValue(point: .zero)); tempos.append(1)
      let olhar = CAKeyframeAnimation(keyPath: "transform.translation")
      olhar.values = valores
      olhar.keyTimes = tempos
      olhar.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: valores.count - 1)
      olhar.duration = passo * Double(alvos)
      olhar.repeatCount = .infinity
      olhar.timeOffset = semente * 3
      olhosFora.add(olhar, forKey: "olhar")
    case .atento:
      // Olha para cima e, de vez em quando, de lado.
      let cima = s * 0.025
      let olhar = CAKeyframeAnimation(keyPath: "transform.translation")
      olhar.values = [CGPoint(x: 0, y: cima), CGPoint(x: 0, y: cima), CGPoint(x: s * 0.03, y: cima), CGPoint(x: s * 0.03, y: cima),
                      CGPoint(x: 0, y: cima), CGPoint(x: 0, y: cima), CGPoint(x: -s * 0.03, y: cima), CGPoint(x: -s * 0.03, y: cima), CGPoint(x: 0, y: cima)]
        .map { NSValue(point: $0) }
      olhar.keyTimes = [0, 0.3, 0.33, 0.42, 0.45, 0.75, 0.78, 0.86, 0.89]
      olhar.duration = 16
      olhar.repeatCount = .infinity
      olhar.timeOffset = semente * 2
      olhosFora.add(olhar, forKey: "olhar")
    case .dormindo:
      break
    }

    // Piscar a cada ~3,9 s (cada agente no seu tempo) e, em repouso, um sorriso de olhos a cada 18 s.
    if d.humor != .dormindo {
      let piscar = CAKeyframeAnimation(keyPath: "transform.scale.y")
      let p = 3.9
      piscar.values = [1, 1, 0.12, 1]
      piscar.keyTimes = [0, NSNumber(value: 1 - 0.12 / p), NSNumber(value: 1 - 0.06 / p), 1]
      piscar.duration = p
      piscar.repeatCount = .infinity
      piscar.timeOffset = (semente * 1.7).truncatingRemainder(dividingBy: p)
      olhosDentro.add(piscar, forKey: "piscar")
    }
    if d.humor == .normal, let olhos, let feliz = VistaMascoteVivo.imagem(d, partes: .soOlhos, feliz: true, escala: escala) {
      let expr = CAKeyframeAnimation(keyPath: "contents")
      expr.values = [olhos, feliz, olhos]
      expr.keyTimes = [0, NSNumber(value: 1 - 1.7 / 18), 1]
      expr.calculationMode = .discrete
      expr.duration = 18
      expr.repeatCount = .infinity
      expr.timeOffset = (semente * 3).truncatingRemainder(dividingBy: 18)
      olhosDentro.add(expr, forKey: "expressao")
    }

    // Halo de quem trabalha: pulsa devagar.
    if !halo.isHidden {
      let pulso = CABasicAnimation(keyPath: "opacity")
      pulso.fromValue = 0.45; pulso.toValue = 1
      pulso.duration = 0.8; pulso.autoreverses = true; pulso.repeatCount = .infinity
      pulso.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      halo.add(pulso, forKey: "pulso")
    }

    // "zz": o de cima some e volta.
    for (i, z) in zs.enumerated() {
      let a = CAKeyframeAnimation(keyPath: "opacity")
      a.values = i == 0 ? [0.9, 0.9] : [0, 0.85, 0.85, 0]
      a.keyTimes = i == 0 ? [0, 1] : [0, 0.33, 0.66, 1]
      a.duration = 2.4; a.repeatCount = .infinity
      a.calculationMode = .discrete
      z.add(a, forKey: "zz")
      let sobe = CABasicAnimation(keyPath: "transform.translation.y")
      sobe.fromValue = 0; sobe.toValue = s * 0.06
      sobe.duration = 1.2; sobe.autoreverses = true; sobe.repeatCount = .infinity
      sobe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      sobe.beginTime = agora + Double(i) * 0.4
      z.add(sobe, forKey: "sobe")
    }
  }

  private func pular(_ s: CGFloat) {
    guard RelogioMascote.shared.rodando else { return }
    let a = CAKeyframeAnimation(keyPath: "transform.translation.y")
    a.values = [0, s * 0.14, 0, s * 0.04, 0]
    a.keyTimes = [0, 0.3, 0.6, 0.8, 1]
    a.duration = 0.5
    raiz.add(a, forKey: "pulo")
  }

  /// Congela (speed 0) ou solta as animações, mantendo a pose em que estavam.
  private func aplicarRodando() {
    guard let l = layer else { return }
    let rodar = RelogioMascote.shared.rodando && window != nil
    if rodar && l.speed == 0 {
      let pausa = l.timeOffset
      l.speed = 1; l.timeOffset = 0; l.beginTime = 0
      l.beginTime = l.convertTime(CACurrentMediaTime(), from: nil) - pausa
    } else if !rodar && l.speed != 0 {
      let t = l.convertTime(CACurrentMediaTime(), from: nil)
      l.speed = 0; l.timeOffset = t
    }
  }

  // MARK: Imagens

  static let margem: CGFloat = 0.45
  private static let cache = NSCache<NSString, CGImage>()

  static func alturaOlhos(_ forma: String) -> CGFloat {
    ["gota": 0.6, "fantasma": 0.47, "nuvem": 0.56, "flor": 0.53, "pilula": 0.42][forma] ?? 0.48
  }

  /// O desenho (sem os olhos, ou só os olhos) num quadro com margem para acessório e sombra.
  @MainActor static func imagem(_ d: DesenhoMascote, partes: DesenhoMascote.Partes, feliz: Bool, escala: CGFloat) -> CGImage? {
    let chave = "\(d.forma)|\(d.cor)|\(d.tamanho)|\(d.humor)|\(d.acessorio)|\(partes)|\(feliz)|\(escala)|\(Cor.claro)" as NSString
    if let c = cache.object(forKey: chave) { return c }
    let s = d.tamanho
    let pad = s * margem
    var pose = PoseMascote()
    pose.feliz = feliz
    let conteudo = d.desenho(pose: feliz ? pose : nil, partes: partes)
      .frame(width: s, height: s)
      .padding(pad)
      .frame(width: s + 2 * pad, height: s + 2 * pad)
    let r = ImageRenderer(content: conteudo)
    r.scale = escala
    guard let img = r.cgImage else { return nil }
    cache.setObject(img, forKey: chave)
    return img
  }
}
