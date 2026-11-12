import Cocoa
import SwiftTerm

// O que há sob o mouse no terminal — um caminho de pasta ou arquivo, ou um link — e o menu de
// contexto que oferece o que fazer com ele (abrir no Finder, no navegador, mencionar no compose…).
// ⌘-clique abre direto. O duplo clique do terminal já seleciona o caminho ou o link inteiro.

struct Alvo: Equatable {
  enum Tipo: String { case url, arquivo, pasta }
  let tipo: Tipo
  let texto: String       // como aparece na tela
  let caminho: String     // caminho absoluto, ou o link
  var linha: Int? = nil   // "arquivo.swift:42"

  var ehHTML: Bool { tipo == .arquivo && ["html", "htm"].contains((caminho as NSString).pathExtension.lowercased()) }
  var url: URL? { tipo == .url ? URL(string: caminho) : URL(fileURLWithPath: caminho) }
}

enum Detector {
  private static let limites = CharacterSet(charactersIn: " \t\"'`<>()[]{}|=,;│┃")
  private static let sobras = CharacterSet(charactersIn: ".,;:!?)]}>'\"`")

  /// Procura um link ou um caminho que exista em disco na posição `coluna` (em caracteres) de `linha`.
  static func alvo(em linha: String, coluna: Int, cwd: String) -> Alvo? {
    let cs = Array(linha)
    guard !cs.isEmpty else { return nil }
    let col = min(max(0, coluna), cs.count - 1)
    if let u = url(cs, col) { return u }
    // 1) A "palavra" sob o mouse (sem espaços).
    var a = col, b = col
    if cs[col] == " " { return nil }
    while a > 0, !ehLimite(cs[a - 1]) { a -= 1 }
    while b < cs.count - 1, !ehLimite(cs[b + 1]) { b += 1 }
    if let r = existente(String(cs[a...b]), cwd: cwd) { return r }
    // 2) Caminho com espaços: de cada começo possível ("/" ou "~/") antes do mouse até cada
    //    fim de palavra depois dele; vale o mais longo que existir.
    var comecos: [Int] = []
    var i = col
    while i >= 0 {
      if (cs[i] == "/" || cs[i] == "~") && (i == 0 || ehLimite(cs[i - 1])) { comecos.append(i) }
      i -= 1
    }
    var fins: [Int] = []
    var j = cs.count - 1
    while j >= col {
      if j == cs.count - 1 || cs[j + 1] == " " { if cs[j] != " " { fins.append(j) } }
      j -= 1
    }
    for c in comecos.reversed().prefix(4) {
      for f in fins.prefix(12) where f > c {
        if let r = existente(String(cs[c...f]), cwd: cwd) { return r }
      }
    }
    return nil
  }

  private static func ehLimite(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { limites.contains($0) } }

  private static func url(_ cs: [Character], _ col: Int) -> Alvo? {
    var a = col, b = col
    func ok(_ c: Character) -> Bool { !(c == " " || c == "\t" || c == "<" || c == ">" || c == "\"" || c == "`" || c == "│") }
    guard ok(cs[col]) else { return nil }
    while a > 0, ok(cs[a - 1]) { a -= 1 }
    while b < cs.count - 1, ok(cs[b + 1]) { b += 1 }
    var s = String(cs[a...b])
    guard let r = s.range(of: #"(https?|file)://"#, options: .regularExpression) ?? s.range(of: "www.") else { return nil }
    s = String(s[r.lowerBound...])
    while let u = s.unicodeScalars.last, sobras.contains(u) {
      if u == ")" && s.contains("(") { break }
      s.removeLast()
    }
    guard s.count > 8 else { return nil }
    if s.hasPrefix("file://"), let u = URL(string: s) { return existente(u.path, cwd: "/") }
    return Alvo(tipo: .url, texto: s, caminho: s.hasPrefix("www.") ? "https://" + s : s)
  }

  /// O texto é um caminho que existe? (aceita ~, relativo à pasta do painel e sufixo :linha[:coluna])
  static func existente(_ bruto: String, cwd: String) -> Alvo? {
    var s = bruto.trimmingCharacters(in: .whitespaces)
    while let u = s.unicodeScalars.first, CharacterSet(charactersIn: "\"'`([{<").contains(u) { s.removeFirst() }
    var linha: Int?
    for _ in 0..<6 {
      guard !s.isEmpty, s != "/", s != ".", s != ".." else { return nil }
      if let r = resolver(s, cwd: cwd, linha: linha, texto: s) { return r }
      // Tira ":42" / ":42:7" do fim, depois a pontuação que sobrou.
      if let m = s.range(of: #":(\d+)(:\d+)?:?$"#, options: .regularExpression) {
        linha = Int(s[m].dropFirst().prefix { $0.isNumber })
        s = String(s[..<m.lowerBound])
        continue
      }
      guard let u = s.unicodeScalars.last, sobras.contains(u) else { return nil }
      s.removeLast()
    }
    return nil
  }

  private static func resolver(_ s: String, cwd: String, linha: Int?, texto: String) -> Alvo? {
    // Uma palavra solta ("build", "src") só conta se tiver cara de caminho ou de arquivo.
    let temCara = s.contains("/") || s.hasPrefix("~") || (s.contains(".") && !s.hasSuffix("."))
    guard temCara, s.count < 1024 else { return nil }
    var p = (s as NSString).expandingTildeInPath
    if !p.hasPrefix("/") { p = (cwd as NSString).appendingPathComponent(p) }
    p = (p as NSString).standardizingPath
    var ehDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: p, isDirectory: &ehDir) else { return nil }
    return Alvo(tipo: ehDir.boolValue ? .pasta : .arquivo, texto: texto, caminho: p, linha: linha)
  }
}

extension Painel {
  /// Link ou caminho sob um ponto do terminal (coordenadas da view do terminal).
  func alvo(em ponto: NSPoint) -> Alvo? {
    guard let v = view, let snap = v.terminalContentSnapshot(region: .viewport), !snap.rows.isEmpty else { return nil }
    let cols = max(1, snap.dimensions.cols), linhas = max(1, snap.dimensions.rows)
    let ideal = v.getOptimalFrameSize()
    let alturaCel = ideal.height / CGFloat(linhas)
    let larguraCel = min(ideal.width, v.bounds.width) / CGFloat(cols)
    let linhaTela = Int((v.bounds.height - ponto.y) / alturaCel)
    let col = Int(ponto.x / larguraCel)
    guard linhaTela >= 0, linhaTela < snap.rows.count, col >= 0, col < cols else { return nil }
    func texto(_ i: Int) -> (String, [Int]) {
      // Texto da linha + para cada célula, a posição do caractere correspondente.
      var s = "", mapa: [Int] = []
      var n = 0
      var pular = 0
      for c in snap.rows[i].cells {
        if pular > 0 { pular -= 1; mapa.append(max(0, n - 1)); continue }
        mapa.append(n)
        s += c.text.isEmpty || c.text == "\u{0}" ? " " : c.text
        n += max(1, c.text.count)
        if c.width > 1 { pular = c.width - 1 }
      }
      return (s, mapa)
    }
    // Linha lógica: junta as linhas que o terminal quebrou por falta de largura.
    var primeira = linhaTela
    while primeira > 0, snap.rows[primeira].isWrapped { primeira -= 1 }
    var ultima = linhaTela
    while ultima + 1 < snap.rows.count, snap.rows[ultima + 1].isWrapped { ultima += 1 }
    var inteira = "", posicao = 0
    for i in primeira...ultima {
      let (s, mapa) = texto(i)
      if i == linhaTela { posicao = inteira.count + (col < mapa.count ? mapa[col] : s.count) }
      inteira += i == ultima ? s : s.padding(toLength: max(s.count, cols), withPad: " ", startingAt: 0)
    }
    if let a = Detector.alvo(em: inteira, coluna: posicao, cwd: cwd) { return a }
    // Programas como o Claude quebram o caminho eles mesmos (sem a marca de quebra): tenta
    // emendar com a linha de baixo e com a de cima.
    let (atual, mapa) = texto(linhaTela)
    let aparada = atual.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    let pos = col < mapa.count ? mapa[col] : atual.count
    if linhaTela + 1 < snap.rows.count {
      let baixo = texto(linhaTela + 1).0.trimmingCharacters(in: .whitespaces)
      if let a = Detector.alvo(em: aparada + baixo, coluna: min(pos, aparada.count - 1), cwd: cwd) { return a }
    }
    if linhaTela > 0 {
      let cima = texto(linhaTela - 1).0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
      let recuo = atual.prefix { $0 == " " }.count
      if pos >= recuo, let a = Detector.alvo(em: cima + atual.dropFirst(recuo), coluna: cima.count + pos - recuo, cwd: cwd) { return a }
    }
    return nil
  }

  /// Último comando (opcional) e a saída dele, capturados pelas marcas OSC 133.
  func textoDoUltimoResultado(comComando: Bool) -> String {
    guard let r = ultimoResultado else { return "" }
    let saida = r.saida.trimmingCharacters(in: .newlines)
    return comComando && !r.comando.isEmpty ? "$ \(r.comando)\n\(saida)" : saida
  }

  /// A última coisa que o agente escreveu (o último balão dele na vista de conversa).
  func ultimaResposta() -> String? {
    baloesConversa().last { !$0.meu && !$0.texto.isEmpty }?.texto
  }

  /// ⇧⌘C: o resultado mais útil para colar em outro lugar.
  func copiarUltimoResultado() {
    if tipoAgente != nil { loja.copiar(ultimaResposta() ?? "", aviso: "Resposta copiada") }
    else { loja.copiar(textoDoUltimoResultado(comComando: true), aviso: "Comando e saída copiados") }
  }

  /// ⌘-clique: abre o link no navegador, o arquivo no app padrão, a pasta no Finder.
  func abrir(_ a: Alvo) {
    guard let u = a.url else { return }
    NSWorkspace.shared.open(u)
  }
}

/// Item de menu que roda um bloco.
private final class AcaoDeMenu: NSObject {
  let rodar: () -> Void
  init(_ r: @escaping () -> Void) { rodar = r }
  @objc func disparar(_ s: Any?) { rodar() }
}

@MainActor
enum MenuTerminal {
  static func copiar(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
  }

  /// App padrão para abrir links (o navegador).
  static var navegador: URL? { NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) }

  static func abrirNoNavegador(_ u: URL) {
    guard let nav = navegador else { NSWorkspace.shared.open(u); return }
    NSWorkspace.shared.open([u], withApplicationAt: nav, configuration: NSWorkspace.OpenConfiguration())
  }

  static func montar(painel p: Painel, alvo: Alvo?) -> NSMenu {
    let loja = p.loja
    let m = NSMenu()
    m.autoenablesItems = false
    @discardableResult func item(_ titulo: String, _ simbolo: String? = nil, ligado: Bool = true, _ acao: @escaping () -> Void) -> NSMenuItem {
      let alvoItem = AcaoDeMenu(acao)
      let i = NSMenuItem(title: titulo, action: #selector(AcaoDeMenu.disparar(_:)), keyEquivalent: "")
      i.target = alvoItem
      i.representedObject = alvoItem        // o menu segura o alvo
      i.isEnabled = ligado
      if let simbolo { i.image = NSImage(systemSymbolName: simbolo, accessibilityDescription: nil) }
      m.addItem(i)
      return i
    }
    func cabecalho(_ texto: String, _ icone: NSImage?) {
      let i = NSMenuItem(title: texto.count > 64 ? "…" + texto.suffix(62) : texto, action: nil, keyEquivalent: "")
      i.isEnabled = false
      if let icone { icone.size = NSSize(width: 16, height: 16); i.image = icone }
      m.addItem(i)
    }

    if let a = alvo, let u = a.url {
      switch a.tipo {
      case .url:
        cabecalho(a.caminho, NSImage(systemSymbolName: "link", accessibilityDescription: nil))
        item("Abrir no navegador", "safari") { abrirNoNavegador(u) }
        item("Copiar link", "doc.on.doc") { copiar(a.caminho) }
        item("Mencionar no compose", "at") { p.inserirNoCompose(a.caminho + " "); p.focarCompose() }
      case .arquivo:
        cabecalho(Loja.encurtar(a.caminho), NSWorkspace.shared.icon(forFile: a.caminho))
        let app = NSWorkspace.shared.urlForApplication(toOpen: u).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        item(app.map { "Abrir com \($0)" } ?? "Abrir com o app padrão", "arrow.up.forward.app") { NSWorkspace.shared.open(u) }
        if a.ehHTML { item("Abrir no navegador", "safari") { abrirNoNavegador(u) } }
        item("Mostrar no Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        item("Copiar caminho", "doc.on.doc") { copiar(a.caminho) }
        item("Mencionar no compose", "at") { p.mencionarNoCompose(caminho: a.caminho); p.focarCompose() }
        item("Novo terminal na pasta do arquivo", "terminal") { loja.criarAba(cwd: (a.caminho as NSString).deletingLastPathComponent) }
      case .pasta:
        cabecalho(Loja.encurtar(a.caminho), NSWorkspace.shared.icon(forFile: a.caminho))
        item("Abrir no Finder", "folder") { NSWorkspace.shared.open(u) }
        item("Novo terminal nesta pasta", "terminal") { loja.criarAba(cwd: a.caminho) }
        item("Ir para esta pasta (cd)", "arrow.right.circle", ligado: p.noPrompt) { p.escrever("\u{15} cd \(Compose.entreAspas(a.caminho))\r") }
        item("Copiar caminho", "doc.on.doc") { copiar(a.caminho) }
        item("Mencionar no compose", "at") { p.mencionarNoCompose(caminho: a.caminho + "/"); p.focarCompose() }
      }
      m.addItem(.separator())
    }

    let selecao = p.view?.selectionActive == true ? p.view?.getSelection() : nil
    item("Copiar", "doc.on.doc", ligado: selecao?.isEmpty == false) { if let s = selecao { loja.copiar(s) } }
    // Mais formas de copiar, sem precisar selecionar com o mouse.
    let sub = NSMenu()
    sub.autoenablesItems = false
    func itemSub(_ titulo: String, _ simbolo: String, ligado: Bool = true, _ acao: @escaping () -> Void) {
      let alvoItem = AcaoDeMenu(acao)
      let i = NSMenuItem(title: titulo, action: #selector(AcaoDeMenu.disparar(_:)), keyEquivalent: "")
      i.target = alvoItem; i.representedObject = alvoItem; i.isEnabled = ligado
      i.image = NSImage(systemSymbolName: simbolo, accessibilityDescription: nil)
      sub.addItem(i)
    }
    if let s = selecao, !s.isEmpty {
      itemSub("Seleção como bloco de código", "chevron.left.forwardslash.chevron.right") { loja.copiar("```\n\(s)\n```") }
      itemSub("Seleção numa linha só", "arrow.left.and.right.text.vertical") {
        loja.copiar(s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " "))
      }
      sub.addItem(.separator())
    }
    if p.tipoAgente != nil {
      let resposta = p.ultimaResposta()
      itemSub("Última resposta do agente  ⇧⌘C", "text.bubble", ligado: resposta != nil) { loja.copiar(resposta ?? "") }
    } else {
      let r = p.ultimoResultado
      itemSub("Último comando e a saída  ⇧⌘C", "terminal", ligado: r != nil) { loja.copiar(p.textoDoUltimoResultado(comComando: true)) }
      itemSub("Só a saída do último comando", "text.alignleft", ligado: r != nil) { loja.copiar(p.textoDoUltimoResultado(comComando: false)) }
      itemSub("Só o último comando", "chevron.right", ligado: r?.comando.isEmpty == false) { loja.copiar(r?.comando ?? "") }
    }
    itemSub("Tela visível", "rectangle.dashed") { loja.copiar(p.texto(linhas: 0)) }
    itemSub("Tudo (histórico inteiro)", "doc.plaintext") { loja.copiar(p.texto(linhas: nil)) }
    itemSub("Pasta atual", "folder") { loja.copiar(p.cwd) }
    let raiz = NSMenuItem(title: "Copiar…", action: nil, keyEquivalent: "")
    raiz.image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: nil)
    raiz.submenu = sub
    m.addItem(raiz)
    item("Colar", "doc.on.clipboard", ligado: NSPasteboard.general.string(forType: .string) != nil) { if let v = p.view { v.paste(v) } }
    if let s = selecao, !s.isEmpty {
      item("Levar a seleção para o compose", "text.insert") { p.inserirNoCompose(s + " "); p.focarCompose() }
    }
    item("Selecionar tudo", "selection.pin.in.out") { p.view?.selectAll(nil) }
    m.addItem(.separator())
    item("Escrever no compose  ⌘E", "square.and.pencil") { p.alternarFocoDoCompose() }
    item("Dividir à direita", "rectangle.split.2x1") { loja.focar(p); _ = loja.dividir(horizontal: true) }
    item("Dividir abaixo", "rectangle.split.1x2") { loja.focar(p); _ = loja.dividir(horizontal: false) }
    if (p.aba?.arvore.folhas.count ?? 1) > 1 {
      item(p.aba?.maximizado == p.id ? "Restaurar divisões" : "Maximizar painel", "arrow.up.left.and.arrow.down.right") { loja.focar(p); loja.maximizar() }
    }
    item("Limpar a tela", "eraser") { p.view?.clearScrollback(); if p.noPrompt { p.escrever("\u{0c}") } }
    m.addItem(.separator())
    item("Renomear a aba…", "pencil") { if let a = p.aba { loja.renomear(a) } }
    item("Mostrar a pasta no Finder", "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: p.cwd) }
    item("Reiniciar a sessão", "arrow.clockwise") { loja.reiniciarAgente(p) }
    item("Fechar o painel", "xmark") { loja.fecharPainel(p) }
    return m
  }

  /// Clique direito num terminal.
  static func mostrar(painel p: Painel, evento e: NSEvent) {
    guard let v = p.view else { return }
    let ponto = v.convert(e.locationInWindow, from: nil)
    let m = montar(painel: p, alvo: p.alvo(em: ponto))
    NSMenu.popUpContextMenu(m, with: e, for: v)
  }

  /// Teste (`orion depurar menu`): abre o menu de um alvo num ponto do terminal e o fecha
  /// sozinho depois de `segundos` — para capturas de tela sem mouse.
  static func mostrarParaTeste(painel p: Painel, alvo: Alvo?, segundos: Double) {
    guard let v = p.view else { return }
    let m = montar(painel: p, alvo: alvo)
    let t = Timer(timeInterval: segundos, repeats: false) { _ in m.cancelTrackingWithoutAnimation() }
    RunLoop.main.add(t, forMode: .common)
    m.popUp(positioning: nil, at: NSPoint(x: 60, y: v.bounds.height - 40), in: v)
  }
}
