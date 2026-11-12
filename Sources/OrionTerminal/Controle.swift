import Cocoa
import Darwin

/// Servidor do CLI `orion` (socket Unix, uma linha JSON por pedido e por resposta).
/// Deixa um agente (Claude, Codex, script) listar workspaces, abas e agentes, ler a tela, rodar
/// comandos esperando o código de saída, abrir agentes num workspace, mandar mensagens e interromper.
final class Controle {
  static var caminho: String { Armazem.pasta.appendingPathComponent("controle.sock").path }
  private var fd: Int32 = -1
  private let fila = DispatchQueue(label: "orion.controle")
  unowned let loja: Loja
  private var ajudantes: [String: String] = [:]   // painel de origem → painel onde `rodar` executa

  init(loja: Loja) { self.loja = loja }

  func iniciar() {
    let caminho = Controle.caminho
    unlink(caminho)
    fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)   // os shells filhos não podem herdar o socket
    var end = sockaddr_un()
    end.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &end.sun_path) { p in
      caminho.withCString { strncpy(UnsafeMutableRawPointer(p).assumingMemoryBound(to: CChar.self), $0, 103) }
    }
    let r = withUnsafePointer(to: &end) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard r == 0 else { close(fd); return }
    chmod(caminho, 0o600)
    listen(fd, 16)
    let servidor = fd
    Thread.detachNewThread { [weak self] in
      while true {
        let c = accept(servidor, nil, nil)
        if c < 0 { if errno == EINTR { continue }; break }
        _ = fcntl(c, F_SETFD, FD_CLOEXEC)
        self?.fila.async { self?.atender(c) }
      }
    }
  }

  func parar() { if fd >= 0 { close(fd); unlink(Controle.caminho) } }

  private func atender(_ c: Int32) {
    // Um cliente que conecta e não manda a linha não pode travar a fila de todos os `orion`.
    var limite = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &limite, socklen_t(MemoryLayout<timeval>.size))
    var dados = Data()
    var buf = [UInt8](repeating: 0, count: 65536)
    while true {
      let n = read(c, &buf, buf.count)
      if n <= 0 { break }
      dados.append(buf, count: n)
      if buf[n - 1] == 10 { break }
    }
    guard let pedido = try? JSONSerialization.jsonObject(with: dados) as? [String: Any] else {
      responder(c, ["ok": false, "erro": "pedido inválido"]); return
    }
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        self.tratar(pedido) { resposta in self.fila.async { self.responder(c, resposta) } }
      }
    }
  }

  private func responder(_ c: Int32, _ r: [String: Any]) {
    if var d = try? JSONSerialization.data(withJSONObject: r) {
      d.append(10)
      d.withUnsafeBytes { p in var off = 0; while off < d.count { let n = write(c, p.baseAddress! + off, d.count - off); if n <= 0 { break }; off += n } }
    }
    close(c)
  }

  // MARK: - Comandos

  @MainActor private func tratar(_ p: [String: Any], _ fim: @escaping ([String: Any]) -> Void) {
    let cmd = p["cmd"] as? String ?? ""
    let origem = p["origem"] as? String
    func painel(_ chave: String = "painel", padraoOrigem: Bool = true) -> Painel? {
      if let id = p[chave] as? String, !id.isEmpty {
        if id == "atual" { return loja.painelAtivo }
        return loja.acharPainel(id)
      }
      if padraoOrigem, let o = origem, let x = loja.painelExistente(o) { return x }
      return loja.painelAtivo
    }
    func erro(_ m: String) { fim(["ok": false, "erro": m]) }
    /// --anexo (imagens e arquivos viram anexo; arquivos entram na mensagem como @caminho), --mencionar e --para.
    func anexos() -> (lista: [Anexo], arquivos: [String], erro: String?) {
      var lista: [Anexo] = [], arquivos: [String] = []
      for bruto in p["anexos"] as? [String] ?? [] {
        var c = (bruto as NSString).expandingTildeInPath
        if !c.hasPrefix("/") { c = (((p["cwd"] as? String) ?? NSHomeDirectory()) as NSString).appendingPathComponent(c) }
        c = (c as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: c) else { return ([], [], "anexo não encontrado: \(bruto)") }
        if Compose.ehImagem(c) { lista.append(Anexo(tipo: .imagem, valor: c, rotulo: (c as NSString).lastPathComponent)) } else { arquivos.append(c) }
      }
      for (chave, tipo) in [("mencionar", Anexo.Tipo.contexto), ("para", Anexo.Tipo.destino)] {
        for id in p[chave] as? [String] ?? [] {
          guard let alvo = id == "atual" ? loja.painelAtivo : loja.acharPainel(id) else { return ([], [], "painel não encontrado: \(id)") }
          lista.append(Anexo(tipo: tipo, valor: alvo.id, rotulo: alvo.apelido))
        }
      }
      return (lista, arquivos, nil)
    }
    /// Workspace pedido (id, nome ou número). `criar`: cria se não existir.
    func workspace(criar: Bool = false) -> Workspace? {
      guard let ref = (p["workspace"] as? String) ?? (p["grupo"] as? String), !ref.isEmpty else { return nil }
      if let w = loja.buscarWorkspace(ref) { return w }
      return criar ? loja.criarWorkspace(ref, pasta: (p["pasta"] as? String)) : nil
    }
    func descrever(_ x: Painel) -> [String: Any] {
      let a = x.aba
      let w = a.flatMap { loja.workspace(de: $0) }
      let tipo = x.tipoAgente
      var d: [String: Any] = ["id": x.id, "aba": a?.id ?? "", "workspace": w?.nome ?? "", "workspaceId": w?.id ?? "",
                              "tipo": tipo ?? "shell", "estado": x.estado.rawValue, "desde": Int(Date().timeIntervalSince(x.desde)),
                              "titulo": a.flatMap { $0.titulo } ?? x.titulo, "pasta": x.cwd, "branch": x.branch,
                              "programa": x.ocioso ? "shell" : x.processo, "voce": x.id == origem,
                              "apelido": x.apelido, "memoria": Int(x.memoria / 1_048_576)]
      if let m = x.marca { d["marca"] = m }
      if let pr = x.pr { d["pr"] = pr }
      if x.hibernado { d["hibernado"] = true }
      if let st = a?.setor { d["setor"] = st }
      if let ps = x.persona { d["personagem"] = ps.nome; d["avatar"] = ps.avatar; d["papel"] = ps.papel; if !ps.descricao.isEmpty { d["descricao"] = ps.descricao } }
      if let perm = x.permissao { d["permissao"] = ["pergunta": perm.pergunta, "detalhe": perm.detalhe, "opcoes": perm.opcoes.map { "\($0.id). \($0.rotulo)" }] }
      let fila = loja.naFila(para: x.id)
      if fila > 0 { d["caixa"] = fila }
      if let pai = x.pai { d["pai"] = pai; d["paiNome"] = loja.acharPainel(pai)?.persona?.nome ?? "" }
      if let t = x.tarefa { d["tarefa"] = t }
      let nFilhos = loja.filhos(de: x.id).count
      if nFilhos > 0 || x.maestro { d["maestro"] = true; d["filhos"] = nFilhos }
      if !x.portas.isEmpty { d["portas"] = x.portas }
      if let tipo, let a, let c = loja.conta(a.conta(tipo)) {
        d["conta"] = c.id; d["contaNome"] = c.nome
        if let u = loja.usoVisivel(c.id)?.h5 { d["uso5h"] = u.pctAtual }
        if let u = loja.usoVisivel(c.id)?.d7 { d["uso7d"] = u.pctAtual }
      }
      return d
    }

    switch cmd {
    case "abas":
      let filtro = workspace()
      if (p["workspace"] as? String) != nil && filtro == nil { return erro("workspace não encontrado") }
      fim(["ok": true, "abas": loja.todasEmOrdem.filter { filtro == nil || $0.workspace == filtro!.id }.map { a -> [String: Any] in
        let nomeWs = loja.workspace(de: a)?.nome ?? ""
        return ["aba": a.id, "titulo": loja.titulo(a), "workspace": nomeWs, "grupo": nomeWs, "ativa": a.id == loja.abaAtivaID,
         "paineis": a.arvore.folhas.map { n -> [String: Any] in
           let x = loja.paineis[n.id]
           return ["id": n.id, "pasta": x?.cwd ?? n.cwd, "programa": x.map { $0.ocioso ? "shell" : $0.processo } ?? "(não iniciado)",
                   "estado": x.map(estadoTexto) ?? "parado", "titulo": x?.titulo ?? "", "ativo": a.painelAtivo == n.id,
                   "voce": n.id == origem]
         }]
      }])

    case "workspaces":
      fim(["ok": true, "workspaces": loja.workspaces.enumerated().map { (i, w) -> [String: Any] in
        let c = loja.contagem(w)
        return ["id": w.id, "numero": i + 1, "nome": w.nome, "pasta": w.pasta, "cor": w.cor, "simbolo": w.simbolo,
                "ativo": w.id == loja.workspaceAtivoID, "abas": loja.abas(de: w).count,
                "agentes": loja.agentes(workspace: w.id).count, "trabalhando": c.trabalhando, "esperando": c.esperando]
      }])

    case "workspace":
      let acao = p["acao"] as? String ?? ""
      switch acao {
      case "novo", "criar":
        guard let nome = p["nome"] as? String, !nome.isEmpty else { return erro("informe o nome: orion workspace novo \"Nome\" [--pasta P]") }
        if loja.buscarWorkspace(nome) != nil && Int(nome) == nil { return erro("já existe um workspace chamado \(nome)") }
        let w = loja.criarWorkspace(nome, pasta: p["pasta"] as? String, cor: p["cor"] as? String, simbolo: p["simbolo"] as? String)
        if p["fundo"] as? Bool != true { loja.ativarWorkspace(w) }
        fim(["ok": true, "workspace": w.id, "nome": w.nome])
      case "focar", "ir":
        guard let w = workspace() else { return erro("workspace não encontrado") }
        loja.ativarWorkspace(w)
        fim(["ok": true, "workspace": w.id, "nome": w.nome])
      case "renomear":
        guard let w = workspace(), let nome = p["nome"] as? String, !nome.isEmpty else { return erro("uso: orion workspace renomear ATUAL \"Novo nome\"") }
        w.nome = nome
        loja.salvarDepois()
        fim(["ok": true, "workspace": w.id, "nome": w.nome])
      case "editar":
        guard let w = workspace() else { return erro("workspace não encontrado") }
        if let c = p["cor"] as? String { w.cor = c }
        if let s = p["simbolo"] as? String { w.simbolo = s }
        if let d = p["pasta"] as? String { w.pasta = (d as NSString).expandingTildeInPath }
        loja.salvarDepois()
        fim(["ok": true, "workspace": w.id, "nome": w.nome])
      case "fechar":
        guard let w = workspace() else { return erro("workspace não encontrado") }
        let ocupados = loja.abas(de: w).flatMap { loja.paineisDaAba($0) }.filter { $0.vivo && !$0.ocioso }
        if !ocupados.isEmpty && p["forcar"] as? Bool != true {
          return erro("há \(ocupados.count) painel(is) rodando em \(w.nome); repita com --forcar para fechar mesmo assim")
        }
        loja.fecharWorkspace(w, confirmado: true)
        fim(["ok": true])
      default:
        erro("uso: orion workspace novo|focar|renomear|editar|fechar …")
      }

    case "agentes":
      let filtro = workspace()
      if (p["workspace"] as? String) != nil && filtro == nil { return erro("workspace não encontrado") }
      fim(["ok": true, "agentes": loja.agentes(tudo: p["tudo"] as? Bool ?? false, workspace: filtro?.id).map(descrever)])

    case "agente":
      let kind = p["kind"] as? String ?? "claude"
      guard Ferramenta.eh(kind) else { return erro("use --claude, --codex ou --gemini") }
      // --pai ID (ou "eu"): o agente nasce como subagente daquele maestro, em segundo plano.
      var pai: Painel?
      if let ref = p["pai"] as? String, !ref.isEmpty {
        pai = ref == "eu" ? origem.flatMap { loja.acharPainel($0) } : loja.acharPainel(ref)
        guard pai != nil else { return erro("maestro (--pai) não encontrado") }
      }
      let w = workspace(criar: true) ?? pai?.aba.flatMap { loja.workspace(de: $0) }
        ?? origem.flatMap { loja.painelExistente($0)?.aba }.flatMap { loja.workspace(de: $0) } ?? loja.workspaceAtivo
      var comando = loja.comandoDoTipo(kind) ?? kind
      if let m = p["mensagem"] as? String, !m.isEmpty {
        comando += " '" + m.replacingOccurrences(of: "'", with: "'\\''") + "'"   // a tarefa vai como primeiro prompt
      }
      let pasta = (p["pasta"] as? String).map { ($0 as NSString).expandingTildeInPath } ?? pai?.cwd ?? w?.pasta
      var persona: Persona?
      if p["nome"] != nil || p["papel"] != nil || p["descricao"] != nil {
        var ps = loja.novaPersona(papel: p["papel"] as? String ?? (pai != nil ? "Subagente" : ""))
        if let n = p["nome"] as? String, !n.isEmpty {
          ps.nome = n
          // Nome do elenco (Lyra, Atlas…): vem com a forma e a cor daquele personagem.
          if let e = Persona.elenco.first(where: { $0.nome.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            ps.avatar = e.avatar; ps.cor = e.cor
          }
        }
        if let dsc = p["descricao"] as? String { ps.descricao = String(dsc.prefix(2000)) }
        persona = ps
      }
      let mensagem = p["mensagem"] as? String
      let a = loja.criarAba(kind: kind, cwd: pasta, workspace: w?.id, conta: p["conta"] as? String, comando: comando,
                            titulo: p["titulo"] as? String, ativar: p["fundo"] as? Bool != true && pai == nil,
                            persona: persona, pai: pai?.id, tarefa: mensagem)
      if let st = p["setor"] as? String, !st.isEmpty { loja.definirSetor(a, st) }
      else if let pa = pai?.aba, let st = pa.setor { a.setor = st }     // subagente nasce no setor do maestro
      let novo = loja.painelPrincipal(a)
      novo?.no.retorno = p["retorno"] as? Bool == true
      if p["maestro"] as? Bool == true { novo?.maestro = true }
      if let m = mensagem, !m.isEmpty { novo?.enviadas.append(Conversa.Enviada(texto: m, em: Date(), linha: 0)) }
      novo?.acordar()      // em segundo plano o agente começa já, sem esperar você abrir a aba
      fim(["ok": true, "aba": a.id, "painel": a.painelAtivo, "workspace": w?.nome ?? "", "personagem": novo?.persona?.nome ?? ""])

    case "filhos":
      // Subagentes de um maestro (padrão: de quem está chamando).
      guard let x = painel() else { return erro("painel não encontrado") }
      fim(["ok": true, "maestro": x.id, "agentes": loja.filhos(de: x.id).map(descrever)])

    case "resultado":
      // O que o agente escreveu depois da última mensagem que recebeu (ou a tela recente).
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      let ultimo = x.baloesConversa().last { !$0.meu && !$0.texto.isEmpty }?.texto
      let linhas = p["linhas"] as? Int ?? 120
      let corpo = ultimo.map { t -> String in
        let ls = t.split(separator: "\n", omittingEmptySubsequences: false)
        return ls.count > linhas ? ls.suffix(linhas).joined(separator: "\n") : t
      } ?? x.contextoParaMencao(linhas: linhas).corpo
      let ws = x.aba.flatMap { loja.workspace(de: $0) }?.nome ?? ""
      fim(["ok": true, "painel": x.id, "estado": x.estado.rawValue,
           "texto": "<contexto-orion de=\"@\(x.apelido)\" painel=\"\(x.id)\" tipo=\"\(x.tipoAgente ?? "terminal")\" workspace=\"\(ws)\" estado=\"\(x.estado.rawValue)\" conteudo=\"última resposta\">\n\(corpo)\n</contexto-orion>"])

    case "personagem":
      guard let x = painel(), x.tipoAgente != nil else { return erro("o painel não é um agente") }
      var ps = x.persona ?? loja.novaPersona()
      if let n = p["nome"] as? String, !n.isEmpty { ps.nome = n }
      if let r = p["papel"] as? String { ps.papel = r }
      if let dsc = p["descricao"] as? String { ps.descricao = String(dsc.prefix(2000)) }
      if let a = (p["avatar"] as? String)?.lowercased(), !a.isEmpty {
        guard Mascote.formas.contains(a) else { return erro("avatar desconhecido: use \(Mascote.formas.joined(separator: ", "))") }
        ps.avatar = a
      }
      if let c = p["cor"] as? String, Tema.hexValido(c) != nil { ps.cor = c }
      x.persona = ps
      if p["maestro"] as? Bool == true { x.maestro = true }
      loja.salvarDepois()
      fim(["ok": true, "painel": x.id, "personagem": ps.nome, "papel": ps.papel, "apelido": x.apelido])

    case "fechados":
      fim(["ok": true, "fechados": loja.fechados.enumerated().map { (i, f) -> [String: Any] in
        ["numero": i + 1, "id": f.id, "tipo": f.tipo, "titulo": f.titulo, "personagem": f.persona?.nome ?? "", "pasta": f.pasta,
         "workspace": f.workspaceNome, "sessao": f.sessao ?? "", "ha": Int(Date().timeIntervalSince(f.em))]
      }])

    case "reabrir":
      let ref = p["painel"] as? String ?? "1"
      guard let f = loja.fechados.first(where: { $0.id == ref }) ?? Int(ref).flatMap({ $0 >= 1 && $0 <= loja.fechados.count ? loja.fechados[$0 - 1] : nil }) else {
        return erro(loja.fechados.isEmpty ? "nenhum agente fechado há pouco" : "não achei esse fechado (veja `orion fechados`)")
      }
      guard let a = loja.reabrir(f, ativar: p["fundo"] as? Bool != true) else { return erro("não deu para reabrir") }
      fim(["ok": true, "painel": a.painelAtivo, "sessao": f.sessao ?? ""])

    case "portas":
      loja.atualizarPortas {
        let todas = p["tudo"] as? Bool == true
        fim(["ok": true, "portas": self.loja.portas.filter { todas || $0.painel != nil }.map { x -> [String: Any] in
          let dono = x.painel.flatMap { self.loja.acharPainel($0) }
          return ["porta": x.porta, "pid": Int(x.pid), "processo": x.processo, "endereco": x.endereco, "painel": x.painel ?? "",
                  "titulo": dono.map { $0.aba.flatMap { $0.titulo } ?? $0.titulo } ?? "",
                  "workspace": dono?.aba.flatMap { self.loja.workspace(de: $0) }?.nome ?? ""]
        }])
      }

    case "liberar":
      guard let n = p["porta"] as? Int else { return erro("uso: orion liberar PORTA") }
      loja.atualizarPortas {
        let donos = self.loja.portas.filter { $0.porta == n }
        guard !donos.isEmpty else { return fim(["ok": false, "erro": "ninguém está escutando na porta \(n)"]) }
        var pendentes = donos.count
        for d in donos { self.loja.liberar(d) { pendentes -= 1; if pendentes == 0 {
          let ainda = self.loja.portas.contains { $0.porta == n }
          fim(ainda ? ["ok": false, "erro": "a porta \(n) continua ocupada"] : ["ok": true, "porta": n, "encerrados": donos.map { ["pid": Int($0.pid), "processo": $0.processo] }])
        } } }
      }

    case "mandar":
      // Caixa de entrada: a mensagem entra quando o destinatário estiver livre; devolve o id na hora.
      let ref = p["painel"] as? String ?? ""
      let t = (p["texto"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let extras = anexos()
      if let e = extras.erro { return erro(e) }
      guard !t.isEmpty || !extras.lista.isEmpty || !extras.arquivos.isEmpty else { return erro("mensagem vazia") }
      let eu = origem.flatMap { loja.painelExistente($0) }
      // @time (ou --setor sem destinatário): o roteador escolhe quem recebe.
      if Loja.ehTime(ref) || (ref.isEmpty && p["setor"] != nil) {
        let wid = workspace()?.id ?? eu?.aba.flatMap { loja.workspace(de: $0) }?.id ?? loja.workspaceAtivoID
        let caminhos = extras.lista.filter { $0.tipo == .imagem }.map(\.valor) + extras.arquivos
        guard let m = loja.mandarAoTime(de: eu, texto: t, anexos: caminhos, workspace: wid, setor: p["setor"] as? String,
                                        esperaResposta: p["semResposta"] as? Bool != true) else { return erro("nenhum outro agente neste workspace\((p["setor"] as? String).map { " / setor \($0)" } ?? "")") }
        return fim(["ok": true, "id": m.id, "para": m.para, "paraNome": m.paraNome, "estado": m.estado.rawValue,
                    "esperaResposta": m.esperaResposta, "roteada": true, "depois": m.rota.compactMap { loja.acharPainel($0).map { "@" + $0.apelido } }])
      }
      guard let destino = loja.acharDestino(ref) else { return erro("destinatário não encontrado (use o id, @apelido, o nome ou @time)") }
      if eu === destino { return erro("você não pode mandar mensagem para si mesmo") }
      let caminhos = extras.lista.filter { $0.tipo == .imagem }.map(\.valor) + extras.arquivos
      let m = loja.mandar(de: eu, para: destino, texto: t, anexos: caminhos, esperaResposta: p["semResposta"] as? Bool != true)
      let atual = loja.mensagem(m.id) ?? m
      fim(["ok": true, "id": m.id, "para": destino.id, "paraNome": m.paraNome, "estado": atual.estado.rawValue, "esperaResposta": m.esperaResposta])

    case "responder":
      guard let id = p["mensagem"] as? String, let t = p["texto"] as? String, !t.isEmpty else { return erro("use: orion responder ID_DA_MENSAGEM \"texto\"") }
      let extras = anexos()
      if let e = extras.erro { return erro(e) }
      let eu = origem.flatMap { loja.painelExistente($0) }
      let caminhos = extras.lista.filter { $0.tipo == .imagem }.map(\.valor) + extras.arquivos
      if Loja.ehPasse(t) {
        let (prox, e) = loja.passar(id, de: eu, motivo: nil)
        if let e { return erro(e) }
        return fim(["ok": true, "id": id, "passou": true, "para": prox.map { "@" + $0.apelido } ?? "ninguém (quem mandou foi avisado)"])
      }
      let (r, e) = loja.responder(id, de: eu, texto: t, anexos: caminhos)
      if let e { return erro(e) }
      fim(["ok": true, "id": r?.id ?? "", "respostaA": id, "para": r?.paraNome ?? "você"])

    case "caixa":
      // Mensagens de/para um painel (padrão: quem chama; fora do Orion, todas).
      let alvo = (p["painel"] as? String).flatMap { loja.acharDestino($0) } ?? origem.flatMap { loja.painelExistente($0) }
      let todas = p["tudo"] as? Bool == true || alvo == nil
      let lista = loja.caixa.filter { todas || $0.para == alvo!.id || $0.de == alvo!.id }.suffix(p["linhas"] as? Int ?? 30)
      fim(["ok": true, "painel": alvo?.id ?? "", "mensagens": lista.map { m -> [String: Any] in
        var d = m.dicionario
        d["rotulo"] = m.rotuloEstado
        d["entrada"] = m.para == alvo?.id
        return d
      }])

    case "passar":
      guard let id = p["mensagem"] as? String, !id.isEmpty else { return erro("use: orion passar ID_DA_MENSAGEM [\"motivo\"]") }
      let eu = origem.flatMap { loja.painelExistente($0) }
      let (prox, e) = loja.passar(id, de: eu, motivo: p["texto"] as? String)
      if let e { return erro(e) }
      fim(["ok": true, "id": id, "proximo": prox.map { "@" + $0.apelido } ?? ""])

    case "cancelar":
      guard let id = p["mensagem"] as? String else { return erro("use: orion cancelar ID_DA_MENSAGEM") }
      guard loja.cancelarMensagem(id) else { return erro("só dá para cancelar mensagem que ainda está na fila") }
      fim(["ok": true, "id": id])

    case "equipe":
      // Quem é quem: agentes do workspace (padrão: o de quem chama) com papel e descrição.
      let w = workspace() ?? origem.flatMap { loja.painelExistente($0)?.aba }.flatMap { loja.workspace(de: $0) }
      let lista = loja.agentes(workspace: p["tudo"] as? Bool == true ? nil : w?.id)
      fim(["ok": true, "workspace": w?.nome ?? "", "agentes": lista.map(descrever)])

    case "interromper":
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      guard x.vivo else { return erro("o painel não está rodando") }
      // Pedidos de quem interrompe que ainda estão na fila saem primeiro.
      var cancelados: [String] = []
      if let o = origem {
        for m in loja.caixa where m.de == o && m.para == x.id && m.estado == .naFila {
          if loja.cancelarMensagem(m.id, motivo: "cancelada por quem mandou") { cancelados.append(m.id) }
        }
      }
      // Um agente só interrompe quem trabalha para ele: um subagente seu ou alguém com um pedido
      // seu em andamento. Você (fora de um painel) e --forcar podem sempre.
      if let o = origem, let eu = loja.painelExistente(o), eu !== x, p["forcar"] as? Bool != true {
        let filho = x.pai == eu.id
        let pedido = loja.caixa.contains { $0.de == eu.id && $0.para == x.id && $0.estado == .entregue }
        guard filho || pedido else {
          if !cancelados.isEmpty {
            return fim(["ok": true, "painel": x.id, "interrompido": false, "cancelados": cancelados])
          }
          return erro("@\(x.apelido) não está trabalhando para você (não é seu subagente nem tem um pedido seu). Peça ao usuário, ou use --forcar se ele mandou.")
        }
      }
      if let motivo = (p["motivo"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !motivo.isEmpty {
        loja.pararComMotivo(x, motivo: motivo, de: origem.flatMap { loja.painelExistente($0) })
      } else {
        x.interromper()
      }
      fim(["ok": true, "painel": x.id, "interrompido": true, "cancelados": cancelados])

    case "setor":
      guard let x = painel(padraoOrigem: true), let a = x.aba else { return erro("painel não encontrado") }
      let nome = (p["setor"] as? String) ?? ""
      loja.definirSetor(a, nome.isEmpty ? nil : nome)
      fim(["ok": true, "painel": x.id, "setor": a.setor ?? ""])

    case "hibernar":
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      if let motivo = x.impedimentoHibernar(minimo: 0) { return erro("não dá para hibernar: \(motivo)") }
      guard x.hibernar() else { return erro("não achei o id da conversa para retomar depois") }
      fim(["ok": true, "painel": x.id, "retomar": x.comandoRetomar ?? ""])

    case "acordar":
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      x.acordar()
      fim(["ok": true, "painel": x.id])

    case "reiniciar":
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      loja.reiniciarAgente(x, confirmado: true)
      fim(["ok": true, "painel": x.id])

    case "conta":
      // orion conta ID_DO_PAINEL CONTA → troca a conta da aba; orion conta --padrao CONTA → conta padrão.
      guard let c = (p["conta"] as? String).flatMap({ loja.conta($0) }) else { return erro("conta não encontrada (veja `orion contas`)") }
      if p["padrao"] as? Bool == true {
        loja.definirPadrao(c)
        return fim(["ok": true, "padrao": c.id])
      }
      guard let x = painel(padraoOrigem: false), let a = x.aba else { return erro("painel não encontrado") }
      loja.trocarConta(a, para: c, confirmarReinicio: false)
      fim(["ok": true, "painel": x.id, "conta": c.id])

    case "uso":
      if p["atualizar"] as? Bool == true { loja.atualizarUsos(forcar: true) }
      fim(["ok": true, "claude": loja.ajustes.usoClaude, "contas": loja.contas.map { c -> [String: Any] in
        var d: [String: Any] = ["id": c.id, "tipo": c.tipo, "nome": c.nome, "email": c.email, "logado": c.logado,
                                "padrao": loja.contaPadrao(c.tipo)?.id == c.id]
        if let u = loja.usoVisivel(c.id) {
          for (k, v) in u.dicionario { d[k] = v }
          if let h = u.h5 { d["pct5h"] = h.pctAtual }
          if let s = u.d7 { d["pct7d"] = s.pctAtual }
        }
        return d
      }])

    case "depurar":
      // Só para testes automáticos (não aparece na ajuda).
      switch p["alvo"] as? String ?? "" {
      case "uso":
        guard let id = p["conta"] as? String, loja.conta(id) != nil else { return erro("conta não encontrada") }
        var d: [String: Any] = ["em": ISO8601DateFormatter().string(from: Date())]
        let f = ISO8601DateFormatter()
        if let h = p["h5"] as? Double { d["h5"] = ["pct": h, "reinicia": f.string(from: Date().addingTimeInterval(2.4 * 3600))] }
        if let s = p["d7"] as? Double { d["d7"] = ["pct": s, "reinicia": f.string(from: Date().addingTimeInterval(3.2 * 86400))] }
        loja.usos[id] = Uso(d)
        fim(["ok": true])
      case "ancoras":
        fim(["ok": true, "ancoras": loja.ancoras.mapValues { [$0.minX, $0.minY, $0.width, $0.height].map { Double($0) } }])
      case "estado":
        guard let x = painel(padraoOrigem: false), let e = EstadoPainel(rawValue: p["estado"] as? String ?? "") else { return erro("painel/estado") }
        x.estadoFixo = e
        x.estado = e; x.desde = Date().addingTimeInterval(-(p["tempo"] as? Double ?? 0))
        if let t = p["titulo"] as? String { x.tituloOSC = t }
        fim(["ok": true])
      case "agente":
        // Faz um painel de shell aparecer como agente (sem abrir o Claude/Codex de verdade).
        guard let x = painel(padraoOrigem: false) else { return erro("painel") }
        x.no.kind = p["kind"] as? String ?? "claude"
        x.aba?.kind = x.no.kind
        fim(["ok": true])
      case "contas":
        loja.carregarContas()
        fim(["ok": true])
      case "tamanho":
        guard let j = loja.janela else { return erro("sem janela") }
        var f = j.frame
        f.size = NSSize(width: p["largura"] as? Double ?? Double(f.width), height: p["altura"] as? Double ?? Double(f.height))
        j.setFrame(f, display: true)
        fim(["ok": true])
      case "arrasto":
        let passos = (0...24).map { 0.3 + Double($0) * 0.015 }
        guard (NSApp.delegate as? Delegado)?.area.simularArrasto(passos) == true else { return erro("a aba ativa não tem divisão na raiz") }
        fim(["ok": true])
      case "tema":
        let id = p["titulo"] as? String ?? (p["painel"] as? String) ?? "orion"
        guard Tema.existe(id) else { return erro("tema não encontrado: \(Tema.todos.map(\.id).joined(separator: ", "))") }
        loja.escolherTema(Tema.porId(id))
        fim(["ok": true, "tema": loja.tema.id, "claro": loja.tema.claro])
      case "ajuste":
        // orion depurar ajuste CHAVE VALOR — muda qualquer ajuste (número, true/false ou texto).
        guard let chave = p["painel"] as? String, let bruto = p["texto"] as? String,
              let d = try? JSONEncoder().encode(loja.ajustes), var j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              j[chave] != nil else { return erro("ajuste desconhecido") }
        if bruto == "true" || bruto == "false" { j[chave] = bruto == "true" }
        else if let n = Double(bruto), !(j[chave] is String) { j[chave] = n } else { j[chave] = bruto }
        guard let d2 = try? JSONSerialization.data(withJSONObject: j), let novo = try? JSONDecoder().decode(Ajustes.self, from: d2) else { return erro("valor inválido") }
        loja.ajustes = novo
        fim(["ok": true])
      case "dialogo":
        switch p["painel"] as? String ?? "confirmar" {
        case "texto": if let a = loja.abaAtiva { loja.renomear(a) }
        case "workspace": loja.novoWorkspacePerguntando()
        case "agente": loja.novoAgentePerguntando()
        case "conta": loja.novaContaPerguntando("claude")
        case "personagem": if let x = loja.painelAtivo { loja.editarPersonagem(x) }
        case "fechar": loja.cancelarDialogo()
        case "ok": loja.confirmarDialogo()
        default:
          loja.confirmar("Fechar “Claude Code”?", "Ainda está rodando: claude. Fechar encerra o processo.", "Fechar", destrutivo: true) { }
        }
        fim(["ok": true])
      case "menu":
        // Abre o menu de contexto do terminal para um caminho (ou sem alvo) e o fecha sozinho.
        guard let x = painel(padraoOrigem: false) else { return erro("painel") }
        let alvo = (p["texto"] as? String).flatMap { Detector.alvo(em: $0, coluna: p["coluna"] as? Int ?? 2, cwd: x.cwd) }
        let itens = MenuTerminal.montar(painel: x, alvo: alvo).items.map { $0.isSeparatorItem ? "—" : ($0.isEnabled ? "" : "(desligado) ") + $0.title }
        fim(["ok": true, "alvo": alvo?.caminho ?? "", "tipo": alvo?.tipo.rawValue ?? "", "itens": itens])
        // Com --tempo, o menu também aparece na tela por esse tempo (fecha sozinho).
        if let t = p["tempo"] as? Double, t > 0 {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainActor.assumeIsolated { MenuTerminal.mostrarParaTeste(painel: x, alvo: alvo, segundos: t) }
          }
        }
      case "colar":
        // Testa o caminho do ⌘V / arrastar com uma área de transferência PRIVADA (não mexe na do
        // usuário): --texto ARQUIVO. Imagem vai como dados PNG (como uma captura de tela copiada);
        // com --aceitar, vai como arquivo (como copiar no Finder).
        guard let x = painel(padraoOrigem: false), let arq = p["texto"] as? String, let c = x.caixa?.campoDoCompose else { return erro("painel com compose à vista e --texto ARQUIVO") }
        let pb = NSPasteboard(name: NSPasteboard.Name("orion-teste-" + UUID().uuidString))
        pb.clearContents()
        if p["aceitar"] as? Bool == true { pb.writeObjects([URL(fileURLWithPath: arq) as NSURL]) }
        else if let d = try? Data(contentsOf: URL(fileURLWithPath: arq)) { pb.setData(d, forType: .png) }
        let ok = c.receber(pb)
        pb.releaseGlobally()
        fim(["ok": ok, "anexos": x.rascunho.anexos.map { ["tipo": $0.tipo.rawValue, "valor": $0.valor] }, "texto": x.rascunho.texto])
      case "alvo":
        // Detecção pura: orion depurar alvo ID --texto "linha" --coluna N
        guard let x = painel(padraoOrigem: false), let linha = p["texto"] as? String else { return erro("painel e --texto") }
        let a = Detector.alvo(em: linha, coluna: p["coluna"] as? Int ?? 0, cwd: x.cwd)
        fim(["ok": true, "tipo": a?.tipo.rawValue ?? "nada", "alvo": a?.caminho ?? "", "linha": a?.linha ?? NSNull()])
      case "ponto":
        // Detecção na tela de verdade: linha e coluna (a partir de 0) do que está visível no terminal.
        guard let x = painel(padraoOrigem: false), let v = x.view, let dim = v.terminalInputStateSnapshot()?.dimensions else { return erro("painel") }
        let ideal = v.getOptimalFrameSize()
        let ac = ideal.height / CGFloat(max(1, dim.rows)), lc = min(ideal.width, v.bounds.width) / CGFloat(max(1, dim.cols))
        let pt = NSPoint(x: (CGFloat(p["coluna"] as? Int ?? 0) + 0.5) * lc, y: v.bounds.height - (CGFloat(p["linha"] as? Int ?? 0) + 0.5) * ac)
        let a = x.alvo(em: pt)
        fim(["ok": true, "tipo": a?.tipo.rawValue ?? "nada", "alvo": a?.caminho ?? ""])
      case "mencao":
        // Digita no compose (como se fosse o teclado) e deixa a lista do @ aberta.
        guard let x = painel(padraoOrigem: false) else { return erro("painel") }
        let texto = p["texto"] as? String ?? "@"
        loja.focar(x, teclado: false)
        x.rascunho.manual = true
        x.atualizarCompose()
        x.caixa?.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          MainActor.assumeIsolated {
            guard let c = x.caixa?.campoDoCompose else { return fim(["ok": false, "erro": "o compose não está na tela"]) }
            x.rascunho.campo = c
            c.string = texto
            c.setSelectedRange(NSRange(location: (texto as NSString).length, length: 0))
            c.didChangeText()
            if p["aceitar"] as? Bool == true {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { x.rascunho.aceitar(x); fim(["ok": true, "texto": x.rascunho.texto]) } }
            } else { fim(["ok": true, "itens": x.rascunho.itens.map(\.rotulo)]) }
          }
        }
      case "editar-tema":
        let n = Tema.duplicar(loja.tema)
        loja.versaoTemas += 1
        loja.escolherTema(n)
        loja.temaEmEdicao = n.id
        (NSApp.delegate as? Delegado)?.abrirAjustes(aba: "aparencia")
        fim(["ok": true, "tema": n.id])
      case "soltar":
        // Testa o arrasto para o painel com uma área de transferência privada: --texto ARQUIVO
        // (--aceitar = como arquivo; sem = como dados de imagem).
        guard let x = painel(padraoOrigem: false), let arq = p["texto"] as? String else { return erro("painel e --texto ARQUIVO") }
        let pb = NSPasteboard(name: NSPasteboard.Name("orion-teste-" + UUID().uuidString))
        pb.clearContents()
        if p["aceitar"] as? Bool == true { pb.writeObjects([URL(fileURLWithPath: arq) as NSURL]) }
        else if let d = try? Data(contentsOf: URL(fileURLWithPath: arq)) { pb.setData(d, forType: .png) }
        let ok = x.receber(pb)
        pb.releaseGlobally()
        fim(["ok": ok, "anexos": x.rascunho.anexos.map { ["tipo": $0.tipo.rawValue, "valor": $0.valor] }, "texto": x.rascunho.texto])
      case "sessao":
        // Qual id de conversa o app acha que este agente tem (só nomes e datas de arquivo).
        guard let x = painel(padraoOrigem: false), let t = x.tipoAgente, let a = x.aba else { return erro("agente") }
        let cfg = loja.conta(a.conta(t))?.dir
        let s = Sessoes.descobrir(tipo: t, config: cfg, cwd: x.cwd, desde: x.iniciadoEm, atividade: x.leitor.ultimaSaida)
        fim(["ok": true, "sessao": s ?? "", "pasta": t == "claude" ? Sessoes.pastaDoClaude(config: cfg, cwd: x.cwd).path : ""])
      case "aliviar":
        Memoria.aliviar()
        fim(["ok": true])
      case "sair":
        // O mesmo caminho do ⌘Q (com o diálogo do app se houver algo rodando).
        fim(["ok": true])
        // Pelo run loop (como um evento de menu), não por um bloco do GCD: o encerramento com
        // diálogo roda um laço interno, e a fila principal precisa continuar andando.
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0.1)
      case "sistema":
        loja.sistemaMudouAparencia(escuro: (p["painel"] as? String) != "claro")
        fim(["ok": true, "claro": loja.tema.claro])
      case "frente":
        // Janela à frente sem ativar o app (o teclado continua com quem estava): o macOS só
        // redesenha o texto do terminal em janela visível.
        loja.janela?.orderFrontRegardless()
        fim(["ok": true])
      case "fundo":
        loja.janela?.orderBack(nil)
        fim(["ok": true])
      case "lateral":
        loja.ajustes.larguraLateral = p["largura"] as? Double ?? 240
        fim(["ok": true])
      case "proporcao":
        guard let a = loja.abaAtiva, a.arvore.tipo == .divisao else { return erro("a aba ativa não tem divisão") }
        a.arvore.proporcao = p["valor"] as? Double ?? 0.5
        a.versaoArvore += 1
        loja.aoMudarLayout?()
        fim(["ok": true])
      default: erro("alvo de depuração desconhecido")
      }

    case "ler":
      guard let x = painel() else { return erro("painel não encontrado") }
      fim(["ok": true, "painel": x.id, "texto": x.texto(linhas: p["linhas"] as? Int ?? 0)])

    case "enviar":
      guard let x = painel(padraoOrigem: false), let t = p["texto"] as? String else { return erro("informe o painel e o texto") }
      guard x.vivo || !x.iniciado else { return erro("o painel não está rodando") }
      let extras = anexos()
      if let e = extras.erro { return erro(e) }
      if extras.lista.isEmpty && extras.arquivos.isEmpty {
        guard x.vivo else { return erro("o painel não está rodando") }
        if (p["enter"] as? Bool) == true, x.tipoAgente != nil, !t.isEmpty {
          // Mensagem inteira para um agente: entra na conversa e, se for a primeira, dá nome à tarefa.
          x.enviadas.append(Conversa.Enviada(texto: t, em: Date(), linha: x.linhaDoCursor()))
          if x.tarefa == nil, let curta = Nomes.tarefaCurta(t) { x.tarefa = curta; loja.salvarDepois() }
        }
        x.escrever(t + ((p["enter"] as? Bool) == true ? "\r" : ""))
      } else {
        // Com anexos ou menções: mesma montagem do compose (imagens como caminho, contexto em bloco).
        // Arquivos vão como anexo (entram na mensagem como @caminho e aparecem na conversa).
        let arquivos = extras.arquivos.map { Anexo(tipo: .arquivo, valor: $0, rotulo: ($0 as NSString).lastPathComponent) }
        loja.enviarComposto(de: x, texto: t, anexos: extras.lista + arquivos, enter: (p["enter"] as? Bool) == true)
      }
      fim(["ok": true, "painel": x.id])

    case "compor":
      // Deixa um rascunho no compose do painel (não envia): o usuário revisa e manda.
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      let extras = anexos()
      if let e = extras.erro { return erro(e) }
      x.rascunho.manual = true
      x.atualizarCompose()
      if let t = p["texto"] as? String { x.rascunho.definir(t) }
      if p["limpar"] as? Bool == true { x.rascunho.anexos = [] }
      extras.lista.forEach { x.rascunho.anexar($0) }
      if !extras.arquivos.isEmpty { x.anexar(caminhos: extras.arquivos) }     // cartões com prévia, como no arrasto
      if p["focar"] as? Bool == true { loja.focar(x, teclado: false); x.focarCompose() }
      fim(["ok": true, "painel": x.id, "texto": x.rascunho.texto, "anexos": x.rascunho.anexos.map { ["tipo": $0.tipo.rawValue, "valor": $0.valor] }])

    case "contexto":
      guard let x = painel() else { return erro("painel não encontrado") }
      fim(["ok": true, "painel": x.id, "apelido": x.apelido,
           "texto": Compose.contexto(de: x, apelido: x.apelido, loja: loja, linhas: p["linhas"] as? Int ?? 80, sempreInline: true)])

    case "marcar":
      guard let x = painel(padraoOrigem: true) else { return erro("painel não encontrado") }
      let m = (p["marca"] as? String ?? "").lowercased()
      switch m {
      case "revisar": loja.marcar(x, "revisar")
      case "concluido", "concluído": loja.marcar(x, "concluido")
      case "nada", "limpar", "": loja.marcar(x, nil)
      default: return erro("use: revisar | concluido | nada")
      }
      fim(["ok": true, "painel": x.id, "marca": x.marca ?? ""])

    case "memoria":
      loja.amostrarMemoria(forcar: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
        MainActor.assumeIsolated {
          fim(["ok": true, "app": Int(self.loja.memoriaApp / 1_048_576), "paineis": Int(self.loja.memoriaPaineis / 1_048_576),
               "lista": self.loja.paineis.values.filter(\.vivo).sorted { $0.memoria > $1.memoria }.map { x -> [String: Any] in
                 ["id": x.id, "titulo": x.aba.flatMap { $0.titulo } ?? x.titulo, "tipo": x.tipoAgente ?? "shell",
                  "mb": Int(x.memoria / 1_048_576), "processos": x.processos,
                  "workspace": x.aba.flatMap { self.loja.workspace(de: $0) }?.nome ?? ""]
               }])
        }
      }

    case "rodar":
      guard let comando = p["comando"] as? String, !comando.isEmpty else { return erro("informe o comando") }
      let esperar = p["esperar"] as? Bool ?? false
      let tempo = p["tempo"] as? Double ?? 600
      if p["painel"] != nil {
        guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
        rodar(comando, em: x, esperar: esperar, tempo: tempo, fim)
      } else {
        ajudante(para: origem) { x in
          guard let x else { return erro("não consegui abrir um painel para rodar") }
          self.rodar(comando, em: x, esperar: esperar, tempo: tempo, fim)
        }
      }

    case "nova":
      let kind = p["kind"] as? String ?? "shell"
      let w = workspace(criar: true)
      let pasta = (p["pasta"] as? String).map { ($0 as NSString).expandingTildeInPath }
      let a = loja.criarAba(kind: kind, cwd: pasta, workspace: w?.id, conta: p["conta"] as? String,
                            comando: p["comando"] as? String, titulo: p["titulo"] as? String, ativar: p["fundo"] as? Bool != true)
      if p["fundo"] as? Bool == true { loja.painelPrincipal(a)?.acordar() }
      fim(["ok": true, "aba": a.id, "painel": a.painelAtivo])

    case "dividir":
      guard let x = painel() else { return erro("painel não encontrado") }
      let voltar = loja.painelAtivo
      loja.focar(x, teclado: false)
      guard let novo = loja.dividir(horizontal: !(p["abaixo"] as? Bool ?? false), comando: p["comando"] as? String) else { return erro("não deu para dividir") }
      if let v = voltar, p["focar"] as? Bool != true { loja.focar(v) }
      fim(["ok": true, "painel": novo.id])

    case "focar":
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      loja.focar(x)
      if !Armazem.semFoco { NSApp.activate(ignoringOtherApps: true) }
      fim(["ok": true])

    case "fechar":
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      loja.fecharPainel(x, confirmado: true)
      fim(["ok": true])

    case "renomear":
      guard let x = painel(), let a = x.aba else { return erro("painel não encontrado") }
      let t = (p["titulo"] as? String) ?? ""
      a.titulo = t.isEmpty ? nil : t
      loja.salvarDepois()
      fim(["ok": true])

    case "esperar":
      let limite = Date().addingTimeInterval(p["tempo"] as? Double ?? 600)
      if p["filhos"] as? Bool == true {
        // Espera todos os subagentes de um maestro pararem.
        guard let m = painel() else { return erro("painel não encontrado") }
        let lista = loja.filhos(de: m.id)
        guard !lista.isEmpty else { return erro("este painel não tem subagentes") }
        var faltam = lista.count
        var saida: [[String: Any]] = []
        for f in lista {
          esperarLivre(f, limite: limite) { r in
            saida.append(["painel": f.id, "personagem": f.persona?.nome ?? "", "estado": r["estado"] ?? "", "ok": r["ok"] ?? false])
            faltam -= 1
            if faltam == 0 { fim(["ok": !saida.contains { $0["ok"] as? Bool != true }, "agentes": saida, "erro": "tempo esgotado esperando algum subagente"]) }
          }
        }
        return
      }
      guard let x = painel(padraoOrigem: false) else { return erro("painel não encontrado") }
      esperarLivre(x, limite: limite, fim)

    case "notificar":
      guard let x = painel() else { return erro("sem painel") }
      loja.notificar(x, titulo: p["titulo"] as? String ?? "Orion", corpo: p["texto"] as? String ?? "")
      fim(["ok": true])

    case "contas":
      fim(["ok": true, "contas": loja.contas.map { ["id": $0.id, "tipo": $0.tipo, "nome": $0.nome, "email": $0.email, "logado": $0.logado,
                                                     "padrao": loja.contaPadrao($0.tipo)?.id == $0.id] }])

    case "ui":
      let d = NSApp.delegate as? Delegado
      switch p["alvo"] as? String ?? "" {
      case "ajustes": d?.abrirAjustes(aba: p["secao"] as? String ?? "aparencia")
      case "contas": d?.abrirAjustes(aba: "contas")
      case "paleta": loja.abrirQuadro(false); loja.paletaAberta = true
      case "quadro": loja.abrirQuadro(true)
      case "lateral": loja.ajustes.barraLateral.toggle()
      case "barra": loja.ajustes.barraAgentes.toggle()
      case "uso", "ferramenta", "claude", "codex", "gemini":
        // "uso": o resumo (o mesmo do hover); "ferramenta" / "claude" / "codex": o painel expandido
        // (o mesmo do clique). Ficam presos à âncora pedida até `orion ui fechar`.
        let alvoUI = p["alvo"] as? String ?? ""
        let tipo = Ferramenta.eh(alvoUI) ? alvoUI : (Ferramenta.de(p["secao"] as? String)?.id ?? "claude")
        let nome = p["ancora"] as? String ?? "topo-\(tipo)"
        let alvo = loja.ancoras[nome] ?? loja.ancoras["topo-\(tipo)"] ?? loja.ancoras["doca-\(tipo)"] ?? CGRect(x: 400, y: 20, width: 30, height: 30)
        loja.usoAgendado?.cancel()
        loja.usoHover = UsoHover(tipo: tipo, ancora: alvo, fixo: true, expandido: alvoUI != "uso")
      case "compose":
        guard let x = (p["secao"] as? String).flatMap({ loja.acharPainel($0) }) ?? loja.painelAtivo else { return erro("painel não encontrado") }
        loja.focar(x, teclado: false)
        x.rascunho.manual = true
        x.atualizarCompose()
        x.focarCompose()
      case "novo-agente": loja.novoAgentePerguntando(kind: Ferramenta.de(p["secao"] as? String)?.id ?? "claude")
      case "subagente":
        guard let x = (p["secao"] as? String).flatMap({ loja.acharPainel($0) }) ?? loja.painelAtivo, let t = x.tipoAgente else { return erro("escolha um agente") }
        loja.novoAgentePerguntando(kind: t, pai: x.id)
      case "personagem":
        guard let x = (p["secao"] as? String).flatMap({ loja.acharPainel($0) }) ?? loja.painelAtivo, x.tipoAgente != nil else { return erro("escolha um agente") }
        loja.editarPersonagem(x)
      case "conversa":
        guard let x = (p["secao"] as? String).flatMap({ loja.acharPainel($0) }) ?? loja.painelAtivo else { return erro("painel não encontrado") }
        loja.focar(x, teclado: false)
        x.conversa.toggle()
      case "portas": loja.atualizarPortas(); loja.pedirPortas += 1
      case "fechados": loja.pedirFechados += 1
      case "workspaces": loja.pedirWorkspaces += 1
      case "historico", "agentes": loja.ajustes.barraLateral = true; loja.abrirQuadro(false); loja.modoLateral = (p["alvo"] as? String) ?? "agentes"
      case "novo-workspace": loja.novoWorkspacePerguntando()
      case "proximo", "esperando": loja.irParaProximoEsperando()
      case "temas": d?.abrirAjustes(aba: "aparencia")
      case "memoria": loja.amostrarMemoria(forcar: true)
      case "fechar":
        loja.paletaAberta = false; loja.abrirQuadro(false); loja.fecharUso(); loja.cancelarDialogo(); loja.temaEmEdicao = nil
        loja.fecharPopovers += 1
        Memoria.aliviar()
        loja.paineis.values.forEach { $0.rascunho.fecharMencao($0) }
        d?.janelaAjustes?.close()
      default: return erro("alvos: quadro, paleta, ajustes [seção], contas, temas, uso [ferramenta], claude, codex, gemini, compose [ID], conversa [ID], portas, novo-agente [ferramenta], subagente [ID], personagem [ID], novo-workspace, lateral, barra, fechar")
      }
      if !Armazem.semFoco { NSApp.activate(ignoringOtherApps: true) }
      fim(["ok": true])

    case "versao":
      let at = Atualizador.shared
      at.verificar { v, erro in
        var r: [String: Any] = ["ok": true, "versao": at.atual]
        if let v { r["disponivel"] = v.numero; r["pagina"] = v.pagina.absoluteString }
        if let erro { r["aviso"] = erro }
        fim(r)
      }

    case "atualizar":
      let at = Atualizador.shared
      at.verificar { v, erro in
        guard let v else { fim(["ok": true, "versao": at.atual, "mensagem": erro ?? "já está na versão mais nova"]); return }
        fim(["ok": true, "versao": at.atual, "disponivel": v.numero, "mensagem": "instalando \(v.numero); o app reabre sozinho"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { at.instalarAgora() }
      }

    case "estado":
      fim(["ok": true, "versao": Shell.versao, "workspaces": loja.workspaces.count, "abas": loja.abas.count,
           "paineis": loja.paineis.values.filter(\.vivo).count, "workspace": loja.workspaceAtivo?.nome ?? ""])

    default:
      erro("comando desconhecido: \(cmd)")
    }
  }

  /// Estado no vocabulário do CLI (o mesmo da v0.2: parado, saiu, trabalhando, rodando, aguardando, pronto).
  @MainActor private func estadoTexto(_ x: Painel) -> String {
    switch x.estado {
    case .dormindo: return "parado"
    case .esperando: return "aguardando"
    default: return x.estado.rawValue
    }
  }

  /// Painel auxiliar onde `orion rodar` executa sem painel informado: uma divisão abaixo do
  /// painel de quem pediu, reaproveitada enquanto estiver livre.
  @MainActor private func ajudante(para origem: String?, _ pronto: @escaping (Painel?) -> Void) {
    let chave = origem ?? "_"
    if let id = ajudantes[chave], let x = loja.painelExistente(id), x.vivo, x.noPrompt { pronto(x); return }
    let base = origem.flatMap { loja.painelExistente($0) } ?? loja.painelAtivo
    let voltar = loja.painelAtivo
    if let base { loja.focar(base, teclado: false) }
    guard let novo = loja.dividir(horizontal: false) else { pronto(nil); return }
    novo.aba.map { _ in novo.no.comando = nil }
    if let v = voltar { loja.focar(v) }
    ajudantes[chave] = novo.id
    esperarPrompt(novo, limite: Date().addingTimeInterval(15), pronto)
  }

  @MainActor private func esperarPrompt(_ x: Painel, limite: Date, _ pronto: @escaping (Painel?) -> Void) {
    if x.noPrompt { pronto(x); return }
    if Date() > limite { pronto(x.vivo ? x : nil); return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { self.esperarPrompt(x, limite: limite, pronto) } }
  }

  @MainActor private func rodar(_ comando: String, em x: Painel, esperar: Bool, tempo: Double, _ fim: @escaping ([String: Any]) -> Void) {
    guard x.vivo else { fim(["ok": false, "erro": "o painel não está rodando"]); return }
    guard x.noPrompt else { fim(["ok": false, "erro": "o painel está ocupado (\(x.processo)); use outro ou espere", "painel": x.id]); return }
    if !esperar {
      x.escrever("\u{15}" + comando + "\r")
      fim(["ok": true, "painel": x.id])
      return
    }
    var respondeu = false
    x.aoTerminarComando.append { r in
      guard !respondeu else { return }
      respondeu = true
      fim(["ok": true, "painel": x.id, "codigo": r.codigo ?? NSNull(), "saida": r.saida, "duracao": r.duracao])
    }
    x.escrever("\u{15}" + comando + "\r")
    DispatchQueue.main.asyncAfter(deadline: .now() + tempo) {
      guard !respondeu else { return }
      respondeu = true
      fim(["ok": false, "erro": "tempo esgotado (\(Int(tempo)) s); o comando continua rodando", "painel": x.id])
    }
  }

  @MainActor private func esperarLivre(_ x: Painel, limite: Date, livreDesde: Date? = nil, _ fim: @escaping ([String: Any]) -> Void) {
    let livre = !x.vivo || (!x.ocupado && x.progresso == nil && (x.noPrompt || x.agente != nil))
    let desde = livre ? (livreDesde ?? Date()) : nil
    if let d = desde, Date().timeIntervalSince(d) >= 2.5 {
      var r: [String: Any] = ["ok": true, "painel": x.id, "estado": estadoTexto(x)]
      if let u = x.ultimoResultado { r["codigo"] = u.codigo ?? NSNull(); r["comando"] = u.comando }
      fim(r); return
    }
    if Date() > limite { fim(["ok": false, "erro": "tempo esgotado", "estado": estadoTexto(x)]); return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      MainActor.assumeIsolated { self.esperarLivre(x, limite: limite, livreDesde: desde, fim) }
    }
  }
}
