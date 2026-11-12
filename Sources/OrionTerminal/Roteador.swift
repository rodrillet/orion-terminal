import Foundation
import AppKit

// Orquestração do time: o roteador escolhe quem responde a uma mensagem sem destinatário
// (`orion mandar @time "…"`, ou "@time …" no compose), quem não tem o que acrescentar passa a
// vez (`orion passar ID`), o agente que abre um pull request vai sozinho para "Revisar" no
// quadro, e dá para parar um agente dizendo o motivo — ele lê o motivo antes de continuar.

extension Loja {
  /// Referências que querem dizer "o time todo" em vez de um agente.
  static func ehTime(_ ref: String) -> Bool {
    let r = (ref.hasPrefix("@") ? String(ref.dropFirst()) : ref).lowercased()
    return ["time", "equipe", "todos", "team", "all"].contains(r)
  }

  // MARK: Roteador

  /// Candidatos para uma mensagem ao time, do mais indicado ao menos: quem é citado pelo nome,
  /// quem tem papel/descrição/tarefa parecidos com o texto e quem está livre agora.
  func candidatos(para texto: String, de origem: Painel?, workspace wid: String?, setor: String? = nil) -> [Painel] {
    let lista = agentes(workspace: wid).filter { p in
      guard p !== origem, p.tipoAgente != nil else { return false }
      if let setor, !setor.isEmpty, p.aba?.setor != setor { return false }
      return !(p.iniciado && !p.vivo && !p.hibernado)          // terminal que saiu não recebe
    }
    guard lista.count > 1 else { return lista }
    let palavras = Loja.palavras(texto)
    let semAcento = Loja.normalizar(texto)
    func nota(_ p: Painel) -> Double {
      var n = 0.0
      if let nome = p.persona?.nome, !nome.isEmpty, semAcento.contains(Loja.normalizar(nome)) { n += 10 }
      if semAcento.contains(p.apelido) { n += 10 }
      let perfil = Loja.palavras([p.persona?.papel ?? "", p.persona?.descricao ?? ""].joined(separator: " "))
      let trabalho = Loja.palavras([p.tarefa ?? "", p.aba?.titulo ?? "", p.aba?.setor ?? "", Loja.nomeDaPasta(p.cwd), p.branch].joined(separator: " "))
      n += 3 * Double(palavras.intersection(perfil).count) + 2 * Double(palavras.intersection(trabalho).count)
      // Livre agora vale mais; trabalhando ou pedindo permissão, menos.
      switch p.estado {
      case .esperando, .pronto: n += 1.5
      case .trabalhando: n -= 1
      default: break
      }
      if p.permissao != nil { n -= 2 }
      if p.hibernado || !p.iniciado { n -= 0.5 }
      if p.maestro || ehCoordenador(p) { n += 0.75 }       // sem pista nenhuma, quem coordena decide
      return n
    }
    return lista.map { ($0, nota($0)) }.sorted { $0.1 > $1.1 }.map(\.0)
  }

  private func ehCoordenador(_ p: Painel) -> Bool {
    let papel = Loja.normalizar(p.persona?.papel ?? "")
    return ["coorden", "maestro", "lider", "gerent", "lead", "pm"].contains { papel.hasPrefix($0) }
  }

  static func normalizar(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
  }

  private static let vazias: Set<String> = [
    "para", "como", "isso", "esse", "essa", "este", "esta", "aqui", "agora", "quem", "qual", "quando", "onde", "pode", "voce",
    "voces", "fazer", "favor", "preciso", "precisa", "sobre", "mais", "menos", "muito", "tudo", "todo", "toda", "time", "equipe",
    "com", "sem", "uma", "umas", "uns", "dos", "das", "nos", "nas", "que", "por", "the", "and", "with", "this", "that", "from",
  ]

  /// Palavras de 3+ letras, sem acento, sem as que não dizem nada.
  static func palavras(_ s: String) -> Set<String> {
    // Radical de 5 letras: "pesquisa", "pesquisar" e "pesquisas" contam como a mesma palavra.
    Set(normalizar(s).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !vazias.contains($0) }
      .map { String($0.prefix(5)) })
  }

  /// Manda ao time: o roteador escolhe quem recebe; os outros ficam na fila de espera da
  /// própria mensagem e recebem se o escolhido passar a vez.
  @discardableResult
  func mandarAoTime(de origem: Painel?, texto: String, anexos: [String] = [], workspace wid: String?, setor: String? = nil,
                    esperaResposta: Bool = true) -> Mensagem? {
    let fila = candidatos(para: texto, de: origem, workspace: wid, setor: setor)
    guard let primeiro = fila.first else { return nil }
    let m = mandar(de: origem, para: primeiro, texto: texto, anexos: anexos, esperaResposta: esperaResposta,
                   doTime: true, rota: fila.dropFirst().map(\.id))
    return mensagem(m.id) ?? m
  }

  // MARK: Passar a vez

  /// "Não é comigo": a mensagem vai para o próximo candidato do roteador; se não sobrar
  /// ninguém, quem mandou fica sabendo. Não acorda ninguém à toa.
  @discardableResult
  func passar(_ id: String, de origem: Painel?, motivo: String?) -> (proximo: Painel?, erro: String?) {
    guard let i = caixa.firstIndex(where: { $0.id == id }) else { return (nil, "mensagem não encontrada: \(id)") }
    let m = caixa[i]
    if let o = origem, o.id != m.para { return (nil, "essa mensagem não é para você") }
    guard m.estado == .entregue || m.estado == .naFila else { return (nil, "essa mensagem já foi \(m.rotuloEstado)") }
    caixa[i].estado = .passada
    caixa[i].motivo = motivo.flatMap { $0.isEmpty ? nil : $0 } ?? "não era com ele"
    let quem = origem.map { $0.persona?.nome ?? "@" + $0.apelido } ?? m.paraNome
    var rota = m.rota
    while !rota.isEmpty {
      let prox = rota.removeFirst()
      guard let p = acharPainel(prox), !(p.iniciado && !p.vivo && !p.hibernado) else { continue }
      let origemPainel = m.de.flatMap { acharPainel($0) }
      mandar(de: origemPainel, para: p, texto: m.texto, anexos: m.anexos, esperaResposta: m.esperaResposta, doTime: m.doTime, rota: rota)
      return (p, nil)
    }
    gravarCaixa()
    // Ninguém mais: avisa quem mandou (agente → mensagem; você → aviso no app).
    let aviso = m.doTime ? "Ninguém do time pegou a mensagem \(m.id) (o último a passar foi \(quem): \(caixa[i].motivo ?? ""))."
                         : "\(quem) passou a mensagem \(m.id): \(caixa[i].motivo ?? "")."
    if let de = m.de, let remetente = acharPainel(de), remetente.vivo || remetente.hibernado {
      caixa.append(Mensagem(de: nil, deNome: "Orion", para: remetente.id, paraNome: "@" + remetente.apelido,
                            texto: aviso, respostaA: m.id, esperaResposta: false))
      gravarCaixa()
    } else if m.de == nil {
      avisoRapido(aviso, segundos: 5)
    }
    return (nil, nil)
  }

  /// "PASS", "passo", "não é comigo": resposta que na verdade é passar a vez.
  static func ehPasse(_ texto: String) -> Bool {
    let t = normalizar(texto.trimmingCharacters(in: .whitespacesAndNewlines)).trimmingCharacters(in: .punctuationCharacters)
    return ["pass", "passo", "passar", "nao e comigo", "nada a acrescentar", "sem nada a acrescentar"].contains(t)
  }

  // MARK: Pull request → Revisar

  /// Procura na tela um pull request recém-aberto (link do GitHub/GitLab sozinho na linha, ou
  /// perto de "gh pr create"/"criado"/"opened"). Achou um novo: guarda e marca "revisar".
  func procurarPR(_ p: Painel) {
    guard p.tipoAgente != nil, let v = p.view, let snap = v.terminalContentSnapshot(region: .history(maximumScrollbackRows: 120)) else { return }
    let linhas = snap.rows.map { $0.text.replacingOccurrences(of: "\u{0}", with: " ") }
    guard let re = try? NSRegularExpression(pattern: #"https://(github\.com/[\w.-]+/[\w.-]+/pull/\d+|gitlab\.[\w.]+/[\w./-]+/-/merge_requests/\d+)"#) else { return }
    let pistas = ["gh pr create", "pull request", "criad", "abri", "aberto", "opened", "created", "glab mr create"]
    var achado: String?
    for (i, l) in linhas.enumerated() {
      let ns = l as NSString
      for r in re.matches(in: l, range: NSRange(location: 0, length: ns.length)) {
        let url = ns.substring(with: r.range)
        let resto = l.replacingOccurrences(of: url, with: "").trimmingCharacters(in: CharacterSet(charactersIn: " ⎿│•·*-:>❯\t"))
        let perto = linhas[max(0, i - 3)...min(linhas.count - 1, i + 1)].joined(separator: " ").lowercased()
        if resto.isEmpty || pistas.contains(where: { perto.contains($0) }) { achado = url }
      }
    }
    guard let url = achado, url != p.pr else { return }
    p.pr = url
    if p.marca == nil { marcar(p, "revisar") } else { salvarDepois() }
    let numero = url.split(separator: "/").last.map(String.init) ?? ""
    notificar(p, titulo: "\(p.persona?.nome ?? "O agente") abriu o PR #\(numero)", corpo: "Foi para Revisar no quadro.")
  }

  // MARK: Parar com motivo

  /// Interrompe e, quando o agente parar de fato, entrega o motivo — ele lê antes de seguir.
  func pararComMotivo(_ p: Painel, motivo: String, de origem: Painel? = nil) {
    guard p.vivo else { return }
    p.interromper()
    let quem = origem.map { "@" + $0.apelido } ?? "você"
    let texto = "[Interrompido por \(quem)] Motivo: \(motivo)\nNão retome o que estava fazendo antes de levar isso em conta. Se precisar de algo, pergunte."
    func entregar(_ tentativa: Int) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak p] in
        MainActor.assumeIsolated {
          guard let self, let p, p.vivo else { return }
          let quieto = !p.ocupado && p.estado != .trabalhando && Date().timeIntervalSince(p.leitor.ultimaSaida) > 1.0
          if !quieto && tentativa < 30 {
            // O primeiro Esc pode ter caído num menu. Só repete o Esc: ⌃C duas vezes fecha o Codex.
            if tentativa == 6, p.agente == "claude" || p.agente == "gemini" { p.interromper() }
            entregar(tentativa + 1); return
          }
          self.enviarComposto(de: p, texto: texto, anexos: [], lembrar: false, remetente: quem)
        }
      }
    }
    entregar(0)
  }

  func pararComMotivoPerguntando(_ p: Painel) {
    perguntar("Parar \(p.persona?.nome ?? "o agente")", texto: "Ele para agora e lê o motivo antes de continuar.",
              ok: "Parar", dica: "Por que parar? (ex.: está mexendo no arquivo errado)", simbolo: "stop.circle") { [weak self, weak p] motivo in
      guard let self, let p else { return }
      if motivo.isEmpty { p.interromper() } else { self.pararComMotivo(p, motivo: motivo) }
    }
  }

  func perguntarAoTimePerguntando(workspace wid: String? = nil, setor: String? = nil) {
    let w = wid ?? workspaceAtivoID
    perguntar(setor.map { "Perguntar ao setor \($0)" } ?? "Perguntar ao time",
              texto: "O Orion escolhe quem do time responde pelo papel, pela tarefa e por quem está livre. Se não for com ele, passa para o próximo.",
              ok: "Mandar", dica: "O que você precisa?", simbolo: "person.3") { [weak self] texto in
      guard let self, !texto.isEmpty else { return }
      if let m = self.mandarAoTime(de: nil, texto: texto, workspace: w, setor: setor) {
        self.avisoRapido("Roteado para \(self.acharPainel(m.para)?.persona?.nome ?? m.paraNome)", segundos: 3)
      } else {
        self.avisoRapido("Nenhum agente neste workspace para receber", segundos: 3)
      }
    }
  }
}
