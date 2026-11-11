import Cocoa
import SwiftUI
import Observation

/// Autocomplete em lista, embaixo do que está sendo digitado. Lê a linha da tela, então convive
/// com o Tab do zsh (fzf-tab) e a sugestão cinza do zsh-autosuggestions. Só captura teclas
/// depois que você entra na lista com ↓ (ou abre com ⌃Espaço).
@MainActor @Observable
final class Sugestoes {
  struct Item: Identifiable, Equatable {
    let id = UUID()
    let texto: String
    let rotulo: String
    let tipo: String       // comando, sub, opcao, branch, script, pasta, arquivo, historico
    var desc = ""
    var espaco = true
    var linhaInteira = false
    var continua = false
    static func == (a: Item, b: Item) -> Bool { a.texto == b.texto && a.tipo == b.tipo }
  }

  var itens: [Item] = []
  var sel = -1
  @ObservationIgnored weak var loja: Loja?
  @ObservationIgnored private(set) weak var painel: Painel?
  @ObservationIgnored private var historico: [String] = []
  @ObservationIgnored private var frequencia: [String: Int] = [:]
  @ObservationIgnored private var token = ""
  @ObservationIgnored private var linha = ""
  @ObservationIgnored private var agendado: DispatchWorkItem?
  @ObservationIgnored private var vista: NSHostingView<ListaSugestoes>?
  @ObservationIgnored private var cachePastas: [String: (Date, [(String, Bool)])] = [:]
  @ObservationIgnored private var cacheBranches: [String: (Date, [String])] = [:]
  @ObservationIgnored private var cacheScripts: [String: (Date, [String])] = [:]

  var aberta: Bool { vista != nil }

  func carregarHistorico() {
    DispatchQueue.global(qos: .utility).async {
      let h = Armazem.historico()
      var f: [String: Int] = [:]
      for c in h { if let p = c.split(separator: " ").first { f[String(p), default: 0] += 1 } }
      DispatchQueue.main.async { self.historico = h; self.frequencia = f }
    }
  }

  func lembrar(_ cmd: String) {
    let c = cmd.trimmingCharacters(in: .whitespaces)
    guard !c.isEmpty else { return }
    historico.removeAll { $0 == c }
    historico.insert(c, at: 0)
    if let p = c.split(separator: " ").first { frequencia[String(p), default: 0] += 1 }
  }

  func digitou(_ p: Painel, _ bytes: [UInt8]) {
    guard loja?.ajustes.sugestoes == true else { return }
    if bytes.contains(13) || bytes.contains(3) || bytes == [27] || bytes == [9] { fechar(); return }
    agendar(p)
  }

  func agendar(_ p: Painel) {
    guard let loja, loja.ajustes.sugestoes, loja.ajustes.sugestoesAuto, p === loja.painelAtivo else { return }
    agendado?.cancel()
    let w = DispatchWorkItem { [weak self, weak p] in if let p { self?.atualizar(p) } }
    agendado = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: w)
  }

  func atualizar(_ p: Painel, forcar: Bool = false) {
    guard let l = p.linhaAtual(), !l.trimmingCharacters(in: .whitespaces).isEmpty || forcar, l.count < 300 else { fechar(); return }
    if !forcar && aberta && painel === p && l == linha { return }
    linha = l
    let novos = candidatos(p, l)
    guard !novos.isEmpty else { fechar(); return }
    if novos != itens { sel = forcar ? 0 : -1 }
    itens = novos
    mostrar(p)
  }

  // MARK: - Candidatos

  private func tokens(_ l: String) -> [String] {
    var out: [String] = [], atual = "", aspas: Character? = nil
    for ch in l {
      if let a = aspas { atual.append(ch); if ch == a { aspas = nil }; continue }
      if ch == "\"" || ch == "'" { aspas = ch; atual.append(ch); continue }
      if ch == " " { if !atual.isEmpty { out.append(atual) }; atual = ""; continue }
      if "|;&".contains(ch) { out.removeAll(); atual = ""; continue }
      atual.append(ch)
    }
    out.append(atual)
    return out
  }

  private func candidatos(_ p: Painel, _ l: String) -> [Item] {
    var toks = tokens(l)
    let atual = toks.removeLast()
    while let f = toks.first, ["sudo", "time", "nohup", "env", "exec"].contains(f) { toks.removeFirst() }
    token = atual
    var out: [Item] = []
    let a = atual.lowercased()
    func casa(_ s: String) -> Bool { s.lowercased().hasPrefix(a) && s != atual }

    if toks.isEmpty {
      if atual.contains("/") || atual.hasPrefix(".") || atual.hasPrefix("~") {
        out += caminhos(p, atual, soPastas: false)
      } else if !atual.isEmpty {
        let nomes = Set(frequencia.keys).union(Specs.comandosBase)
        let lista = nomes.filter { casa($0) && !$0.contains("=") && !$0.contains("$") }
          .sorted { (frequencia[$0] ?? 0, $1) > (frequencia[$1] ?? 0, $0) }.prefix(12)
        for n in lista {
          let f = frequencia[n] ?? 0
          out.append(Item(texto: n, rotulo: n, tipo: "comando", desc: Specs.todos[n]?.desc ?? (f > 0 ? "\(f)× no histórico" : "")))
        }
      }
    } else {
      var nivel = Specs.todos[toks[0]]
      for t in toks.dropFirst() where !t.hasPrefix("-") { if let s = nivel?.sub[t] { nivel = s } }
      if let nivel {
        if atual.hasPrefix("-") {
          for o in nivel.op where casa(o.0) { out.append(Item(texto: o.0, rotulo: o.0, tipo: "opcao", desc: o.1)) }
        } else {
          for (nome, s) in nivel.sub.sorted(by: { $0.key < $1.key }) where atual.isEmpty || casa(nome) {
            out.append(Item(texto: nome, rotulo: nome, tipo: "sub", desc: s.desc))
          }
          switch nivel.arg {
          case "branches": for b in branches(p) where atual.isEmpty || casa(b) { out.append(Item(texto: b, rotulo: b, tipo: "branch", desc: "branch")) }
          case "scripts": for s in scripts(p) where atual.isEmpty || casa(s) { out.append(Item(texto: s, rotulo: s, tipo: "script", desc: "script do package.json")) }
          case "pastas", "arquivos": if !atual.isEmpty || out.isEmpty { out += caminhos(p, atual, soPastas: nivel.arg == "pastas") }
          default: break
          }
          if atual.isEmpty && out.count > 14 { out = Array(out.prefix(14)) }
        }
      } else if !atual.isEmpty && (atual.contains("/") || atual.hasPrefix(".") || atual.hasPrefix("~") || atual.count >= 2) {
        out += caminhos(p, atual, soPastas: false)
      }
    }
    let lt = l.trimmingCharacters(in: .whitespaces)
    if lt.count >= 2 {
      var n = 0
      for h in historico where h.hasPrefix(l) && h != l && !h.contains("\n") {
        out.append(Item(texto: h, rotulo: h, tipo: "historico", desc: "histórico", espaco: false, linhaInteira: true))
        n += 1
        if n >= 4 { break }
      }
    }
    return Array(out.prefix(40))
  }

  private func caminhos(_ p: Painel, _ tok: String, soPastas: Bool) -> [Item] {
    let t = tok.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    let barra = t.lastIndex(of: "/")
    let dir = barra.map { String(t[...$0]) } ?? ""
    let base = barra.map { String(t[t.index(after: $0)...]) } ?? t
    let chave = p.cwd + "|" + dir
    var lista: [(String, Bool)]
    if let c = cachePastas[chave], Date().timeIntervalSince(c.0) < 4 { lista = c.1 }
    else {
      lista = Armazem.listarPasta(dir.isEmpty ? "." : dir, base: p.cwd).map { ($0["nome"] as? String ?? "", $0["dir"] as? Bool ?? false) }
      cachePastas[chave] = (Date(), lista)
    }
    var out: [Item] = []
    for (nome, ehDir) in lista {
      if soPastas && !ehDir { continue }
      if nome.hasPrefix(".") && !base.hasPrefix(".") { continue }
      guard nome.lowercased().hasPrefix(base.lowercased()), nome != base else { continue }
      var esc = ""
      for ch in nome { if " '\"()&;|<>$`\\".contains(ch) { esc.append("\\") }; esc.append(ch) }
      out.append(Item(texto: dir + esc + (ehDir ? "/" : ""), rotulo: nome + (ehDir ? "/" : ""), tipo: ehDir ? "pasta" : "arquivo",
                      espaco: !ehDir, continua: ehDir))
      if out.count >= 30 { break }
    }
    return out.sorted { ($0.tipo == "pasta" ? 0 : 1) < ($1.tipo == "pasta" ? 0 : 1) }
  }

  private func branches(_ p: Painel) -> [String] {
    if let c = cacheBranches[p.cwd], Date().timeIntervalSince(c.0) < 15 { return c.1 }
    let b = Armazem.branches(p.cwd)
    cacheBranches[p.cwd] = (Date(), b)
    return b
  }

  private func scripts(_ p: Painel) -> [String] {
    if let c = cacheScripts[p.cwd], Date().timeIntervalSince(c.0) < 15 { return c.1 }
    let s = Armazem.scriptsNpm(p.cwd)
    cacheScripts[p.cwd] = (Date(), s)
    return s
  }

  // MARK: - Tela

  private func mostrar(_ p: Painel) {
    guard let caixa = p.caixa, let tv = p.view, let pos = p.posicaoDoCursor() else { return }
    if painel !== p { vista?.removeFromSuperview(); vista = nil }
    painel = p
    if vista == nil {
      let v = NSHostingView(rootView: ListaSugestoes(sugestoes: self))
      caixa.addSubview(v)
      vista = v
    }
    guard let v = vista else { return }
    let tam = v.fittingSize
    let dim = tv.terminalInputStateSnapshot()?.dimensions
    let larguraCel = tv.bounds.width / CGFloat(max(1, dim?.cols ?? 80))
    let alturaCel = tv.bounds.height / CGFloat(max(1, dim?.rows ?? 24))
    let xTok = pos.x - CGFloat(token.count) * larguraCel
    let baseDaLinha = tv.frame.maxY - pos.y          // a caixa tem origem embaixo
    var origem = NSPoint(x: tv.frame.minX + xTok - 30, y: baseDaLinha - tam.height - 4)
    if origem.y < 4 { origem.y = baseDaLinha + alturaCel + 4 }
    origem.x = min(max(8, origem.x), caixa.bounds.width - tam.width - 8)
    v.frame = NSRect(origin: origem, size: tam)
  }

  func fechar() {
    vista?.removeFromSuperview()
    vista = nil
    painel = nil
    itens = []
    sel = -1
    linha = ""
  }

  /// Teclas enquanto a lista está aberta. Devolve true se consumiu.
  func tecla(_ e: NSEvent, painel p: Painel) -> Bool {
    if !aberta || painel !== p {
      if e.modifierFlags.contains(.control) && e.keyCode == 49, loja?.ajustes.sugestoes == true {   // ⌃Espaço
        if p.inicioLinha == nil { p.marcarInicioDaLinha() }
        atualizar(p, forcar: true)
        return true
      }
      return false
    }
    switch e.keyCode {
    case 125: sel = min(sel + 1, itens.count - 1); return true                         // ↓
    case 126: if sel >= 0 { sel -= 1; return true }; fechar(); return false            // ↑
    case 36, 76, 48:                                                                    // ↩ ⇥
      if sel >= 0 { aceitar(); return true }
      fechar(); return false
    case 53: fechar(); return true                                                      // esc
    case 123, 124: fechar(); return false
    default: return false
    }
  }

  func aceitar(_ indice: Int? = nil) {
    let i = indice ?? sel
    guard i >= 0, i < itens.count, let p = painel else { return }
    let it = itens[i]
    let apagar = it.linhaInteira ? linha.count : token.count
    p.escrever(String(repeating: "\u{7f}", count: apagar) + it.texto + (it.espaco && !it.linhaInteira ? " " : ""))
    let continua = it.continua
    fechar()
    if continua { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak p] in if let p { self?.atualizar(p) } } }
  }
}

struct ListaSugestoes: View {
  @Bindable var sugestoes: Sugestoes

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(sugestoes.itens.enumerated()), id: \.element.id) { i, it in
              HStack(spacing: 9) {
                Image(systemName: simbolo(it.tipo)).font(F.ui(11)).foregroundStyle(i == sugestoes.sel ? Cor.acento : cor(it.tipo)).frame(width: 14)
                Text(it.rotulo).font(F.mono(12.5)).foregroundStyle(it.tipo == "historico" ? Cor.texto2 : Cor.texto).lineLimit(1)
                Spacer(minLength: 12)
                Text(it.desc).font(F.ui(11)).foregroundStyle(Cor.texto4).lineLimit(1)
              }
              .padding(.horizontal, 8).frame(height: 25)
              .background(RoundedRectangle(cornerRadius: 6).fill(i == sugestoes.sel ? Cor.acento.opacity(0.22) : .clear))
              .contentShape(Rectangle())
              .onTapGesture { sugestoes.aceitar(i) }
              .id(i)
            }
          }
        }
        .onChange(of: sugestoes.sel) { _, v in if v >= 0 { proxy.scrollTo(v) } }
      }
      .frame(maxHeight: min(CGFloat(sugestoes.itens.count) * 26, 230))
      Text(sugestoes.sel < 0 ? "↓ escolher · esc fecha" : "↩ ou ⇥ aceitar · ↑↓ navegar · esc fecha")
        .font(F.ui(10.5)).foregroundStyle(Cor.texto4).padding(.horizontal, 8).padding(.top, 3)
    }
    .padding(4)
    .frame(width: 400)
    .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.flutuante))
    .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(.regularMaterial))
    .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(Cor.linhaForte))
    .clipShape(RoundedRectangle(cornerRadius: R.controle, style: .continuous))
    .preferredColorScheme(Cor.claro ? .light : .dark)
  }

  func simbolo(_ t: String) -> String {
    ["comando": "terminal", "sub": "chevron.right", "opcao": "option", "branch": "arrow.triangle.branch", "script": "bolt",
     "pasta": "folder", "arquivo": "doc", "historico": "clock.arrow.circlepath"][t] ?? "terminal"
  }
  func cor(_ t: String) -> Color { t == "pasta" ? Cor.azul : t == "branch" ? Cor.lilas : Cor.texto3 }
}
