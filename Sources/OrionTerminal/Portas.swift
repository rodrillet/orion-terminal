import Cocoa
import Darwin

/// Uma porta TCP em escuta: um servidor rodando (node, vite, next, python…).
struct Porta: Identifiable, Equatable {
  let porta: Int
  let pid: pid_t
  let processo: String
  let endereco: String        // "*", "127.0.0.1", "[::1]"
  var painel: String?         // painel deste app que subiu o processo (nil = de fora)
  var id: String { "\(pid):\(porta)" }
  var url: URL? { URL(string: "http://localhost:\(porta)") }
}

enum Portas {
  /// Portas em escuta do usuário, pelo `lsof` (uma chamada, ~50 ms, fora da thread principal).
  /// `raizes`: pid do shell de cada painel → id do painel, para dizer de quem é cada servidor.
  static func listar(raizes: [pid_t: String]) -> [Porta] {
    guard let saida = Armazem.rodar("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"], em: nil, limite: 4) else { return [] }
    var lista: [Porta] = []
    var pid: pid_t = 0, cmd = ""
    var vistos = Set<String>()
    for linha in saida.split(separator: "\n") {
      guard let t = linha.first else { continue }
      let v = String(linha.dropFirst())
      switch t {
      case "p": pid = pid_t(v) ?? 0
      case "c": cmd = v
      case "n":
        guard let i = v.lastIndex(of: ":"), let porta = Int(v[v.index(after: i)...]), pid > 0 else { continue }
        guard vistos.insert("\(pid):\(porta)").inserted else { continue }      // IPv4 e IPv6 da mesma porta
        lista.append(Porta(porta: porta, pid: pid, processo: cmd, endereco: String(v[..<i]), painel: nil))
      default: break
      }
    }
    // De quem é: sobe pelos pais de cada processo até achar o shell de um painel.
    var bsd = proc_bsdinfo()
    let tam = Int32(MemoryLayout<proc_bsdinfo>.size)
    for i in lista.indices {
      var p = lista[i].pid
      for _ in 0..<24 {
        if let painel = raizes[p] { lista[i].painel = painel; break }
        guard proc_pidinfo(p, PROC_PIDTBSDINFO, 0, &bsd, tam) == tam else { break }
        let pai = pid_t(bsd.pbi_ppid)
        if pai <= 1 || pai == p { break }
        p = pai
      }
      // O nome que o lsof dá é cortado ("node", "Python"); o do app é o do script (vite, next…).
      let nome = Sessao.nomeDoProcesso(lista[i].pid)
      if !nome.isEmpty { lista[i] = Porta(porta: lista[i].porta, pid: lista[i].pid, processo: nome, endereco: lista[i].endereco, painel: lista[i].painel) }
    }
    return lista.sorted { ($0.painel == nil ? 1 : 0, $0.porta) < ($1.painel == nil ? 1 : 0, $1.porta) }
  }
}

extension Loja {
  /// Relê as portas em escuta (em segundo plano) e distribui pelos painéis.
  func atualizarPortas(depois: (() -> Void)? = nil) {
    guard !portasLendo else { depois.map { f in DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { f() } }; return }
    portasLendo = true
    var raizes: [pid_t: String] = [:]
    for p in paineis.values { if let pid = p.pidShell { raizes[pid] = p.id } }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let lista = Portas.listar(raizes: raizes)
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self else { return }
          self.portasLendo = false
          if self.portas != lista { self.portas = lista }
          for p in self.paineis.values {
            let dele = lista.filter { $0.painel == p.id }.map(\.porta)
            if p.portas != dele { p.portas = dele }
          }
          depois?()
        }
      }
    }
  }

  /// Encerra o processo que ocupa uma porta: pede para sair (TERM) e, se continuar de pé, mata (KILL).
  func liberar(_ porta: Porta, depois: (() -> Void)? = nil) {
    let pid = porta.pid
    kill(pid, SIGTERM)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
      if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { self.atualizarPortas(depois: depois) } }
    }
  }

  /// Com confirmação no diálogo do app.
  func liberarPerguntando(_ porta: Porta) {
    let dono = porta.painel.flatMap { acharPainel($0) }.map { " (painel “\($0.aba.flatMap { $0.titulo } ?? $0.titulo)”)" } ?? ""
    confirmar("Liberar a porta \(porta.porta)?", "Encerra o processo \(porta.processo) (pid \(porta.pid))\(dono) que está ocupando a porta.",
              "Encerrar processo", destrutivo: true, simbolo: "bolt.horizontal.circle.fill") { [weak self] in self?.liberar(porta) }
  }

  // MARK: - Fechados recentemente

  /// Guarda um agente que está sendo fechado, com o id da conversa dele, para poder reabrir.
  func lembrarFechado(_ p: Painel) {
    guard let tipo = p.tipoAgente, let a = p.aba else { return }
    let conta = a.conta(tipo)
    let sessao = p.idDaConversa()
    let w = workspace(de: a)
    fechados.removeAll { $0.id == p.id }
    fechados.insert(Fechado(id: p.id, tipo: tipo, pasta: p.cwd, workspace: a.workspace, workspaceNome: w?.nome ?? "", conta: conta,
                            titulo: a.titulo ?? p.titulo, persona: p.persona, tarefa: p.tarefa, pai: p.pai, sessao: sessao), at: 0)
    if fechados.count > Loja.limiteFechados { fechados.removeLast(fechados.count - Loja.limiteFechados) }
    Armazem.gravar("fechados.json", fechados.map(\.dicionario))
  }

  /// Reabre um agente fechado: mesma pasta, conta e personagem, retomando a conversa.
  @discardableResult
  func reabrir(_ f: Fechado, ativar: Bool = true) -> Aba? {
    guard let fer = Ferramenta.de(f.tipo), let base = comandoDoTipo(f.tipo) else { return nil }
    fechados.removeAll { $0.id == f.id }
    Armazem.gravar("fechados.json", fechados.map(\.dicionario))
    let ws = workspace(f.workspace) ?? workspaces.first { $0.nome == f.workspaceNome }
    let a = criarAba(kind: f.tipo, cwd: f.pasta, workspace: ws?.id, conta: conta(f.conta) != nil ? f.conta : nil,
                     comando: fer.retomar(base, sessao: f.sessao), titulo: nil, ativar: ativar, persona: f.persona,
                     pai: f.pai.flatMap { acharPainel($0) != nil ? $0 : nil },
                     idPainel: f.id)     // mesmo id: os subagentes dele continuam apontando para ele
    if let n = a.arvore.folhas.first { n.tarefa = f.tarefa; n.sessao = f.sessao; paineis[n.id]?.tarefa = f.tarefa }
    if !ativar { painelPrincipal(a)?.acordar() }
    return a
  }

  /// Quantos agentes fechados o histórico guarda.
  static let limiteFechados = 50

  func esquecerFechados() {
    fechados = []
    Armazem.gravar("fechados.json", [])
  }

  /// Tira um agente do histórico (a conversa continua guardada pela própria ferramenta).
  func esquecer(_ f: Fechado) {
    fechados.removeAll { $0.id == f.id }
    Armazem.gravar("fechados.json", fechados.map(\.dicionario))
  }

  /// Limpa o histórico (todo, ou só um workspace), com confirmação.
  func esquecerFechadosPerguntando(workspace: String? = nil) {
    let alvo = workspace.map { w in fechados.filter { $0.workspace == w } } ?? fechados
    guard !alvo.isEmpty else { return }
    let nome = workspace.flatMap { self.workspace($0)?.nome }
    confirmar(nome.map { "Limpar o histórico de “\($0)”?" } ?? "Limpar todo o histórico?",
              "\(alvo.count) agente\(alvo.count == 1 ? "" : "s") sai\(alvo.count == 1 ? "" : "em") da lista. As conversas continuam no Claude/Codex/Gemini.",
              "Limpar", destrutivo: true, simbolo: "trash") { [weak self] in
      guard let self else { return }
      if let workspace { self.fechados.removeAll { $0.workspace == workspace } } else { self.fechados = [] }
      Armazem.gravar("fechados.json", self.fechados.map(\.dicionario))
    }
  }

  /// Antes de salvar para sair: anota o id da conversa de cada agente vivo (volta exatamente nela).
  func anotarSessoes() {
    for p in paineis.values where p.vivo {
      guard p.agente != nil else { continue }
      if let s = p.idDaConversa() { p.no.sessao = s }
    }
  }
}
