import Cocoa

/// Contas e uso (limites de 5 h / 7 dias). O uso fica em cache — em memória e em disco — e é
/// atualizado em segundo plano; passar o mouse só lê o cache, nunca espera a rede nem o Chaveiro.
extension Loja {
  func carregarContas(_ depois: (() -> Void)? = nil) {
    DispatchQueue.global(qos: .userInitiated).async {
      let lista = Contas.todas().map { c -> Conta in
        var x = c; x["info"] = Contas.info(c["id"] as? String ?? ""); return Conta(x)
      }
      DispatchQueue.main.async { self.contas = lista; depois?() }
    }
  }

  func contas(_ tipo: String) -> [Conta] { contas.filter { $0.tipo == tipo } }
  func conta(_ id: String) -> Conta? { contas.first { $0.id == id } }
  func contaPadrao(_ tipo: String) -> Conta? { conta(ajustes.contaPadrao(tipo)) }

  /// Conta padrão da ferramenta: vale para as próximas abas (as abertas não mudam).
  func definirPadrao(_ c: Conta) {
    ajustes.definirContaPadrao(c.tipo, c.id)
    lerUso(c.id)
  }

  /// Troca a conta de uma aba. Agente rodando: reinicia com a conta nova (com confirmação).
  /// Shell no prompt: troca a variável.
  func trocarConta(_ a: Aba, para c: Conta, confirmarReinicio: Bool = true) {
    guard a.conta(c.tipo) != c.id else { return }
    let nome = nomeFerramenta(c.tipo)
    let rodando = paineisDaAba(a).filter { $0.vivo && $0.agente == c.tipo }
    if !rodando.isEmpty && confirmarReinicio {
      confirmar("Reiniciar o \(nome) com a conta \(c.nome)?", "A conversa atual fica guardada no histórico da conta anterior.",
                "Reiniciar", simbolo: "arrow.left.arrow.right") { [weak self] in self?.trocarConta(a, para: c, confirmarReinicio: false) }
      return
    }
    let variavel = Ferramenta.de(c.tipo)?.variavel ?? "CLAUDE_CONFIG_DIR"
    a.definirConta(c.tipo, c.id)
    salvarDepois()
    for p in paineisDaAba(a) where p.vivo {
      if p.agente == c.tipo {
        p.reiniciar(comando: comandoDoTipo(c.tipo))
      } else if p.noPrompt {
        let cmd = c.dir.map { " export \(variavel)='\($0.replacingOccurrences(of: "'", with: "'\\''"))'" } ?? " unset \(variavel)"
        p.escrever("\u{15}" + cmd + "\r")
      }
    }
    lerUso(c.id)
  }

  // MARK: - Uso

  /// O uso do Codex vem de arquivos locais. O do Claude precisa do login guardado no Chaveiro,
  /// então só é lido depois que você aceita (uma vez).
  func podeLerUso(_ c: Conta) -> Bool { c.tipo == "codex" || (c.tipo == "claude" && ajustes.usoClaude == "ligado") }

  /// Uso para mostrar em anéis e resumos: nada do Claude enquanto a leitura não estiver ligada
  /// (mesmo que haja números antigos em cache).
  func usoVisivel(_ id: String) -> Uso? {
    guard let c = conta(id), podeLerUso(c) else { return nil }
    return usos[id]
  }

  func lerUso(_ id: String, forcar: Bool = false) {
    guard let c = conta(id), podeLerUso(c), !usoCarregando.contains(id) else { return }
    if !forcar, let em = usos[id]?.em, Date().timeIntervalSince(em) < 60 { return }
    if Contas.usoFalso { return }
    usoCarregando.insert(id)
    Contas.uso(id, forcar: forcar) { [weak self] r in
      guard let self else { return }
      self.usoCarregando.remove(id)
      var novo = Uso(r)
      novo.em = Date()
      // Falha passageira (sem rede): mantém os últimos números e só anota o erro.
      if novo.erro != nil, novo.h5 == nil, let antigo = self.usos[id], antigo.h5 != nil || antigo.d7 != nil {
        var m = antigo; m.erro = novo.erro; self.usos[id] = m
      } else {
        self.usos[id] = novo
      }
      self.salvarCacheDeUso()
    }
  }

  /// Atualiza todas as contas com login. Chamado ao abrir, a cada `usoIntervalo` minutos e ao
  /// passar o mouse (se o dado tiver mais de um minuto).
  func atualizarUsos(forcar: Bool = false) {
    proximoUso = Date().addingTimeInterval(max(1, ajustes.usoIntervalo) * 60)
    for c in contas where c.logado { lerUso(c.id, forcar: forcar) }
  }

  func carregarCacheDeUso() {
    guard let d = Armazem.ler("uso.json") as? [String: [String: Any]] else { return }
    for (id, v) in d { usos[id] = Uso(v) }
  }

  func salvarCacheDeUso() {
    Armazem.gravar("uso.json", usos.mapValues(\.dicionario))
  }

  /// Maior uso (5 h) entre as contas de uma ferramenta — para o anel do ícone.
  func usoDaPadrao(_ tipo: String) -> Uso? { contaPadrao(tipo).flatMap { usos[$0.id] } }

  // MARK: - Cartão do Claude / Codex (hover = resumo, clique = painel)

  /// O mouse entrou num ícone do Claude/Codex: abre o resumo depois de um instante.
  func entrouUso(_ tipo: String, ancora: CGRect, atraso: Double = 0.28) {
    usoAgendado?.cancel()
    if let h = usoHover, h.fixo { return }
    if let h = usoHover, h.tipo == tipo { usoHover = UsoHover(tipo: tipo, ancora: ancora); return }
    let w = DispatchWorkItem { [weak self] in
      guard let self, self.dialogo == nil else { return }
      self.usoHover = UsoHover(tipo: tipo, ancora: ancora)
      for c in self.contas(tipo) where c.logado { self.lerUso(c.id) }   // só relê se o dado tiver mais de 1 min
    }
    usoAgendado = w
    DispatchQueue.main.asyncAfter(deadline: .now() + (usoHover == nil ? atraso : 0.05), execute: w)
  }

  /// O mouse saiu do ícone ou do cartão: fecha depois de um instante (dá tempo de ir de um ao outro).
  func saiuUso() {
    usoAgendado?.cancel()
    guard let h = usoHover, !h.fixo else { return }
    let w = DispatchWorkItem { [weak self] in
      if let h = self?.usoHover, !h.fixo { self?.usoHover = nil }
    }
    usoAgendado = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: w)
  }

  /// O mouse está sobre o cartão: cancela o fechamento.
  func ficouNoUso() { usoAgendado?.cancel() }

  func fecharUso() { usoAgendado?.cancel(); usoHover = nil }

  /// Clique no botão do Claude/Codex: abre (ou fecha) o painel expandido, preso até fecharem.
  func alternarPainelDaFerramenta(_ tipo: String, ancora: CGRect) {
    usoAgendado?.cancel()
    if let h = usoHover, h.tipo == tipo, h.expandido { usoHover = nil; return }
    usoHover = UsoHover(tipo: tipo, ancora: ancora, fixo: true, expandido: true)
    for c in contas(tipo) where c.logado { lerUso(c.id) }
  }

  /// O que o clique num botão do Claude/Codex faz. Padrão: abre o painel; com ⌥ (ou se o ajuste
  /// estiver em "novo"), abre um agente direto. O duplo clique sempre abre direto.
  func cliqueNaFerramenta(_ tipo: String, ancora: CGRect, alternativo: Bool) {
    let direto = (ajustes.cliqueFerramenta == "novo") != alternativo
    if direto { fecharUso(); criarAba(kind: tipo) } else { alternarPainelDaFerramenta(tipo, ancora: ancora) }
  }
}
