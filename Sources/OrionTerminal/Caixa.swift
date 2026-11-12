import Foundation
import AppKit

// Caixa de entrada dos agentes: mensagens assíncronas entre agentes (e de scripts/usuário).
//
// `orion mandar @vega "tarefa"` não digita nada no terminal na hora: a mensagem entra na fila do
// destinatário e só é colada quando ele está livre (parado, esperando você). Várias mensagens
// acumuladas viram uma só entrega. Quem manda não espera: encerra o turno e a resposta chega
// sozinha como mensagem nova (`orion responder ID "…"`). Se o destinatário parar sem responder,
// o remetente recebe um aviso com o caminho da última resposta dele.

struct Mensagem: Identifiable, Equatable {
  enum Estado: String { case naFila, entregue, respondida, semResposta, cancelada, passada }

  let id: String
  let de: String?            // painel remetente (nil = você ou um script)
  let deNome: String         // "@vega", "você"
  let para: String           // painel destinatário
  let paraNome: String
  var texto: String
  var anexos: [String]
  let respostaA: String?     // id da mensagem respondida
  let esperaResposta: Bool
  let criada: Date
  var estado: Estado
  var entregueEm: Date?
  var motivo: String?        // por que foi cancelada / o que aconteceu
  var resposta: String?      // texto da resposta (para mensagens de você/script)
  var doTime = false         // mandada ao time: o roteador escolheu o destinatário
  var rota: [String] = []    // próximos candidatos, se este passar a vez

  var dicionario: [String: Any] {
    var d: [String: Any] = ["id": id, "deNome": deNome, "para": para, "paraNome": paraNome, "texto": texto, "anexos": anexos,
                            "esperaResposta": esperaResposta, "criada": criada.timeIntervalSince1970, "estado": estado.rawValue]
    if let de { d["de"] = de }
    if let respostaA { d["respostaA"] = respostaA }
    if let entregueEm { d["entregueEm"] = entregueEm.timeIntervalSince1970 }
    if let motivo { d["motivo"] = motivo }
    if let resposta { d["resposta"] = resposta }
    if doTime { d["doTime"] = true }
    if !rota.isEmpty { d["rota"] = rota }
    return d
  }

  init(id: String = "m-" + UUID().uuidString.prefix(6).lowercased(), de: String?, deNome: String, para: String, paraNome: String,
       texto: String, anexos: [String] = [], respostaA: String? = nil, esperaResposta: Bool) {
    self.id = id; self.de = de; self.deNome = deNome; self.para = para; self.paraNome = paraNome
    self.texto = texto; self.anexos = anexos; self.respostaA = respostaA; self.esperaResposta = esperaResposta
    criada = Date(); estado = .naFila
  }

  init?(_ d: [String: Any]) {
    guard let i = d["id"] as? String, let p = d["para"] as? String, let t = d["texto"] as? String else { return nil }
    id = i; para = p; texto = t
    de = d["de"] as? String
    deNome = d["deNome"] as? String ?? "você"
    paraNome = d["paraNome"] as? String ?? p
    anexos = d["anexos"] as? [String] ?? []
    respostaA = d["respostaA"] as? String
    esperaResposta = d["esperaResposta"] as? Bool ?? false
    criada = Date(timeIntervalSince1970: d["criada"] as? Double ?? 0)
    estado = Estado(rawValue: d["estado"] as? String ?? "") ?? .cancelada
    entregueEm = (d["entregueEm"] as? Double).map { Date(timeIntervalSince1970: $0) }
    motivo = d["motivo"] as? String
    resposta = d["resposta"] as? String
    doTime = d["doTime"] as? Bool ?? false
    rota = d["rota"] as? [String] ?? []
  }

  var rotuloEstado: String {
    switch estado {
    case .naFila: return "na fila"
    case .entregue: return esperaResposta ? "entregue, aguardando resposta" : "entregue"
    case .respondida: return "respondida"
    case .semResposta: return "parou sem responder"
    case .cancelada: return "cancelada"
    case .passada: return "passou a vez"
    }
  }
}

extension Loja {
  static let limiteCaixa = 300

  func gravarCaixa() {
    if caixa.count > Loja.limiteCaixa {
      // Descarta primeiro as mais antigas que já terminaram.
      let terminadas = caixa.enumerated().filter { $0.element.estado != .naFila && $0.element.estado != .entregue }.map(\.offset)
      let sobra = caixa.count - Loja.limiteCaixa
      let fora = Set(terminadas.prefix(sobra))
      caixa = caixa.enumerated().filter { !fora.contains($0.offset) }.map(\.element)
    }
    Armazem.gravar("caixa.json", caixa.map(\.dicionario))
  }

  func carregarCaixa() {
    caixa = ((Armazem.ler("caixa.json") as? [[String: Any]]) ?? []).compactMap(Mensagem.init)
  }

  func mensagem(_ id: String) -> Mensagem? { caixa.first { $0.id == id } }

  /// Quantas mensagens esperam para entrar neste painel.
  func naFila(para id: String) -> Int { caixa.filter { $0.para == id && $0.estado == .naFila }.count }

  /// Destinatário por id do painel, "@apelido" ou nome do personagem.
  func acharDestino(_ ref: String) -> Painel? {
    let r = ref.hasPrefix("@") ? String(ref.dropFirst()) : ref
    if let p = acharPainel(r) { return p }
    let alvo = r.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    let todos = agentes(tudo: true)
    return todos.first { $0.apelido == alvo }
      ?? todos.first { ($0.persona?.nome ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased() == alvo }
  }

  // MARK: Mandar e responder

  /// Põe uma mensagem na caixa de `para`. Ela entra no terminal quando ele estiver livre.
  @discardableResult
  func mandar(de origem: Painel?, para destino: Painel, texto: String, anexos: [String] = [], esperaResposta: Bool = true,
              respostaA: String? = nil, doTime: Bool = false, rota: [String] = []) -> Mensagem {
    // O mesmo texto para o mesmo destinatário, ainda pendente, na última hora: não duplica.
    if let igual = caixa.last(where: { $0.de == origem?.id && $0.para == destino.id && $0.texto == texto && $0.respostaA == respostaA
                                       && ($0.estado == .naFila || $0.estado == .entregue) && Date().timeIntervalSince($0.criada) < 3600 }) {
      return igual
    }
    var m = Mensagem(de: origem?.id, deNome: origem.map { "@" + $0.apelido } ?? "você", para: destino.id, paraNome: "@" + destino.apelido,
                     texto: texto, anexos: anexos, respostaA: respostaA, esperaResposta: esperaResposta && origem != nil)
    m.doTime = doTime
    m.rota = rota
    caixa.append(m)
    gravarCaixa()
    processarCaixa()          // livre agora? entra já
    return m
  }

  /// Resposta a uma mensagem: volta para quem mandou (ou, se foi você/um script, fica guardada e avisa).
  @discardableResult
  func responder(_ id: String, de origem: Painel?, texto: String, anexos: [String] = []) -> (Mensagem?, String?) {
    guard let i = caixa.firstIndex(where: { $0.id == id }) else { return (nil, "mensagem não encontrada: \(id)") }
    if Loja.ehPasse(texto) { return (nil, passar(id, de: origem, motivo: nil).erro) }
    let original = caixa[i]
    caixa[i].estado = .respondida
    caixa[i].resposta = texto
    // Mensagens do mesmo remetente que entraram na mesma entrega: uma resposta vale para todas.
    if let quando = original.entregueEm {
      for j in caixa.indices where j != i && caixa[j].estado == .entregue && caixa[j].de == original.de
        && caixa[j].para == original.para && caixa[j].entregueEm.map({ abs($0.timeIntervalSince(quando)) < 1 }) == true {
        caixa[j].estado = .respondida
        caixa[j].resposta = "(respondida junto com \(id))"
      }
    }
    // Resposta que é só confirmação ("ok", "valeu", "feito") fica registrada mas não acorda
    // ninguém — senão dois agentes educados viram pingue-pongue de agradecimentos.
    if Loja.soConfirmacao(texto) {
      gravarCaixa()
      return (nil, nil)
    }
    if let de = original.de, let remetente = acharPainel(de), remetente.vivo || !remetente.iniciado {
      let r = mandar(de: origem, para: remetente, texto: texto, anexos: anexos, esperaResposta: false, respostaA: id)
      return (r, nil)
    }
    gravarCaixa()
    // Mensagem sua (ou de script): avisa no app.
    if let o = origem {
      notificar(o, titulo: "\(o.persona?.nome ?? o.apelido) respondeu", corpo: String(texto.prefix(160)))
    }
    return (nil, nil)
  }

  /// "ok", "obrigado!", "feito 👍": curta, sem pergunta nem link.
  static func soConfirmacao(_ texto: String) -> Bool {
    let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count < 40, !t.contains("?"), !t.contains("http"), !t.contains("/") else { return false }
    let l = t.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    return ["ok", "okay", "obrigad", "valeu", "feito", "certo", "beleza", "entendido", "combinado", "perfeito", "thanks", "thank you", "done", "show", "blz", "vlw"]
      .contains { l.hasPrefix($0) }
  }

  /// Avisa quem mandou (se foi um agente) que a mensagem não vai chegar.
  private func avisarRemetente(_ m: Mensagem, _ motivo: String) {
    guard let de = m.de, let remetente = acharPainel(de), remetente.vivo || remetente.hibernado else { return }
    caixa.append(Mensagem(de: nil, deNome: "Orion", para: remetente.id, paraNome: "@" + remetente.apelido,
                          texto: "Sua mensagem \(m.id) para \(m.paraNome) não vai ter resposta: \(motivo).", respostaA: m.id, esperaResposta: false))
  }

  func cancelarMensagem(_ id: String, motivo: String = "cancelada") -> Bool {
    guard let i = caixa.firstIndex(where: { $0.id == id }), caixa[i].estado == .naFila else { return false }
    caixa[i].estado = .cancelada
    caixa[i].motivo = motivo
    gravarCaixa()
    return true
  }

  /// Força a entrega de uma mensagem da fila (o usuário decidiu não esperar).
  func entregarAgora(_ id: String) {
    guard let i = caixa.firstIndex(where: { $0.id == id && $0.estado == .naFila }), let p = acharPainel(caixa[i].para) else { return }
    entregar([caixa[i]], para: p)
    caixa[i].estado = .entregue
    caixa[i].entregueEm = Date()
    gravarCaixa()
  }

  func limparCaixa() {
    caixa.removeAll { $0.estado != .naFila && $0.estado != .entregue }
    gravarCaixa()
  }

  // MARK: Entrega

  /// O painel pode receber agora? Agente parado há um instante, ou shell no prompt.
  func livreParaReceber(_ p: Painel) -> Bool {
    if !p.iniciado { return true }                       // dormindo ou hibernado: a entrega acorda o agente
    guard p.vivo else { return false }
    // Painel de agente com o agente fora do ar (subindo, ou saiu com /exit): nunca colar no shell.
    if Ferramenta.eh(p.tipo) && p.agente == nil { return false }
    if dialogo != nil, p.aba?.id == abaAtivaID { return false }
    if p.tipoAgente != nil {
      guard !p.ocupado, p.estado != .trabalhando, p.permissao == nil else { return false }   // nunca por cima de uma pergunta
      return Date().timeIntervalSince(p.leitor.ultimaSaida) > 1.5 && Date().timeIntervalSince(p.ultimaEntrada) > 2
    }
    return p.ocioso
  }

  /// Chamado a cada segundo (e ao mandar): entrega o que estiver na fila de quem está livre e
  /// avisa quem esperava resposta de um agente que parou sem responder.
  func processarCaixa() {
    guard !caixa.isEmpty else { return }
    var mudou = false
    // 1) Entregas.
    let destinos = Set(caixa.filter { $0.estado == .naFila }.map(\.para))
    for id in destinos {
      guard let p = acharPainel(id) else {
        for i in caixa.indices where caixa[i].para == id && caixa[i].estado == .naFila {
          caixa[i].estado = .cancelada; caixa[i].motivo = "o destinatário foi fechado"; mudou = true
        }
        continue
      }
      // Destinatário que não vai mais receber: o processo saiu (e não está hibernado) ou o
      // agente fechou e deixou só o shell há mais de um minuto.
      let saiu = p.iniciado && !p.vivo && !p.hibernado
      let agenteFechou = p.iniciado && p.vivo && Ferramenta.eh(p.tipo) && p.agente == nil && Date().timeIntervalSince(p.iniciadoEm) > 60
      if saiu || agenteFechou {
        let motivo = saiu ? "o terminal de \(p.persona?.nome ?? p.apelido) encerrou" : "\(p.persona?.nome ?? p.apelido) fechou (só ficou o shell)"
        for i in caixa.indices where caixa[i].para == id && caixa[i].estado == .naFila {
          caixa[i].estado = .cancelada; caixa[i].motivo = motivo; mudou = true
          if caixa[i].esperaResposta { avisarRemetente(caixa[i], motivo) }
        }
        continue
      }
      guard livreParaReceber(p) else { continue }
      // Respostas voltam juntas: enquanto este agente ainda espera outras respostas do que ele
      // passou adiante, as que já chegaram aguardam (até 15 min) para entrar numa entrega só.
      let pendentes = caixa.contains { $0.de == id && $0.esperaResposta && ($0.estado == .entregue || $0.estado == .naFila) }
      let idxs = caixa.indices.filter { i in
        guard caixa[i].para == id && caixa[i].estado == .naFila else { return false }
        if caixa[i].respostaA != nil && pendentes && Date().timeIntervalSince(caixa[i].criada) < 900 { return false }
        return true
      }
      guard !idxs.isEmpty else { continue }
      entregar(idxs.map { caixa[$0] }, para: p)
      for i in idxs { caixa[i].estado = .entregue; caixa[i].entregueEm = Date() }
      mudou = true
    }
    // 2) Parou sem responder: trabalhou depois da entrega e está parado há um tempo.
    let agora = Date()
    for i in caixa.indices where caixa[i].estado == .entregue && caixa[i].esperaResposta {
      guard let quando = caixa[i].entregueEm, agora.timeIntervalSince(quando) > 10 else { continue }
      guard let p = acharPainel(caixa[i].para) else {
        caixa[i].estado = .semResposta; caixa[i].motivo = "o destinatário foi fechado"; mudou = true
        avisarRemetente(caixa[i], "\(caixa[i].paraNome) foi fechado antes de responder")
        continue
      }
      if p.hibernado { continue }       // hibernou parado: a resposta, se vier, vem quando acordar
      let trabalhou = p.inicioAtividade > quando || !p.vivo
      let parado = !p.ocupado && agora.timeIntervalSince(p.leitor.ultimaSaida) > 8 && p.permissao == nil   // pedindo permissão ainda está no meio
      guard trabalhou && parado else { continue }
      caixa[i].estado = .semResposta
      mudou = true
      if let de = caixa[i].de, let remetente = acharPainel(de), remetente.vivo {
        let bloco = Compose.contexto(de: p, apelido: p.apelido, loja: self, linhas: 120, sempreArquivo: true)
        let aviso = Mensagem(de: p.id, deNome: "@" + p.apelido, para: remetente.id, paraNome: "@" + remetente.apelido,
                             texto: "@\(p.apelido) parou sem usar `orion responder` (pode ter terminado ou estar esperando o usuário). Última resposta dele:\n\(bloco)",
                             respostaA: caixa[i].id, esperaResposta: false)
        caixa.append(aviso)
      }
    }
    if mudou { gravarCaixa() }
  }

  /// Cola as mensagens no terminal do destinatário, com a moldura que diz de quem são e como responder.
  private func entregar(_ ms: [Mensagem], para p: Painel) {
    func moldura(_ m: Mensagem) -> String {
      var cab: String
      if let r = m.respostaA { cab = "[Resposta de \(m.deNome) à mensagem \(r) · id \(m.id)]" }
      else if m.doTime { cab = "[Mensagem de \(m.deNome) para o time — o Orion escolheu você · id \(m.id)]" }
      else { cab = "[Mensagem de \(m.deNome) · id \(m.id)]" }
      var corpo = cab + "\n" + m.texto
      if m.doTime {
        corpo += "\n— Se não for com você (ou não tiver nada a acrescentar), rode só: orion passar \(m.id) \"motivo\" — vai para o próximo do time."
      }
      if m.esperaResposta {
        corpo += "\n— Quando terminar, responda com: orion responder \(m.id) \"Status: … | Resultado: … | Evidência: …\" e encerre o turno (não espere)."
      }
      return corpo
    }
    let texto = ms.count == 1 ? moldura(ms[0])
      : "[\(ms.count) mensagens novas na sua caixa — leia todas antes de agir]\n\n" + ms.map(moldura).joined(separator: "\n\n")
    var anexos: [Anexo] = []
    for c in ms.flatMap(\.anexos) where FileManager.default.fileExists(atPath: c) {
      anexos.append(Anexo(tipo: Compose.ehImagem(c) ? .imagem : .arquivo, valor: c, rotulo: (c as NSString).lastPathComponent))
    }
    let quem = Set(ms.map(\.deNome)).sorted().joined(separator: ", ")
    enviarComposto(de: p, texto: texto, anexos: anexos, lembrar: false, remetente: quem)
  }
}
