import Cocoa
import SwiftUI

/// Mostra a árvore da aba ativa. Os terminais (CaixaPainel) e as divisões de cada aba são
/// montados uma vez e guardados: trocar de aba ou de workspace só troca a raiz na tela, e mudar
/// o foco entre painéis só atualiza o destaque — nada é recriado.
final class AreaTerminais: NSView {
  unowned let loja: Loja
  private var raiz: NSView?
  private var abaNaTela: String?
  private var workspaceNaTela: String?
  private var vazio: NSHostingView<EstadoVazio>?
  /// Folga em volta dos cartões (a sombra deles precisa de espaço dentro desta view).
  var margens = NSEdgeInsets(top: 2, left: 6, bottom: 10, right: 10) { didSet { needsLayout = true } }
  /// Raiz montada de cada aba, válida enquanto a árvore (versão) e o painel maximizado não mudam.
  private var montadas: [String: (versao: Int, maximizado: String?, view: NSView)] = [:]

  @MainActor init(loja: Loja) {
    self.loja = loja
    super.init(frame: .zero)
    loja.aoMudarLayout = { [weak self] in self?.remontar() }
    loja.aoMudarFoco = { [weak self] in self?.atualizarFoco() }
    loja.tamanhoDaArea = { [weak self] in self?.bounds.size ?? .zero }
  }

  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }

  @MainActor func remontar() {
    let vivas = Set(loja.abas.map(\.id))
    for id in montadas.keys where !vivas.contains(id) { montadas[id] = nil }
    guard let a = loja.abaAtiva else {
      raiz?.removeFromSuperview()
      raiz = nil
      abaNaTela = nil
      if vazio == nil { vazio = NSHostingView(rootView: EstadoVazio(loja: loja)) }
      if vazio!.superview !== self { addSubview(vazio!) }
      needsLayout = true
      return
    }
    vazio?.removeFromSuperview()
    let v: NSView
    if let m = montadas[a.id], m.versao == a.versaoArvore, m.maximizado == a.maximizado {
      v = m.view
    } else {
      let no = a.maximizado.flatMap { a.arvore.folha($0) } ?? a.arvore
      v = construir(no, aba: a)
      montadas[a.id] = (a.versaoArvore, a.maximizado, v)
    }
    // Trocar de workspace: a tela desliza um pouco e aparece (curto; trocar de aba é instantâneo).
    let ws = a.workspace
    if let antes = workspaceNaTela, antes != ws, window != nil {
      wantsLayer = true
      let ordem = loja.workspaces.map(\.id)
      let desce = (ordem.firstIndex(of: ws) ?? 0) >= (ordem.firstIndex(of: antes) ?? 0)
      let t = CATransition()
      t.type = .push
      t.subtype = desce ? .fromTop : .fromBottom
      t.duration = 0.2
      t.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer?.masksToBounds = true          // só durante a troca (fora dela, a sombra dos cartões precisa da folga)
      layer?.add(t, forKey: "workspace")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in self?.layer?.masksToBounds = false }
    }
    workspaceNaTela = ws
    if raiz !== v || v.superview !== self {
      // Caixas fora da tela param de desenhar (o terminal continua recebendo dados).
      // A raiz antiga pode ter sido reaproveitada dentro da nova (dividir um painel único).
      if let r = raiz, r !== v, r.superview === self { r.removeFromSuperview() }
      addSubview(v)
      raiz = v
    }
    abaNaTela = a.id
    needsLayout = true
    layoutSubtreeIfNeeded()
    atualizarFoco()
  }

  /// Só o destaque do painel ativo e o foco do teclado.
  @MainActor func atualizarFoco() {
    guard let a = loja.abaAtiva, a.id == abaNaTela else { return }
    let dividida = a.maximizado == nil && a.arvore.tipo == .divisao
    for n in a.arvore.folhas {
      guard let c = loja.painelExistente(n.id)?.caixa else { continue }
      if c.comBorda != dividida { c.comBorda = dividida }
      let ativo = a.painelAtivo == n.id
      if c.destacado != ativo { c.destacado = ativo }
    }
    if let p = loja.painelAtivo, let tv = p.view {
      let atual = window?.firstResponder
      if !(atual is NSTextView) && atual !== tv && !loja.quadroAberto && !loja.paletaAberta { window?.makeFirstResponder(tv) }
      if p.branch.isEmpty { p.atualizarGit() }
    }
  }

  /// Teste (`orion depurar arrasto`): refaz o que o arrasto de uma divisão faz, sem mouse —
  /// vários tamanhos seguidos com `arrastando` ligado e o assentamento no fim.
  @MainActor func simularArrasto(_ valores: [Double]) -> Bool {
    guard let d = raiz as? Divisao else { return false }
    loja.arrastando = true
    for v in valores {
      d.no.proporcao = v
      d.needsLayout = true
      d.layoutSubtreeIfNeeded()
    }
    loja.arrastando = false
    for p in loja.paineis.values { p.caixa?.assentar() }
    d.needsLayout = true
    layoutSubtreeIfNeeded()
    return true
  }

  @MainActor private func construir(_ no: No, aba: Aba) -> NSView {
    if no.tipo == .painel, let p = loja.painel(id: no.id, aba: aba) { return p.garantirCaixa() }
    let d = Divisao(no: no, loja: loja)
    d.adicionar(construir(no.a!, aba: aba), construir(no.b!, aba: aba))
    return d
  }

  override func layout() {
    super.layout()
    let util = backingAlignedRect(NSRect(x: margens.left, y: margens.top, width: max(10, bounds.width - margens.left - margens.right),
                                         height: max(10, bounds.height - margens.top - margens.bottom)), options: .alignAllEdgesNearest)
    raiz?.frame = util
    vazio?.frame = util
  }
}

/// Divisão em dois com alça arrastável. Duplo clique na alça volta a 50/50.
final class Divisao: NSView {
  let no: No
  unowned let loja: Loja
  private var a: NSView?, b: NSView?
  private let espessura: CGFloat = 10

  init(no: No, loja: Loja) {
    self.no = no
    self.loja = loja
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }

  func adicionar(_ x: NSView, _ y: NSView) {
    a = x; b = y
    addSubview(x); addSubview(y)
  }

  override func layout() {
    super.layout()
    guard let a, let b else { return }
    let p = CGFloat(no.proporcao)
    if no.horizontal {
      // Larguras e alturas inteiras: divisão em meia posição = letra borrada nos dois painéis.
      let w = ((bounds.width - espessura) * p).rounded()
      a.frame = NSRect(x: 0, y: 0, width: w, height: bounds.height)
      b.frame = NSRect(x: w + espessura, y: 0, width: bounds.width - w - espessura, height: bounds.height)
    } else {
      let h = ((bounds.height - espessura) * p).rounded()
      a.frame = NSRect(x: 0, y: 0, width: bounds.width, height: h)
      b.frame = NSRect(x: 0, y: h + espessura, width: bounds.width, height: bounds.height - h - espessura)
    }
  }

  private var alca: NSRect {
    let p = CGFloat(no.proporcao)
    if no.horizontal {
      let w = (bounds.width - espessura) * p
      return NSRect(x: w, y: 0, width: espessura, height: bounds.height)
    }
    let h = (bounds.height - espessura) * p
    return NSRect(x: 0, y: h, width: bounds.width, height: espessura)
  }

  override func resetCursorRects() {
    addCursorRect(alca, cursor: no.horizontal ? .resizeLeftRight : .resizeUpDown)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    if alca.contains(local) { return self }
    return super.hitTest(point)
  }

  override func mouseDown(with e: NSEvent) {
    if e.clickCount == 2 { no.proporcao = 0.5; needsLayout = true; loja.salvarDepois(); return }
    // Enquanto arrasta, os terminais agrupam o reflow e o aviso de tamanho ao programa
    // (veja CaixaPainel.layout e Painel.sizeChanged); ao soltar, tudo assenta de uma vez.
    MainActor.assumeIsolated { loja.arrastando = true }
    while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if ev.type == .leftMouseUp { break }
      let p = convert(ev.locationInWindow, from: nil)
      let v = no.horizontal ? p.x / bounds.width : p.y / bounds.height
      let nova = Double(min(0.88, max(0.12, v)))
      if abs(nova - no.proporcao) * Double(no.horizontal ? bounds.width : bounds.height) >= 1 {   // ignora movimento menor que 1 pt
        no.proporcao = nova
        needsLayout = true
        layoutSubtreeIfNeeded()
      }
    }
    MainActor.assumeIsolated { loja.arrastando = false }
    assentar(self)
    window?.invalidateCursorRects(for: self)
    loja.salvarDepois()
  }

  private func assentar(_ v: NSView) {
    for s in v.subviews {
      if let c = s as? CaixaPainel { c.assentar() } else { assentar(s) }
    }
    v.needsLayout = true
    layoutSubtreeIfNeeded()
  }
}

