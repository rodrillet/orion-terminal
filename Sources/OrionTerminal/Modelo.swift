import Foundation
import Observation

/// Nó da árvore de uma aba: folha = painel (terminal), interno = divisão em dois.
final class No {
  enum Tipo: String { case painel, divisao }
  var tipo: Tipo
  // painel
  var id: String
  var cwd: String
  var kind: String          // shell | claude | codex
  var zoom: Double
  var ultimoProcesso: String
  var comando: String?      // roda na primeira abertura (não é salvo)
  var marca: String?        // quadro de agentes: "revisar" | "concluido" (marcado à mão)
  // agente: quem ele é e de quem ele é filho
  var persona: Persona?     // personagem (nome, avatar, cor, papel)
  var pai: String?          // id do painel do maestro que o criou (subagente)
  var maestro = false       // marcado como maestro (coordena outros agentes)
  var tarefa: String?       // a tarefa em poucas palavras (da primeira mensagem)
  var sessao: String?       // id da conversa na ferramenta (para retomar exatamente ela)
  var retorno = false       // ao parar, entrega o resultado ao pai
  // divisão
  var horizontal: Bool      // true = lado a lado
  var proporcao: Double
  var a: No?
  var b: No?

  init(painel id: String, cwd: String, kind: String, comando: String? = nil, zoom: Double = 0) {
    tipo = .painel; self.id = id; self.cwd = cwd; self.kind = kind; self.comando = comando; self.zoom = zoom
    ultimoProcesso = ""; horizontal = true; proporcao = 0.5
  }

  init(divisao horizontal: Bool, a: No, b: No, proporcao: Double = 0.5) {
    tipo = .divisao; id = UUID().uuidString; cwd = ""; kind = "shell"; zoom = 0; ultimoProcesso = ""
    self.horizontal = horizontal; self.a = a; self.b = b; self.proporcao = proporcao
  }

  var folhas: [No] { tipo == .painel ? [self] : (a?.folhas ?? []) + (b?.folhas ?? []) }

  func folha(_ id: String) -> No? { folhas.first { $0.id == id } }

  func pai(de alvo: No) -> No? {
    guard tipo == .divisao else { return nil }
    if a === alvo || b === alvo { return self }
    return a?.pai(de: alvo) ?? b?.pai(de: alvo)
  }

  @MainActor func dicionario(painel: (String) -> Painel?) -> [String: Any] {
    if tipo == .painel {
      // Painel ainda não aberto nesta sessão (dormindo): vale o que estava salvo, senão um
      // agente restaurado e nunca visitado voltaria como terminal comum na próxima abertura.
      let p = painel(id).flatMap { $0.iniciado ? $0 : nil }
      var d: [String: Any] = ["tipo": "painel", "id": id, "cwd": p?.cwd ?? cwd, "kind": kind, "zoom": p?.zoom ?? zoom,
                              "ultimoProcesso": p.map { $0.ocioso ? "" : $0.processo } ?? ultimoProcesso]
      if let marca { d["marca"] = marca }
      if let persona { d["persona"] = persona.dicionario }
      if let pai { d["pai"] = pai }
      if maestro { d["maestro"] = true }
      if let tarefa { d["tarefa"] = tarefa }
      if let sessao { d["sessao"] = sessao }
      if retorno { d["retorno"] = true }
      return d
    }
    return ["tipo": "divisao", "horizontal": horizontal, "proporcao": proporcao,
            "a": a?.dicionario(painel: painel) ?? [:], "b": b?.dicionario(painel: painel) ?? [:]]
  }

  static func de(_ d: [String: Any]) -> No? {
    if d["tipo"] as? String == "divisao" {
      guard let a = (d["a"] as? [String: Any]).flatMap(de), let b = (d["b"] as? [String: Any]).flatMap(de) else { return nil }
      return No(divisao: d["horizontal"] as? Bool ?? true, a: a, b: b, proporcao: d["proporcao"] as? Double ?? 0.5)
    }
    guard let id = d["id"] as? String else { return nil }
    let n = No(painel: id, cwd: d["cwd"] as? String ?? NSHomeDirectory(), kind: d["kind"] as? String ?? "shell",
               zoom: d["zoom"] as? Double ?? 0)
    n.ultimoProcesso = d["ultimoProcesso"] as? String ?? ""
    if let m = d["marca"] as? String, ["revisar", "concluido"].contains(m) { n.marca = m }
    n.persona = Persona(d["persona"] as? [String: Any])
    n.pai = d["pai"] as? String
    n.maestro = d["maestro"] as? Bool ?? false
    n.tarefa = d["tarefa"] as? String
    n.sessao = d["sessao"] as? String
    n.retorno = d["retorno"] as? Bool ?? false
    return n
  }
}

/// Um workspace é um projeto (cliente, repositório, assunto): tem pasta raiz, cor, símbolo e as
/// suas próprias abas — terminais e agentes. Trocar de workspace troca tudo o que está na tela.
@Observable final class Workspace: Identifiable {
  let id: String
  var nome: String
  var cor: String
  var simbolo: String
  var pasta: String
  var abaAtiva: String?     // última aba vista neste workspace

  init(id: String = "w-" + UUID().uuidString.prefix(8).lowercased(), nome: String, cor: String,
       simbolo: String = "folder", pasta: String = NSHomeDirectory()) {
    self.id = id; self.nome = nome; self.cor = cor; self.simbolo = simbolo; self.pasta = pasta
  }

  static let simbolos = ["house", "folder", "briefcase", "building.2", "megaphone", "chart.bar", "cart", "globe",
                         "paintbrush", "hammer", "server.rack", "bolt", "sparkles", "book", "camera", "person.2",
                         "heart", "leaf", "gamecontroller", "graduationcap", "cross.case", "fuelpump", "gift", "star"]
}

@Observable final class Aba: Identifiable {
  let id: String
  var workspace: String
  var titulo: String?
  var kind: String
  var cor: String?
  /// Conta de cada ferramenta nesta aba (ferramenta → id da conta).
  var contas: [String: String]
  @ObservationIgnored var arvore: No
  var painelAtivo: String
  var maximizado: String?
  var atencao = false
  var versaoArvore = 0      // muda quando a árvore muda (a interface observa)

  init(id: String = "a-" + UUID().uuidString.prefix(8).lowercased(), workspace: String, kind: String, arvore: No,
       contas: [String: String]) {
    self.id = id; self.workspace = workspace; self.kind = kind; self.arvore = arvore
    self.painelAtivo = arvore.folhas.first?.id ?? ""
    self.contas = contas
  }

  func conta(_ tipo: String) -> String { contas[tipo] ?? tipo + "-padrao" }
  func definirConta(_ tipo: String, _ id: String) { contas[tipo] = id }
}

/// Estado de um painel, do ponto de vista de quem orquestra.
enum EstadoPainel: String {
  case dormindo      // restaurado, ainda não abriu o shell
  case trabalhando   // agente produzindo saída
  case esperando     // agente parado, aguardando você
  case rodando       // um programa comum em primeiro plano
  case pronto        // shell no prompt
  case saiu          // processo encerrado

  var rotulo: String {
    switch self {
    case .dormindo: return "Dormindo"
    case .trabalhando: return "Trabalhando"
    case .esperando: return "Esperando você"
    case .rodando: return "Rodando"
    case .pronto: return "Pronto"
    case .saiu: return "Saiu"
    }
  }
}

struct Conta: Identifiable, Hashable {
  let id: String
  let tipo: String
  var nome: String
  var cor: String
  let dir: String?
  var email: String = ""
  var plano: String = ""
  var logado = false
  var padraoDoSistema: Bool { id.hasSuffix("-padrao") }

  init(_ d: [String: Any]) {
    id = d["id"] as? String ?? ""
    tipo = d["tipo"] as? String ?? "claude"
    nome = d["nome"] as? String ?? ""
    // A conta da instalação normal (~/.claude, ~/.codex) chamava "Padrão", o que confundia com
    // "conta padrão para novos agentes". Agora aparece como "Principal".
    if id.hasSuffix("-padrao") && nome == "Padrão" { nome = "Principal" }
    cor = d["cor"] as? String ?? "#a0a0aa"
    dir = d["dir"] as? String
    if let i = d["info"] as? [String: Any] {
      email = i["email"] as? String ?? ""
      plano = i["plano"] as? String ?? ""
      logado = i["logado"] as? Bool ?? false
    }
  }
}

/// Uso de uma conta: janelas de 5 horas e de 7 dias (% usado e quando zera).
struct Uso: Equatable {
  struct Janela: Equatable {
    var pct: Double
    var reinicia: Date?
    /// O dado pode ser antigo (Codex: última sessão). Se a janela já zerou, o uso é 0.
    var pctAtual: Double { if let r = reinicia, r < Date() { return 0 }; return pct }
    var zerou: Bool { if let r = reinicia, r < Date() { return true }; return false }
  }
  var h5: Janela?
  var d7: Janela?
  var erro: String?
  var em: Date?          // quando foi lido

  /// A janela que mais importa para um resumo (anel, "5h 42%"): a de 5 h; sem ela, a de 7 dias.
  var resumo: (rotulo: String, pct: Double)? {
    if let h = h5 { return ("5h", h.pctAtual) }
    if let d = d7 { return ("7d", d.pctAtual) }
    return nil
  }

  private static let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
  }()
  private static let isoSimples = ISO8601DateFormatter()
  private static func data(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) ?? isoSimples.date(from: $0) } }

  init(_ d: [String: Any]) {
    erro = d["erro"] as? String
    func janela(_ k: String) -> Janela? {
      guard let w = d[k] as? [String: Any], let p = (w["pct"] as? Double) ?? (w["pct"] as? Int).map(Double.init) else { return nil }
      return Janela(pct: p, reinicia: Uso.data(w["reinicia"] as? String))
    }
    h5 = janela("h5"); d7 = janela("d7")
    em = Uso.data(d["em"] as? String)
  }

  /// Forma gravável (cache em disco e CLI).
  var dicionario: [String: Any] {
    var d: [String: Any] = [:]
    func j(_ w: Janela?) -> [String: Any]? {
      guard let w else { return nil }
      var x: [String: Any] = ["pct": w.pct]
      if let r = w.reinicia { x["reinicia"] = Uso.isoSimples.string(from: r) }
      return x
    }
    if let x = j(h5) { d["h5"] = x }
    if let x = j(d7) { d["d7"] = x }
    if let e = erro { d["erro"] = e }
    if let em { d["em"] = Uso.isoSimples.string(from: em) }
    return d
  }
}

/// Cartão do Claude/Codex: de que ferramenta, e onde está o elemento que o abriu.
/// O hover mostra o resumo; o clique abre o painel expandido (contas, uso, agentes, novo).
struct UsoHover: Equatable {
  var tipo: String
  var ancora: CGRect      // em coordenadas da janela, origem em cima à esquerda
  var fixo = false        // aberto por clique, CLI ou atalho: só fecha quando mandarem
  var expandido = false   // painel completo (senão, só o resumo)
}

struct Notificacao: Identifiable {
  let id = UUID()
  let titulo: String
  let corpo: String
  let aba: String
  let processo: String
  let em = Date()
}
