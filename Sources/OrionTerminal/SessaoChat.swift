import Foundation
import SwiftUI

// Chat a partir do arquivo de sessão: o Claude Code e o Codex gravam cada conversa num .jsonl
// (o que você mandou, o texto da resposta, as ferramentas usadas). Ler esse arquivo dá um chat
// limpo — sem molduras, sem dicas de atalho, com o Markdown original — em vez de recortar o
// texto do terminal. Leitura incremental: só os bytes novos desde a última vez.
// Gemini CLI e terminais comuns continuam com a leitura da tela (Conversa.swift).

final class LeitorSessao {
  struct Item: Equatable {
    enum Tipo { case voce, agente, ferramenta }
    let tipo: Tipo
    let texto: String
    let em: Date?
  }

  private(set) var url: URL?
  private(set) var itens: [Item] = []
  private var deslocamento: UInt64 = 0
  private var resto = Data()
  private var ultimaBusca = Date.distantPast
  private var tipo = ""

  /// Acha (ou troca) o arquivo da sessão do painel. Barato: no máximo a cada 8 s.
  @MainActor func localizar(_ p: Painel) {
    guard let tipo = p.tipoAgente, tipo == "claude" || tipo == "codex" else { url = nil; return }
    guard Date().timeIntervalSince(ultimaBusca) > 8 || url == nil && Date().timeIntervalSince(ultimaBusca) > 2 else { return }
    ultimaBusca = Date()
    let config = p.aba.flatMap { p.loja.conta($0.conta(tipo))?.dir }
    let id = p.idDaConversa()
    guard let id, let novo = LeitorSessao.arquivo(tipo: tipo, config: config, cwd: p.cwd, sessao: id) else { return }
    if novo != url {
      url = novo; self.tipo = tipo
      itens = []; deslocamento = 0; resto = Data()
      if p.no.sessao != id { p.no.sessao = id; p.loja.salvarDepois() }
    }
  }

  /// Lê o que foi acrescentado ao arquivo. Devolve true se apareceu algo novo.
  @discardableResult
  func atualizar() -> Bool {
    guard let url, let h = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? h.close() }
    let tamanho = (try? h.seekToEnd()) ?? 0
    if tamanho < deslocamento { itens = []; deslocamento = 0; resto = Data() }       // arquivo reescrito
    guard tamanho > deslocamento else { return false }
    try? h.seek(toOffset: deslocamento)
    var dados = resto + ((try? h.readToEnd()) ?? Data())
    deslocamento = tamanho
    // Guarda a última linha incompleta para a próxima leitura.
    if let ultimo = dados.lastIndex(of: 10) {
      resto = dados.suffix(from: dados.index(after: ultimo))
      dados = dados.prefix(upTo: ultimo)
    } else { resto = dados; return false }
    let antes = itens.count
    for linha in dados.split(separator: 10) {
      guard let d = try? JSONSerialization.jsonObject(with: linha) as? [String: Any] else { continue }
      if tipo == "claude" { lerClaude(d) } else { lerCodex(d) }
    }
    if itens.count > 2000 { itens.removeFirst(itens.count - 2000) }
    return itens.count != antes
  }

  // MARK: Formatos

  private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
  private func data(_ d: [String: Any]) -> Date? { (d["timestamp"] as? String).flatMap { LeitorSessao.iso.date(from: $0) } }

  /// Texto do usuário que é ruído do programa (comandos internos, lembretes do sistema).
  private static func textoDoUsuario(_ bruto: String) -> String? {
    var t = bruto
    if let r = t.range(of: #"<command-name>(.*?)</command-name>"#, options: .regularExpression) {
      return String(t[r]).replacingOccurrences(of: #"</?command-name>"#, with: "", options: .regularExpression)
    }
    t = t.replacingOccurrences(of: #"<system-reminder>[\s\S]*?</system-reminder>"#, with: "", options: .regularExpression)
    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
    let ruido = ["<local-command", "<command-", "Caveat:", "[Request interrupted", "<environment_context>", "<user_instructions>",
                 "# AGENTS.md", "<permissions", "<user_shell_command>"]
    if t.isEmpty || ruido.contains(where: { t.hasPrefix($0) }) { return nil }
    return t
  }

  private static func resumoFerramenta(_ nome: String, _ entrada: [String: Any]) -> String {
    let chave = ["command", "cmd", "file_path", "path", "pattern", "url", "query", "description", "prompt"]
      .lazy.compactMap { entrada[$0] as? String }.first
      ?? (entrada["command"] as? [String])?.joined(separator: " ")
    let r = chave.map { String($0.replacingOccurrences(of: "\n", with: " ").prefix(140)) } ?? ""
    return r.isEmpty ? nome : "\(nome) · \(r)"
  }

  private func lerClaude(_ d: [String: Any]) {
    guard d["isSidechain"] as? Bool != true, d["isMeta"] as? Bool != true, let m = d["message"] as? [String: Any] else { return }
    let quando = data(d)
    switch d["type"] as? String {
    case "user":
      guard m["role"] as? String == "user" else { return }
      if let s = m["content"] as? String, let t = LeitorSessao.textoDoUsuario(s) { itens.append(Item(tipo: .voce, texto: t, em: quando)) }
      else if let partes = m["content"] as? [[String: Any]] {
        let t = partes.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        if let limpo = LeitorSessao.textoDoUsuario(t) { itens.append(Item(tipo: .voce, texto: limpo, em: quando)) }
      }
    case "assistant":
      for parte in m["content"] as? [[String: Any]] ?? [] {
        switch parte["type"] as? String {
        case "text":
          if let t = (parte["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { itens.append(Item(tipo: .agente, texto: t, em: quando)) }
        case "tool_use":
          itens.append(Item(tipo: .ferramenta, texto: LeitorSessao.resumoFerramenta(parte["name"] as? String ?? "ferramenta", parte["input"] as? [String: Any] ?? [:]), em: quando))
        default: break
        }
      }
    default: break
    }
  }

  private func lerCodex(_ d: [String: Any]) {
    guard d["type"] as? String == "response_item", let p = d["payload"] as? [String: Any] else { return }
    let quando = data(d)
    switch p["type"] as? String {
    case "message":
      let partes = p["content"] as? [[String: Any]] ?? []
      let t = partes.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if p["role"] as? String == "user", let limpo = LeitorSessao.textoDoUsuario(t) { itens.append(Item(tipo: .voce, texto: limpo, em: quando)) }
      else if p["role"] as? String == "assistant", !t.isEmpty { itens.append(Item(tipo: .agente, texto: t, em: quando)) }
    case "function_call", "custom_tool_call":
      let nome = p["name"] as? String ?? "ferramenta"
      var entrada: [String: Any] = [:]
      if let a = p["arguments"] as? String, let j = a.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: j) as? [String: Any] { entrada = o }
      else if let a = p["input"] as? String { entrada = ["command": a] }
      itens.append(Item(tipo: .ferramenta, texto: LeitorSessao.resumoFerramenta(nome, entrada), em: quando))
    default: break
    }
  }

  // MARK: Arquivo

  static func arquivo(tipo: String, config: String?, cwd: String, sessao: String) -> URL? {
    let fm = FileManager.default
    switch tipo {
    case "claude":
      let u = Sessoes.pastaDoClaude(config: config, cwd: cwd).appendingPathComponent(sessao + ".jsonl")
      return fm.fileExists(atPath: u.path) ? u : nil
    case "codex":
      let raiz = URL(fileURLWithPath: (config ?? NSHomeDirectory() + "/.codex") + "/sessions")
      let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"
      for i in 0..<4 {
        let dia = raiz.appendingPathComponent(f.string(from: Date().addingTimeInterval(Double(-i) * 86400)))
        if let u = (try? fm.contentsOfDirectory(at: dia, includingPropertiesForKeys: nil))?.first(where: { $0.lastPathComponent.hasSuffix(sessao + ".jsonl") }) { return u }
      }
      return nil
    default: return nil
    }
  }
}

extension Painel {
  /// Balões da conversa: do arquivo de sessão quando há um; senão, da tela.
  func baloesConversa() -> [Conversa.Balao] {
    leitorSessao.localizar(self)
    guard leitorSessao.url != nil else { return baloes() }
    leitorSessao.atualizar()
    var out: [Conversa.Balao] = []
    var n = 0
    var ferramentas: [String] = []
    var usadas = Set<Int>()
    for it in leitorSessao.itens {
      if let corte = inicioConversaEm, let em = it.em, em < corte { continue }
      switch it.tipo {
      case .ferramenta:
        ferramentas.append(it.texto)
      case .agente:
        // Texto seguido de texto: emenda no mesmo balão.
        if let ultimo = out.last, !ultimo.meu, ferramentas.isEmpty {
          out[out.count - 1] = Conversa.Balao(id: ultimo.id, meu: false, texto: ultimo.texto + "\n\n" + it.texto, em: ultimo.em,
                                              ferramentas: ultimo.ferramentas, markdown: true)
        } else {
          out.append(Conversa.Balao(id: n, meu: false, texto: it.texto, em: it.em, ferramentas: ferramentas, markdown: true)); n += 1
        }
        ferramentas = []
      case .voce:
        if !ferramentas.isEmpty { out.append(Conversa.Balao(id: n, meu: false, texto: "", em: it.em, ferramentas: ferramentas)); n += 1; ferramentas = [] }
        // O que o compose sabe dessa mensagem (anexos, quem mandou pela caixa).
        let i = enviadas.indices.first { !usadas.contains($0) && !enviadas[$0].texto.isEmpty && it.texto.contains(enviadas[$0].texto.prefix(60)) }
        var texto = it.texto
        var anexos: [String] = []
        var de: String?
        if let i {
          usadas.insert(i)
          anexos = enviadas[i].anexos
          de = enviadas[i].de
          texto = enviadas[i].texto.isEmpty ? texto : enviadas[i].texto
        } else if texto.hasPrefix("[Mensagem de ") || texto.hasPrefix("[Resposta de ") || texto.contains("mensagens novas na sua caixa") {
          de = texto.range(of: #"@[\w-]+"#, options: .regularExpression).map { String(texto[$0]) } ?? "outro agente"
        }
        out.append(Conversa.Balao(id: n, meu: true, texto: texto, em: it.em, anexos: anexos, de: de)); n += 1
      }
    }
    if !ferramentas.isEmpty { out.append(Conversa.Balao(id: n, meu: false, texto: "", em: nil, ferramentas: ferramentas)) }
    return out
  }
}

// MARK: - Markdown

/// Markdown de uma resposta: títulos, blocos de código (com copiar), listas e formatação inline.
struct TextoMarkdown: View {
  let texto: String
  let loja: Loja

  enum Bloco: Hashable {
    case paragrafo(String)
    case titulo(String, Int)
    case codigo(String, String)      // linguagem, código
    case regra
  }

  static func blocos(_ s: String) -> [Bloco] {
    var out: [Bloco] = []
    var para: [String] = []
    var codigo: [String]? = nil
    var lingua = ""
    func fecharParagrafo() { if !para.isEmpty { out.append(.paragrafo(para.joined(separator: "\n"))); para = [] } }
    for l in s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
      let t = l.trimmingCharacters(in: .whitespaces)
      if t.hasPrefix("```") {
        if let c = codigo { out.append(.codigo(lingua, c.joined(separator: "\n"))); codigo = nil }
        else { fecharParagrafo(); codigo = []; lingua = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        continue
      }
      if codigo != nil { codigo!.append(l); continue }
      if t.isEmpty { fecharParagrafo(); continue }
      if t == "---" || t == "***" { fecharParagrafo(); out.append(.regra); continue }
      if let m = t.range(of: #"^#{1,4} "#, options: .regularExpression) {
        fecharParagrafo(); out.append(.titulo(String(t[m.upperBound...]), t[m].count - 1)); continue
      }
      var linha = l
      if let m = linha.range(of: #"^(\s*)[-*] "#, options: .regularExpression) {
        let recuo = linha[m].prefix { $0 == " " }
        linha = recuo + "•  " + linha[m.upperBound...]
      }
      para.append(linha)
    }
    if let c = codigo { out.append(.codigo(lingua, c.joined(separator: "\n"))) }
    fecharParagrafo()
    return out
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(TextoMarkdown.blocos(texto).enumerated()), id: \.offset) { _, b in
        switch b {
        case .paragrafo(let s):
          Text(TextoMarkdown.inline(s)).font(F.ui(13)).foregroundStyle(Cor.texto).lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
        case .titulo(let s, let nivel):
          Text(TextoMarkdown.inline(s)).font(F.ui(nivel <= 1 ? 16 : nivel == 2 ? 14.5 : 13.5, .semibold)).foregroundStyle(Cor.texto)
            .padding(.top, 2)
        case .codigo(let lingua, let c):
          BlocoCodigo(lingua: lingua, codigo: c, loja: loja)
        case .regra:
          Rectangle().fill(Cor.linha).frame(height: 1)
        }
      }
    }
    .textSelection(.enabled)
  }

  static func inline(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
  }
}

private struct BlocoCodigo: View {
  let lingua: String
  let codigo: String
  let loja: Loja
  @Estado private var sobre = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(lingua.isEmpty ? "código" : lingua).font(F.ui(10.5, .medium)).foregroundStyle(Cor.texto3)
        Spacer()
        Button { loja.copiar(codigo) } label: {
          HStack(spacing: 4) { Image(systemName: "doc.on.doc"); Text("Copiar") }.font(F.ui(10.5)).foregroundStyle(sobre ? Cor.texto : Cor.texto3)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 10).frame(height: 26)
      .background(Cor.vidro2)
      ScrollView(.horizontal, showsIndicators: false) {
        Text(codigo).font(F.mono(11.5)).foregroundStyle(Cor.texto).fixedSize().padding(10)
      }
    }
    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Cor.vidro))
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Cor.linha))
    .onHover { sobre = $0 }
  }
}

/// Ferramentas que o agente usou entre uma resposta e outra: "N passos" recolhido, abre ao clicar
/// com um check por passo. Uma chamada só é a linha dela, sem "1 passo".
struct FerramentasUsadas: View {
  let lista: [String]
  @Estado private var aberto = false
  @Estado private var sobre = false

  private func nome(_ f: String) -> String { f.split(separator: "·").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? f }

  var body: some View {
    let tipos = Array(NSOrderedSet(array: lista.map(nome))).compactMap { $0 as? String }
    VStack(alignment: .leading, spacing: 0) {
      Button { withAnimation(.easeOut(duration: 0.14)) { aberto.toggle() } } label: {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Cor.verde)
          if lista.count == 1 {
            Text(lista[0]).lineLimit(1).truncationMode(.middle)
          } else {
            Text("\(lista.count) passos").fontWeight(.medium).foregroundStyle(Cor.texto2)
            Text(tipos.prefix(4).joined(separator: ", ") + (tipos.count > 4 ? "…" : "")).lineLimit(1)
          }
          Spacer(minLength: 4)
          if lista.count > 1 {
            Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold)).rotationEffect(.degrees(aberto ? 90 : 0))
          }
        }
        .font(F.ui(11.5)).foregroundStyle(Cor.texto3)
        .padding(.horizontal, 10).frame(height: 28)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(lista.count == 1)
      if aberto && lista.count > 1 {
        Divider().opacity(0.6)
        VStack(alignment: .leading, spacing: 5) {
          ForEach(Array(lista.enumerated()), id: \.offset) { _, f in
            HStack(alignment: .firstTextBaseline, spacing: 7) {
              Image(systemName: "checkmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Cor.verde)
              Text(f).font(F.mono(11)).foregroundStyle(Cor.texto2).lineLimit(2).truncationMode(.tail).textSelection(.enabled)
            }
          }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
      }
    }
    .frame(maxWidth: 560, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sobre || aberto ? Cor.vidro2 : Cor.vidro))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Cor.linha))
    .onHover { sobre = $0 }
  }
}
