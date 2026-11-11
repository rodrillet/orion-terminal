import Cocoa
import SwiftUI
import Observation
import ImageIO

// Compose: a caixa de escrita do app, uma por painel. Escreve-se nela como num chat —
// ↩ envia, ⇧↩ quebra a linha, ↑ / ↓ percorrem o histórico — e ela entende:
//   @  → menciona outro terminal/agente (anexa o contexto dele, ou manda a mensagem para ele),
//        uma pasta ou um arquivo (com autocomplete de caminho);
//   ⌘V, arrastar ou o clipe → anexa imagens (salvas em arquivo temporário; o agente recebe o
//        caminho, que é como o Claude Code e o Codex leem imagem) e arquivos.
// Convive com o teclado direto no terminal: ⌘E alterna o foco, esc devolve ao terminal.

struct Anexo: Identifiable, Equatable {
  enum Tipo: String { case imagem, contexto, destino }
  let id = UUID()
  let tipo: Tipo
  let valor: String      // caminho do arquivo (imagem) ou id do painel (contexto, destino)
  var rotulo: String
}

struct ItemMencao: Identifiable, Equatable {
  enum Tipo { case painel, pasta, arquivo }
  let id: String
  let tipo: Tipo
  let rotulo: String
  let detalhe: String
  let valor: String        // id do painel ou caminho absoluto
  var programa: String? = nil
  var estado: EstadoPainel? = nil
}

/// O que está sendo escrito num painel: texto, anexos e a lista de menções aberta.
@MainActor @Observable
final class Rascunho {
  var texto = ""
  var anexos: [Anexo] = []
  var itens: [ItemMencao] = []
  var mencaoAberta = false
  var sel = 0
  var focado = false
  var altura: CGFloat = 22
  /// Compose aberto/fechado à mão neste painel (nil = segue o ajuste).
  var manual: Bool?
  @ObservationIgnored var termo = ""
  @ObservationIgnored var inicioMencao = 0          // posição (UTF-16) do "@"
  @ObservationIgnored weak var campo: CampoTexto?
  @ObservationIgnored var posHistorico = -1
  @ObservationIgnored var antesDoHistorico = ""
  @ObservationIgnored var busca = 0                 // descarta resultados de buscas antigas

  var vazio: Bool { texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !anexos.contains { $0.tipo != .destino } }

  func definir(_ t: String) {
    texto = t
    if let c = campo, c.textoSerializado != t { c.string = t; c.recalcularAltura() }
  }

  func anexar(_ a: Anexo) {
    if anexos.contains(where: { $0.tipo == a.tipo && $0.valor == a.valor }) { return }
    anexos.append(a)
  }

  // MARK: Menções

  /// Olha o que há antes do cursor: se for "@algo" (sem espaço), abre a lista e busca.
  func atualizarMencao(_ painel: Painel) {
    guard let c = campo else { return }
    let s = c.string as NSString
    let cursor = c.selectedRange().location
    guard c.selectedRange().length == 0, cursor <= s.length else { fecharMencao(painel); return }
    var i = cursor - 1
    var achou = -1
    while i >= 0 {
      let ch = s.character(at: i)
      if ch == 0x40 { achou = i; break }                               // @
      if ch == 0x20 || ch == 0x0a || ch == 0x09 || ch == 0xFFFC { break }
      i -= 1
    }
    guard achou >= 0 else { fecharMencao(painel); return }
    if achou > 0 {
      let antes = s.character(at: achou - 1)
      if !(antes == 0x20 || antes == 0x0a || antes == 0x09 || antes == 0x28 || antes == 0xFFFC) { fecharMencao(painel); return }
    }
    inicioMencao = achou
    termo = s.substring(with: NSRange(location: achou + 1, length: cursor - achou - 1))
    buscar(painel)
  }

  private func buscar(_ painel: Painel) {
    busca += 1
    let n = busca
    let t = termo
    let ehCaminho = t.contains("/") || t.hasPrefix("~") || t.hasPrefix(".")
    var lista = ehCaminho ? [] : Mencoes.paineis(t, de: painel)
    lista += ehCaminho ? Mencoes.caminhos(t, cwd: painel.cwd) : Mencoes.daPasta(t, cwd: painel.cwd)
    mostrar(lista, painel)
    guard !ehCaminho, t.count >= 2 else { return }
    // Busca nas subpastas (fora da thread principal); entra na lista se ainda for a mesma busca.
    let cwd = painel.cwd
    DispatchQueue.global(qos: .userInitiated).async {
      let fundos = Mencoes.noProjeto(t, cwd: cwd)
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard self.busca == n, self.mencaoAberta else { return }
          let ja = Set(self.itens.map(\.id))
          let novos = fundos.filter { !ja.contains($0.id) }
          if !novos.isEmpty { self.mostrar(Array((self.itens + novos).prefix(14)), painel, manterSel: true) }
        }
      }
    }
  }

  private func mostrar(_ lista: [ItemMencao], _ painel: Painel, manterSel: Bool = false) {
    itens = lista
    sel = manterSel ? min(sel, max(0, lista.count - 1)) : 0
    mencaoAberta = true
    painel.caixa?.atualizarMencoes()
  }

  func fecharMencao(_ painel: Painel) {
    busca += 1
    guard mencaoAberta else { return }
    mencaoAberta = false
    itens = []
    painel.caixa?.atualizarMencoes()
  }

  /// Aceita o item escolhido. `destino`: (⌥↩) em vez de anexar o contexto do terminal, manda a
  /// mensagem para ele. `completar`: (⇥) numa pasta, entra nela e continua a lista.
  func aceitar(_ painel: Painel, indice: Int? = nil, destino: Bool = false, completar: Bool = false) {
    let i = indice ?? sel
    guard i >= 0, i < itens.count, let c = campo else { return }
    let it = itens[i]
    let cursor = c.selectedRange().location
    let faixa = NSRange(location: inicioMencao, length: max(0, cursor - inicioMencao))
    func trocar(_ novo: String) {
      if c.shouldChangeText(in: faixa, replacementString: novo) {
        c.replaceCharacters(in: faixa, with: novo)
        c.didChangeText()
      }
    }
    switch it.tipo {
    case .painel:
      guard let alvo = painel.loja.acharPainel(it.valor) else { return }
      let apelido = alvo.apelido
      if destino {
        anexar(Anexo(tipo: .destino, valor: alvo.id, rotulo: apelido))
        trocar("")
      } else {
        // Etiqueta dentro do texto: ao enviar, o contexto deste terminal vai junto.
        c.inserirEtiqueta(rotulo: apelido, marca: alvo.persona != nil ? "@" : "⌁", texto: "@\(apelido)", painel: alvo.id, em: faixa)
      }
      fecharMencao(painel)
    case .pasta, .arquivo:
      let ref = Compose.referencia(it.valor, cwd: painel.cwd)
      if it.tipo == .pasta && completar {
        trocar("@" + ref + "/")          // a lista continua, agora dentro da pasta
      } else {
        let alvo = ref + (it.tipo == .pasta ? "/" : "")
        c.inserirEtiqueta(rotulo: (alvo as NSString).lastPathComponent + (it.tipo == .pasta ? "/" : ""), marca: it.tipo == .pasta ? "📁" : "📄",
                          texto: Compose.mencao(alvo), painel: nil, em: faixa, dica: alvo)
        fecharMencao(painel)
      }
    }
  }

  // MARK: Histórico

  func historico(_ delta: Int, _ loja: Loja) {
    let h = loja.historicoCompose
    guard !h.isEmpty else { return }
    if posHistorico < 0 { antesDoHistorico = texto }
    let novo = posHistorico + delta
    if novo < 0 { posHistorico = -1; definir(antesDoHistorico); return }
    guard novo < h.count else { return }
    posHistorico = novo
    definir(h[novo])
    if let c = campo { c.setSelectedRange(NSRange(location: (c.string as NSString).length, length: 0)) }
  }

  // MARK: Enviar

  func enviar(_ painel: Painel) {
    guard !vazio else { return }
    fecharMencao(painel)
    // Terminais mencionados por etiqueta no texto: o contexto de cada um vai junto.
    var todos = anexos
    for e in campo?.etiquetas ?? [] {
      if let id = e.painelID, !todos.contains(where: { $0.tipo == .contexto && $0.valor == id }) {
        todos.append(Anexo(tipo: .contexto, valor: id, rotulo: String(e.texto.dropFirst())))
      }
    }
    painel.loja.enviarComposto(de: painel, texto: texto, anexos: todos)
    anexos = []
    posHistorico = -1
    definir("")
  }
}

// MARK: - Arquivos, imagens e contexto

enum Compose {
  /// Pasta temporária (sem espaços no caminho) onde ficam as imagens coladas e os contextos longos.
  static let pastaAnexos: URL = {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("orion-terminal", isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return u
  }()

  /// Apaga anexos com mais de três dias (rodado ao abrir o app).
  static func limparAnexosAntigos() {
    DispatchQueue.global(qos: .utility).async {
      let fm = FileManager.default
      guard let itens = try? fm.contentsOfDirectory(at: pastaAnexos, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
      let limite = Date().addingTimeInterval(-3 * 86400)
      for u in itens {
        let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        if d < limite { try? fm.removeItem(at: u) }
      }
    }
  }

  private static func carimbo() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f.string(from: Date()) + "-" + UUID().uuidString.prefix(4).lowercased()
  }

  static let extensoesDeImagem: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp"]
  static func ehImagem(_ caminho: String) -> Bool { extensoesDeImagem.contains((caminho as NSString).pathExtension.lowercased()) }

  /// Salva a imagem da área de transferência (ou de um arrasto) como PNG e devolve o caminho.
  static func salvarImagem(de pb: NSPasteboard) -> String? {
    var png = pb.data(forType: .png)
    if png == nil, let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
      png = rep.representation(using: .png, properties: [:])
    }
    guard let dados = png else { return nil }
    let u = pastaAnexos.appendingPathComponent("imagem-\(carimbo()).png")
    guard (try? dados.write(to: u, options: .atomic)) != nil else { return nil }
    return u.path
  }

  /// Miniatura pequena para o chip (não carrega a imagem inteira na memória).
  static func miniatura(_ caminho: String, lado: Int = 96) -> NSImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: caminho) as CFURL, nil) else { return nil }
    let op: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: lado,
                               kCGImageSourceCreateThumbnailWithTransform: true]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, op as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: .zero)
  }

  /// Como citar um caminho para o agente: relativo à pasta do painel se estiver dentro dela,
  /// com ~ se estiver na pasta pessoal, absoluto no resto.
  static func referencia(_ caminho: String, cwd: String) -> String {
    let p = (caminho as NSString).standardizingPath
    let base = (cwd as NSString).standardizingPath
    if p == base { return "." }
    if p.hasPrefix(base + "/") { return String(p.dropFirst(base.count + 1)) }
    return Loja.encurtar(p)
  }

  /// "@caminho" (entre aspas se tiver espaço).
  static func mencao(_ ref: String) -> String { ref.contains(" ") ? "@\"\(ref)\"" : "@\(ref)" }

  static func entreAspas(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

  /// Contexto de um terminal mencionado, em bloco estruturado. Longo demais para colar: vai
  /// para um arquivo e a mensagem leva só o caminho.
  @MainActor static func contexto(de p: Painel, apelido: String, loja: Loja, linhas: Int = 80, sempreInline: Bool = false,
                                  sempreArquivo: Bool = false) -> String {
    let c = p.contextoParaMencao(linhas: linhas)
    let ws = p.aba.flatMap { loja.workspace(de: $0) }?.nome ?? ""
    let tipo = p.tipoAgente ?? "terminal"
    let cab = "<contexto-orion de=\"@\(apelido)\" painel=\"\(p.id)\" tipo=\"\(tipo)\" workspace=\"\(ws)\" pasta=\"\(Loja.encurtar(p.cwd))\" conteudo=\"\(c.descricao)\">"
    let bloco = cab + "\n" + c.corpo + "\n</contexto-orion>"
    if sempreInline || (bloco.count <= 1800 && !sempreArquivo) { return bloco }
    let u = pastaAnexos.appendingPathComponent("contexto-\(apelido)-\(carimbo()).md")
    guard (try? bloco.write(to: u, atomically: true, encoding: .utf8)) != nil else { return bloco }
    return "[Contexto de @\(apelido) — \(tipo), workspace \(ws), pasta \(Loja.encurtar(p.cwd)), \(c.descricao): leia o arquivo \(u.path)]"
  }
}

extension Painel {
  /// Nome curto para mencionar este painel no compose: "@claude-api", "@codex-site".
  var apelido: String {
    // Um agente é chamado pelo nome do personagem (@rigel); um terminal, pelo título.
    let base = (persona?.nome ?? aba?.titulo ?? titulo).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    var s = base.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
    s = String(s.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(24)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    if s.isEmpty || s == "~" { s = tipoAgente ?? "terminal" }
    let chave: (Painel) -> String = { $0.persona?.nome ?? $0.aba?.titulo ?? $0.titulo }
    let iguais = loja.paineis.values.filter { $0 !== self && chave($0) == chave(self) }
    return iguais.isEmpty ? s : s + "-" + id.suffix(3)
  }

  /// O que este painel tem a dizer a outro: num shell, o último comando e a saída dele (capturada
  /// entre as marcas OSC 133 C e D); num agente, a tela recente.
  func contextoParaMencao(linhas: Int = 80) -> (descricao: String, corpo: String) {
    if tipoAgente == nil, let r = ultimoResultado, !r.comando.isEmpty {
      var saida = r.saida
      let ls = saida.split(separator: "\n", omittingEmptySubsequences: false)
      if ls.count > 200 { saida = "… (\(ls.count - 200) linhas acima cortadas)\n" + ls.suffix(200).joined(separator: "\n") }
      if saida.count > 12000 { saida = "…" + saida.suffix(12000) }
      let codigo = r.codigo.map { "código \($0)" } ?? "sem código"
      return ("último comando (\(codigo), \(Int(r.duracao)) s)", "$ \(r.comando)\n\(saida)")
    }
    let tela = texto(linhas: linhas).split(separator: "\n", omittingEmptySubsequences: false).suffix(linhas + 20)
      .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return ("tela recente", tela.isEmpty ? "(tela vazia)" : tela)
  }

  /// Clipe do compose: escolhe imagens e arquivos no seletor do sistema.
  func anexarPeloSeletor() {
    let p = NSOpenPanel()
    p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
    p.directoryURL = URL(fileURLWithPath: cwd)
    p.prompt = "Anexar"
    p.message = "Imagens viram anexo; arquivos e pastas entram no texto como @caminho."
    guard p.runModal() == .OK else { return }
    anexar(caminhos: p.urls.map(\.path))
    focarCompose()
  }

  /// Imagens viram chips (anexos); o resto entra no texto como @caminho.
  func anexar(caminhos: [String]) {
    for c in caminhos {
      if Compose.ehImagem(c) {
        rascunho.anexar(Anexo(tipo: .imagem, valor: c, rotulo: (c as NSString).lastPathComponent))
      } else {
        var ehDir: ObjCBool = false
        FileManager.default.fileExists(atPath: c, isDirectory: &ehDir)
        mencionarNoCompose(caminho: c + (ehDir.boolValue && !c.hasSuffix("/") ? "/" : ""))
      }
    }
    if !composeVisivel { rascunho.manual = true; atualizarCompose() }
  }

  /// Põe "@caminho" no compose (abrindo-o se preciso) — usado pelo menu de contexto e pelo arrasto.
  func mencionarNoCompose(caminho: String) {
    let barra = caminho.hasSuffix("/") && caminho.count > 1
    let ref = Compose.referencia(barra ? String(caminho.dropLast()) : caminho, cwd: cwd) + (barra ? "/" : "")
    if !composeVisivel { rascunho.manual = true; atualizarCompose() }
    if let c = rascunho.campo, c.window != nil {
      c.inserirEtiqueta(rotulo: ((barra ? String(ref.dropLast()) : ref) as NSString).lastPathComponent + (barra ? "/" : ""), marca: barra ? "📁" : "📄",
                        texto: Compose.mencao(ref), painel: nil, em: c.selectedRange(), dica: ref)
    } else {
      inserirNoCompose(Compose.mencao(ref) + " ")
    }
  }

  func inserirNoCompose(_ trecho: String) {
    if !composeVisivel { rascunho.manual = true; atualizarCompose() }
    let r = rascunho
    if let c = r.campo, c.window != nil {
      let faixa = c.selectedRange()
      let s = c.string as NSString
      let precisaEspaco = faixa.location > 0 && !" \n\t".contains(Character(UnicodeScalar(s.character(at: faixa.location - 1)) ?? " "))
      c.insertText((precisaEspaco ? " " : "") + trecho, replacementRange: faixa)
    } else {
      r.definir(r.texto + (r.texto.isEmpty || r.texto.hasSuffix(" ") || r.texto.hasSuffix("\n") ? "" : " ") + trecho)
    }
  }
}

// MARK: - Busca das menções

enum Mencoes {
  /// Outros terminais e agentes (o workspace do painel primeiro).
  @MainActor static func paineis(_ termo: String, de painel: Painel) -> [ItemMencao] {
    let loja = painel.loja
    let t = termo.lowercased()
    let meuWs = painel.aba?.workspace
    var lista: [(ItemMencao, Double)] = []
    for a in loja.todasEmOrdem {
      for p in loja.paineisDaAba(a) where p !== painel {
        let ws = loja.workspace(de: a)?.nome ?? ""
        let titulo = a.titulo ?? p.titulo
        let chave = "\(p.apelido) \(titulo) \(ws) \(p.tipoAgente ?? "terminal")".lowercased()
        var pontos = t.isEmpty ? 1 : Paleta.pontuar(chave, t)
        guard pontos > 0 else { continue }
        if a.workspace == meuWs { pontos += 20 }
        if p.tipoAgente != nil { pontos += 10 }
        let detalhe = [ws, Loja.encurtar(p.cwd), p.estado.rotulo.lowercased()].filter { !$0.isEmpty }.joined(separator: " · ")
        lista.append((ItemMencao(id: "p:" + p.id, tipo: .painel, rotulo: titulo, detalhe: detalhe, valor: p.id,
                                 programa: p.tipoAgente ?? p.programa, estado: p.estado), pontos))
      }
    }
    return lista.sorted { $0.1 > $1.1 }.prefix(t.isEmpty ? 6 : 8).map(\.0)
  }

  /// Itens da pasta do painel cujo nome casa com o termo (pastas primeiro).
  static func daPasta(_ termo: String, cwd: String) -> [ItemMencao] {
    let t = termo.lowercased()
    let itens = Armazem.listarPasta(".", base: cwd)
    var saida: [(ItemMencao, Double)] = []
    for i in itens {
      guard let nome = i["nome"] as? String, !nome.hasPrefix(".") || t.hasPrefix(".") else { continue }
      let dir = i["dir"] as? Bool ?? false
      let pontos = t.isEmpty ? 1 : Paleta.pontuar(nome.lowercased(), t)
      guard pontos > 0 else { continue }
      let caminho = (cwd as NSString).appendingPathComponent(nome)
      saida.append((ItemMencao(id: "f:" + caminho, tipo: dir ? .pasta : .arquivo, rotulo: nome + (dir ? "/" : ""),
                               detalhe: "", valor: caminho), pontos + (dir ? 0.5 : 0)))
    }
    return saida.sorted { $0.1 > $1.1 }.prefix(t.isEmpty ? 8 : 10).map(\.0)
  }

  /// Autocomplete de caminho: "src/comp", "~/Doc", "/tmp/", "../x".
  static func caminhos(_ termo: String, cwd: String) -> [ItemMencao] {
    var dir = termo, prefixo = ""
    if !termo.hasSuffix("/") {
      dir = (termo as NSString).deletingLastPathComponent
      prefixo = (termo as NSString).lastPathComponent.lowercased()
      if termo == "~" || termo == "." || termo == ".." { dir = termo; prefixo = "" }
    }
    if dir.isEmpty { dir = termo.hasPrefix("/") ? "/" : "." }
    var base = (dir as NSString).expandingTildeInPath
    if !base.hasPrefix("/") { base = ((cwd as NSString).appendingPathComponent(base) as NSString).standardizingPath }
    var saida: [ItemMencao] = []
    let itens = Armazem.listarPasta(base, base: cwd)
    let ordenados = itens.sorted { (($0["dir"] as? Bool ?? false) ? 0 : 1) < (($1["dir"] as? Bool ?? false) ? 0 : 1) }
    for i in ordenados {
      guard let nome = i["nome"] as? String else { continue }
      if nome.hasPrefix(".") && !prefixo.hasPrefix(".") { continue }
      if !prefixo.isEmpty && !nome.lowercased().hasPrefix(prefixo) { continue }
      let ehDir = i["dir"] as? Bool ?? false
      let caminho = (base as NSString).appendingPathComponent(nome)
      saida.append(ItemMencao(id: "f:" + caminho, tipo: ehDir ? .pasta : .arquivo, rotulo: nome + (ehDir ? "/" : ""),
                              detalhe: Loja.encurtar(base), valor: caminho))
      if saida.count >= 14 { break }
    }
    return saida
  }

  // Índice das subpastas do projeto, guardado por alguns segundos.
  private static let trava = NSLock()
  nonisolated(unsafe) private static var indice: [String: (Date, [(String, Bool)])] = [:]
  private static let ignorar: Set<String> = ["node_modules", ".git", ".build", "build", "dist", "Pods", "DerivedData", "venv", ".venv",
                                             "__pycache__", ".next", "target", "vendor", "Library"]

  private static func listar(_ cwd: String) -> [(String, Bool)] {
    trava.lock()
    if let c = indice[cwd], Date().timeIntervalSince(c.0) < 20 { trava.unlock(); return c.1 }
    trava.unlock()
    let raiz = URL(fileURLWithPath: cwd)
    let rasa = cwd == NSHomeDirectory() || cwd == "/"
    var lista: [(String, Bool)] = []
    if let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
      let fundo = raiz.pathComponents.count
      for case let u as URL in e {
        let ehDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let nivel = u.pathComponents.count - fundo
        if ehDir && (ignorar.contains(u.lastPathComponent) || nivel >= (rasa ? 2 : 6)) { e.skipDescendants() }
        if nivel >= 2 { lista.append((String(u.path.dropFirst(raiz.path.count + 1)), ehDir)) }   // o nível 1 já vem de `daPasta`
        if lista.count >= 8000 { break }
      }
    }
    trava.lock(); indice[cwd] = (Date(), lista); trava.unlock()
    return lista
  }

  /// Arquivos e pastas nas subpastas do projeto cujo caminho casa com o termo.
  static func noProjeto(_ termo: String, cwd: String) -> [ItemMencao] {
    let t = termo.lowercased()
    var saida: [(ItemMencao, Double)] = []
    for (rel, ehDir) in listar(cwd) {
      let nome = (rel as NSString).lastPathComponent.lowercased()
      var pontos = Paleta.pontuar(nome, t) * 2
      if pontos == 0 { pontos = rel.lowercased().contains(t) ? 20 : 0 }
      guard pontos > 0 else { continue }
      let caminho = (cwd as NSString).appendingPathComponent(rel)
      saida.append((ItemMencao(id: "f:" + caminho, tipo: ehDir ? .pasta : .arquivo, rotulo: (rel as NSString).lastPathComponent + (ehDir ? "/" : ""),
                               detalhe: (rel as NSString).deletingLastPathComponent, valor: caminho), pontos - Double(rel.count) * 0.05))
    }
    return saida.sorted { $0.1 > $1.1 }.prefix(8).map(\.0)
  }
}

// MARK: - Envio

extension Loja {
  /// Envia o que foi escrito no compose de `origem`: para ele mesmo ou para os painéis marcados
  /// como destino. Imagens vão antes (cada caminho colado sozinho, que é como o Claude Code e o
  /// Codex reconhecem imagem); depois o texto, com o contexto dos terminais mencionados; por fim ↩.
  @discardableResult
  func enviarComposto(de origem: Painel, texto: String, anexos: [Anexo], enter: Bool = true, lembrar: Bool = true) -> [String] {
    var destinos = anexos.filter { $0.tipo == .destino }.compactMap { acharPainel($0.valor) }
    if destinos.isEmpty { destinos = [origem] }
    let imagens = anexos.filter { $0.tipo == .imagem }.map(\.valor)
    var corpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
    for a in anexos where a.tipo == .contexto {
      guard let p = acharPainel(a.valor) else { continue }
      corpo += (corpo.isEmpty ? "" : "\n\n") + Compose.contexto(de: p, apelido: a.rotulo, loja: self)
    }
    if lembrar { lembrarNoCompose(texto) }
    for d in destinos {
      // A primeira mensagem dá nome à tarefa do agente; todas ficam guardadas para a vista de conversa.
      let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
      if d.tipoAgente != nil, d.tarefa == nil, lembrar, let t = Nomes.tarefaCurta(limpo) { d.tarefa = t; salvarDepois() }
      if !limpo.isEmpty || !imagens.isEmpty {
        d.enviadas.append(Conversa.Enviada(texto: limpo.isEmpty ? "(\(imagens.count) imagem\(imagens.count == 1 ? "" : "s"))" : limpo, em: Date(), linha: d.linhaDoCursor()))
        if d.enviadas.count > 200 { d.enviadas.removeFirst(d.enviadas.count - 200) }
      }
      var msg = corpo
      if d !== origem {
        let ws = origem.aba.flatMap { workspace(de: $0) }?.nome ?? ""
        msg = "[Mensagem de @\(origem.apelido)\(ws.isEmpty ? "" : " · workspace \(ws)")]\n" + msg
      }
      entregar(d, imagens: imagens, mensagem: msg, enter: enter)
    }
    return destinos.map(\.id)
  }

  private func entregar(_ d: Painel, imagens: [String], mensagem: String, enter: Bool) {
    var espera = 0.0
    if !d.iniciado { d.acordar(); espera = 2.5 }
    DispatchQueue.main.asyncAfter(deadline: .now() + espera) { [weak d] in
      MainActor.assumeIsolated {
        guard let d, d.vivo else { return }
        let agente = d.tipoAgente != nil && !d.ocioso
        let colagem = d.view?.terminalInputStateSnapshot()?.bracketedPasteMode ?? false
        func colar(_ s: String) -> String {
          if colagem { return "\u{1b}[200~" + s + "\u{1b}[201~" }
          return s.replacingOccurrences(of: "\n", with: agente ? "\u{1b}\r" : " ")
        }
        var passos: [String] = []
        if agente {
          passos = imagens.map { colar($0) + " " }
          if !mensagem.isEmpty { passos.append(colar(mensagem)) }
        } else {
          // Shell: uma linha de comando; os anexos entram como caminhos entre aspas.
          let linha = ([mensagem] + imagens.map(Compose.entreAspas)).filter { !$0.isEmpty }.joined(separator: " ")
          passos = [colar(linha)]
        }
        for (i, s) in passos.enumerated() {
          DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) { [weak d] in d?.escrever(s) }
        }
        if enter {
          DispatchQueue.main.asyncAfter(deadline: .now() + Double(passos.count - 1) * 0.09 + 0.18) { [weak d] in d?.escrever("\r") }
        }
      }
    }
  }
}

// MARK: - Campo de texto (AppKit)

final class CampoTexto: NSTextView {
  weak var painel: Painel?
  var rascunho: Rascunho? { MainActor.assumeIsolated { painel?.rascunho } }

  override func becomeFirstResponder() -> Bool {
    let ok = super.becomeFirstResponder()
    if ok { MainActor.assumeIsolated { rascunho?.campo = self; rascunho?.focado = true } }
    return ok
  }

  override func resignFirstResponder() -> Bool {
    let ok = super.resignFirstResponder()
    if ok { MainActor.assumeIsolated { rascunho?.focado = false; if let p = painel { rascunho?.fecharMencao(p) } } }
    return ok
  }

  override func didChangeText() {
    super.didChangeText()
    MainActor.assumeIsolated {
      guard let p = painel else { return }
      let r = p.rascunho
      r.campo = self
      let t = textoSerializado
      if r.texto != t { r.texto = t }
      recalcularAltura()
      r.atualizarMencao(p)
    }
  }

  // MARK: Etiquetas (menções como chips dentro do texto)

  /// Etiquetas presentes no texto, na ordem.
  var etiquetas: [Etiqueta] {
    guard let ts = textStorage else { return [] }
    var out: [Etiqueta] = []
    ts.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ts.length)) { v, _, _ in if let e = v as? Etiqueta { out.append(e) } }
    return out
  }

  /// O texto como vai para o agente: cada etiqueta vira o que ela representa ("@src/app.ts", "@rigel").
  var textoSerializado: String {
    guard let ts = textStorage, ts.containsAttachments else { return string }
    var out = ""
    ts.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ts.length)) { v, faixa, _ in
      if let e = v as? Etiqueta { out += e.texto } else { out += ts.attributedSubstring(from: faixa).string }
    }
    return out
  }

  private var atributosDoTexto: [NSAttributedString.Key: Any] {
    [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: textColor ?? NSColor.labelColor]
  }

  /// Põe uma etiqueta (e um espaço) no lugar de `em`.
  func inserirEtiqueta(rotulo: String, marca: String, texto: String, painel: String?, em faixa: NSRange, dica: String? = nil) {
    let e = Etiqueta()
    e.texto = texto
    e.painelID = painel
    let img = Etiqueta.desenhar(rotulo: rotulo, marca: marca, fonte: font ?? .systemFont(ofSize: 13), destaque: painel != nil)
    e.image = img
    e.bounds = CGRect(x: 0, y: (font?.descender ?? -3) - 1, width: img.size.width, height: img.size.height)
    let s = NSMutableAttributedString()
    // Colada numa palavra? Um espaço antes.
    let texto0 = string as NSString
    if faixa.location > 0, faixa.location <= texto0.length {
      let antes = texto0.character(at: faixa.location - 1)
      if !(antes == 0x20 || antes == 0x0a || antes == 0x09 || antes == 0x28) { s.append(NSAttributedString(string: " ", attributes: atributosDoTexto)) }
    }
    let chip = NSMutableAttributedString(attachment: e)
    chip.addAttributes(atributosDoTexto, range: NSRange(location: 0, length: chip.length))
    if let dica { chip.addAttribute(.toolTip, value: dica, range: NSRange(location: 0, length: chip.length)) }
    s.append(chip)
    s.append(NSAttributedString(string: " ", attributes: atributosDoTexto))
    let onde = NSRange(location: min(faixa.location, (string as NSString).length), length: min(faixa.length, max(0, (string as NSString).length - faixa.location)))
    if shouldChangeText(in: onde, replacementString: s.string) {
      textStorage?.replaceCharacters(in: onde, with: s)
      didChangeText()
    }
    setSelectedRange(NSRange(location: onde.location + s.length, length: 0))
    typingAttributes = atributosDoTexto
  }

  /// Altura do texto, entre uma e oito linhas.
  func recalcularAltura() {
    guard let lm = layoutManager, let tc = textContainer else { return }
    lm.ensureLayout(for: tc)
    let linha = lm.defaultLineHeight(for: font ?? .systemFont(ofSize: 13))
    let usado = lm.usedRect(for: tc).height
    let h = (min(max(usado, linha), linha * 8) + textContainerInset.height * 2).rounded(.up)
    MainActor.assumeIsolated { if let r = rascunho, abs(r.altura - h) > 0.5 { r.altura = h } }
  }

  private var naPrimeiraLinha: Bool {
    let s = string as NSString
    return !s.substring(to: min(selectedRange().location, s.length)).contains("\n")
  }
  private var naUltimaLinha: Bool {
    let s = string as NSString
    return !s.substring(from: min(NSMaxRange(selectedRange()), s.length)).contains("\n")
  }

  override func keyDown(with e: NSEvent) {
    let mods = e.modifierFlags.intersection([.shift, .option, .command, .control])
    let tratou: Bool = MainActor.assumeIsolated {
      guard let p = painel else { return false }
      let r = p.rascunho
      let lista = r.mencaoAberta && !r.itens.isEmpty
      switch e.keyCode {
      case 36, 76:                                              // ↩
        if hasMarkedText() { return false }
        if lista { r.aceitar(p, destino: mods.contains(.option)); return true }
        if mods.contains(.shift) || mods.contains(.option) { insertNewlineIgnoringFieldEditor(nil); return true }
        r.enviar(p)
        return true
      case 48:                                                  // ⇥
        if lista { r.aceitar(p, completar: true); return true }
        return false
      case 53:                                                  // esc
        if r.mencaoAberta { r.fecharMencao(p); return true }
        if let v = p.view, v.window === window, p.caixa.map({ isDescendant(of: $0) }) == true { window?.makeFirstResponder(v); return true }
        return false
      case 126:                                                 // ↑
        if lista { r.sel = max(0, r.sel - 1); return true }
        if mods.isEmpty, naPrimeiraLinha, string.isEmpty || r.posHistorico >= 0 { r.historico(1, p.loja); return true }
        return false
      case 125:                                                 // ↓
        if lista { r.sel = min(r.itens.count - 1, r.sel + 1); return true }
        if mods.isEmpty, naUltimaLinha, r.posHistorico >= 0 { r.historico(-1, p.loja); return true }
        return false
      default: return false
      }
    }
    if !tratou { super.keyDown(with: e) }
  }

  // Colar: arquivos e imagens viram anexos; texto entra sem formatação.
  override func paste(_ sender: Any?) {
    if receber(NSPasteboard.general) { return }
    pasteAsPlainText(sender)
  }

  /// Arquivos (do Finder) ou imagem pura (captura de tela, cópia de imagem). Devolve true se tratou.
  func receber(_ pb: NSPasteboard) -> Bool {
    MainActor.assumeIsolated {
      guard let p = painel else { return false }
      if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
        window?.makeFirstResponder(self)
        p.anexar(caminhos: urls.map(\.path))
        return true
      }
      let tipos = pb.types ?? []
      if tipos.contains(.png) || tipos.contains(.tiff), pb.string(forType: .string) == nil || tipos.contains(.png),
         let caminho = Compose.salvarImagem(de: pb) {
        p.rascunho.anexar(Anexo(tipo: .imagem, valor: caminho, rotulo: "imagem colada"))
        return true
      }
      return false
    }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let tipos = sender.draggingPasteboard.types ?? []
    if tipos.contains(.fileURL) || tipos.contains(.png) || tipos.contains(.tiff) { return .copy }
    return super.draggingEntered(sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let tipos = sender.draggingPasteboard.types ?? []
    if tipos.contains(.fileURL) || tipos.contains(.png) || tipos.contains(.tiff) { return .copy }
    return super.draggingUpdated(sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if receber(sender.draggingPasteboard) { return true }
    return super.performDragOperation(sender)
  }
}

/// Menção como chip dentro do texto do compose: uma pasta, um arquivo ou outro terminal.
final class Etiqueta: NSTextAttachment {
  var texto = ""            // o que entra na mensagem
  var painelID: String?     // terminal mencionado (o contexto dele vai junto)

  static func desenhar(rotulo: String, marca: String, fonte: NSFont, destaque: Bool) -> NSImage {
    let t = Tema.atual
    let f = NSFont.systemFont(ofSize: max(10, fonte.pointSize - 1.5), weight: .medium)
    let corTexto = destaque ? t.corAcento.blended(withFraction: t.claro ? 0.35 : 0.0, of: .black) ?? t.corAcento
                            : (t.claro ? NSColor.black : NSColor.white).withAlphaComponent(0.88)
    let s = NSAttributedString(string: "\(marca) \(rotulo)", attributes: [.font: f, .foregroundColor: corTexto])
    let medida = s.size()
    let tam = NSSize(width: ceil(medida.width) + 12, height: ceil(fonte.ascender - fonte.descender) + 2)
    return NSImage(size: tam, flipped: false) { r in
      let caixa = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
      (destaque ? t.corAcento.withAlphaComponent(0.2) : (t.claro ? NSColor.black : NSColor.white).withAlphaComponent(0.1)).setFill()
      caixa.fill()
      (destaque ? t.corAcento.withAlphaComponent(0.5) : (t.claro ? NSColor.black : NSColor.white).withAlphaComponent(0.16)).setStroke()
      caixa.lineWidth = 1
      caixa.stroke()
      s.draw(at: NSPoint(x: 6, y: (r.height - medida.height) / 2))
      return true
    }
  }
}

struct CampoCompose: NSViewRepresentable {
  let painel: Painel
  let texto: String          // só para o SwiftUI chamar `updateNSView` quando o rascunho muda por fora
  let escala: CGFloat
  let claro: Bool
  var focarAoAparecer = false

  func makeNSView(context: Context) -> NSScrollView {
    let rolagem = NSScrollView()
    rolagem.drawsBackground = false
    rolagem.borderType = .noBorder
    rolagem.hasVerticalScroller = true
    rolagem.autohidesScrollers = true
    rolagem.scrollerStyle = .overlay
    let c = CampoTexto(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
    c.painel = painel
    c.isRichText = false
    c.importsGraphics = false
    c.allowsUndo = true
    c.drawsBackground = false
    c.isAutomaticQuoteSubstitutionEnabled = false
    c.isAutomaticDashSubstitutionEnabled = false
    c.isAutomaticTextReplacementEnabled = false
    c.isAutomaticSpellingCorrectionEnabled = false
    c.isContinuousSpellCheckingEnabled = false
    c.isGrammarCheckingEnabled = false
    c.textContainerInset = NSSize(width: 0, height: 3)
    c.textContainer?.lineFragmentPadding = 2
    c.textContainer?.widthTracksTextView = true
    c.isVerticallyResizable = true
    c.isHorizontallyResizable = false
    c.autoresizingMask = [.width]
    c.minSize = NSSize(width: 0, height: 0)
    c.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    c.registerForDraggedTypes([.fileURL, .png, .tiff])
    rolagem.documentView = c
    if painel.rascunho.campo == nil || focarAoAparecer { painel.rascunho.campo = c }
    c.string = painel.rascunho.texto
    if focarAoAparecer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { c.window?.makeFirstResponder(c) } }
    aplicar(c)
    return rolagem
  }

  func updateNSView(_ v: NSScrollView, context: Context) {
    guard let c = v.documentView as? CampoTexto else { return }
    aplicar(c)
    if c.textoSerializado != painel.rascunho.texto { c.string = painel.rascunho.texto }
    DispatchQueue.main.async { c.recalcularAltura() }
  }

  private func aplicar(_ c: CampoTexto) {
    let t = Tema.atual
    c.font = NSFont.systemFont(ofSize: 13 * escala)
    c.textColor = (t.claro ? NSColor.black : NSColor.white).withAlphaComponent(t.claro ? 0.88 : 0.92)
    c.insertionPointColor = t.corAcento
    c.selectedTextAttributes = [.backgroundColor: t.corAcento.withAlphaComponent(0.3)]
  }
}

// MARK: - Views

/// O compose dentro da caixa de um painel: ocupa a base do cartão e informa a altura que quer.
struct ComposeHospedado: View {
  @Bindable var painel: Painel
  var body: some View {
    ComposeView(painel: painel)
      .padding(.horizontal, 8).padding(.bottom, 8).padding(.top, 4)
      .fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { painel.alturaCompose = $0 }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .preferredColorScheme(Cor.claro ? .light : .dark)
  }
}

struct ComposeView: View {
  @Bindable var painel: Painel
  /// Dentro de um cartão do quadro: a lista de menções aparece embutida, acima do campo.
  var embutido = false

  var body: some View {
    let r = painel.rascunho
    let tipo = painel.tipoAgente
    VStack(alignment: .leading, spacing: 6) {
      if embutido && r.mencaoAberta { ListaMencoes(painel: painel, embutida: true) }
      if !r.anexos.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 5) { ForEach(r.anexos) { a in ChipAnexo(painel: painel, anexo: a) } }
        }
      }
      HStack(alignment: .bottom, spacing: 6) {
        BotaoMini("paperclip", "Anexar imagem, arquivo ou pasta (também ⌘V, ou arraste para o painel)") { painel.anexarPeloSeletor() }
        ZStack(alignment: .topLeading) {
          if r.texto.isEmpty {
            Text(dica(tipo)).font(F.ui(13)).foregroundStyle(Cor.texto4).lineLimit(1).truncationMode(.tail)
              .padding(.leading, 2).padding(.top, 3).allowsHitTesting(false)
          }
          CampoCompose(painel: painel, texto: r.texto, escala: F.escala, claro: Cor.claro, focarAoAparecer: embutido)
            .frame(height: r.altura)
        }
        .frame(maxWidth: .infinity)
        if r.vazio && painel.estado == .trabalhando {
          // Agente trabalhando e nada escrito: o botão vira "parar".
          Button { painel.interromper() } label: {
            Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Cor.vermelho)
              .frame(width: 26, height: 26).background(Circle().fill(Cor.vermelho.opacity(0.16))).contentShape(Circle())
          }
          .buttonStyle(.plain).help("Interromper o que o agente está fazendo  ⌘.")
        } else {
          Button { r.enviar(painel) } label: {
            Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
              .foregroundStyle(r.vazio ? Cor.texto3 : Cor.sobreAcento)
              .frame(width: 26, height: 26)
              .background(Circle().fill(r.vazio ? Cor.vidro2 : Cor.acento))
              .contentShape(Circle())
          }
          .buttonStyle(.plain).disabled(r.vazio)
          .help("Enviar  ↩   ·   nova linha  ⇧↩   ·   histórico  ↑ ↓   ·   voltar ao terminal  esc")
        }
      }
      if r.focado && !embutido {
        Text("↩ enviar  ·  ⇧↩ nova linha  ·  @ mencionar  ·  ⌘V imagem  ·  ↑ histórico  ·  esc terminal")
          .font(F.ui(10)).foregroundStyle(Cor.texto4).lineLimit(1).truncationMode(.tail).padding(.leading, 34)
      }
    }
    .padding(.leading, 5).padding(.trailing, 6).padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).fill(Cor.elevado))
    .overlay(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous)
      .strokeBorder(r.focado ? Cor.acento.opacity(0.65) : Cor.linhaForte, lineWidth: r.focado ? 1.5 : 1))
    .animation(.easeOut(duration: 0.12), value: r.anexos.count)
  }

  func dica(_ tipo: String?) -> String {
    if let tipo { return "Escreva para \(painel.persona?.nome ?? "o " + nomeFerramenta(tipo)) — @ menciona · ⌘V ou arraste uma imagem" }
    return "Comando ou mensagem para este terminal — @ menciona · ↩ envia"
  }
}

struct ChipAnexo: View {
  let painel: Painel
  let anexo: Anexo
  @Estado private var sobre = false

  var body: some View {
    let loja = painel.loja
    let alvo = anexo.tipo == .imagem ? nil : loja.acharPainel(anexo.valor)
    HStack(spacing: 6) {
      switch anexo.tipo {
      case .imagem:
        if let img = Compose.miniatura(anexo.valor) {
          Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else { Image(systemName: "photo").foregroundStyle(Cor.texto2) }
        Text(anexo.rotulo).lineLimit(1).truncationMode(.middle).frame(maxWidth: 150)
      case .contexto:
        IconePrograma(processo: alvo?.tipoAgente ?? alvo?.programa ?? "shell", tamanho: 18)
        Text("@\(anexo.rotulo)").lineLimit(1)
        Text("contexto").foregroundStyle(Cor.texto3)
      case .destino:
        Image(systemName: "arrow.turn.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Cor.acento)
        IconePrograma(processo: alvo?.tipoAgente ?? alvo?.programa ?? "shell", tamanho: 18)
        Text("para @\(anexo.rotulo)").lineLimit(1)
      }
      Button { painel.rascunho.anexos.removeAll { $0.id == anexo.id } } label: {
        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Cor.texto2)
          .frame(width: 16, height: 16).background(Circle().fill(sobre ? Cor.vidro2 : .clear))
      }.buttonStyle(.plain).help("Remover")
    }
    .font(F.ui(11.5, .medium)).foregroundStyle(Cor.texto)
    .padding(.leading, anexo.tipo == .imagem ? 3 : 7).padding(.trailing, 4).frame(height: 30)
    .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(anexo.tipo == .destino ? Cor.acento.opacity(0.12) : Cor.vidro2))
    .overlay(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).strokeBorder(anexo.tipo == .destino ? Cor.acento.opacity(0.4) : Cor.linha))
    .onHover { sobre = $0 }
    .help(ajuda)
  }

  var ajuda: String {
    switch anexo.tipo {
    case .imagem: return anexo.valor
    case .contexto: return "A tela recente / o último resultado deste terminal vai junto com a mensagem"
    case .destino: return "A mensagem é enviada para este terminal (em vez deste painel)"
    }
  }
}

/// Lista do "@": terminais e agentes, pastas e arquivos.
struct ListaMencoes: View {
  @Bindable var painel: Painel
  var embutida = false

  var body: some View {
    let r = painel.rascunho
    let temPainel = r.itens.indices.contains(r.sel) && r.itens[r.sel].tipo == .painel
    let temPasta = r.itens.indices.contains(r.sel) && r.itens[r.sel].tipo == .pasta
    VStack(alignment: .leading, spacing: 1) {
      if r.itens.isEmpty {
        Text(r.termo.isEmpty ? "Nenhum outro terminal aberto e a pasta está vazia." : "Nada encontrado para “\(r.termo)”.")
          .font(F.ui(12)).foregroundStyle(Cor.texto3).padding(8)
      }
      ForEach(Array(r.itens.enumerated()), id: \.element.id) { i, it in
        if i == 0 || (r.itens[i - 1].tipo == .painel) != (it.tipo == .painel) {
          Text(it.tipo == .painel ? "TERMINAIS E AGENTES" : "PASTAS E ARQUIVOS").font(F.ui(9.5, .semibold)).kerning(0.5)
            .foregroundStyle(Cor.texto4).padding(.horizontal, 8).padding(.top, i == 0 ? 3 : 7).padding(.bottom, 2)
        }
        HStack(spacing: 9) {
          Group {
            if it.tipo == .painel { IconePrograma(processo: it.programa ?? "shell", tamanho: 20) }
            else {
              Image(systemName: it.tipo == .pasta ? "folder.fill" : "doc").font(.system(size: 13))
                .foregroundStyle(it.tipo == .pasta ? Cor.azul : Cor.texto2).frame(width: 20)
            }
          }
          Text(it.rotulo).font(it.tipo == .painel ? F.ui(12.5, .medium) : F.mono(12)).foregroundStyle(Cor.texto).lineLimit(1)
          if let e = it.estado, e == .trabalhando || e == .esperando { Circle().fill(e.cor).frame(width: 6, height: 6) }
          Spacer(minLength: 10)
          Text(it.detalhe).font(F.ui(11)).foregroundStyle(Cor.texto3).lineLimit(1).truncationMode(.head)
        }
        .padding(.horizontal, 8).frame(height: F.m(28))
        .background(RoundedRectangle(cornerRadius: R.pequeno, style: .continuous).fill(i == r.sel ? Cor.acento.opacity(0.2) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { r.aceitar(painel, indice: i) }
        .help(it.tipo == .painel ? "Mencionar este terminal: o contexto dele vai junto com a mensagem" : "Mencionar \(it.rotulo)")
      }
      Text(temPainel ? "↩ anexa o contexto dele · ⌥↩ manda a mensagem para ele · esc fecha"
           : temPasta ? "↩ menciona a pasta · ⇥ entra nela · esc fecha" : "↩ menciona · ↑↓ escolhe · esc fecha")
        .font(F.ui(10.5)).foregroundStyle(Cor.texto4).padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 2)
    }
    .padding(5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: R.controle + 1, style: .continuous).fill(embutida ? Cor.vidro : Cor.flutuante))
    .background(RoundedRectangle(cornerRadius: R.controle + 1, style: .continuous).fill(embutida ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.regularMaterial)))
    .overlay(RoundedRectangle(cornerRadius: R.controle + 1, style: .continuous).strokeBorder(Cor.linhaForte))
    .clipShape(RoundedRectangle(cornerRadius: R.controle + 1, style: .continuous))
    .preferredColorScheme(Cor.claro ? .light : .dark)
  }
}
