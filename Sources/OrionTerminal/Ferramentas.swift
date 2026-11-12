import Foundation

/// Ferramenta de agente que o app sabe abrir, com multiconta: Claude Code, Codex e Gemini CLI.
/// Tudo o que muda de uma para outra mora aqui (nome, variável de ambiente do perfil, como
/// retomar uma conversa), para o resto do código não precisar de `if claude … else codex`.
struct Ferramenta: Identifiable, Equatable {
  let id: String              // também é o nome do processo: claude | codex | gemini
  let nome: String            // "Claude"
  let nomeLongo: String       // "Claude Code"
  /// Variável que aponta para a pasta do perfil (uma conta = uma pasta).
  let variavel: String
  let cor: String
  let simbolo: String         // SF Symbol quando não há app instalado para emprestar o ícone
  let atalho: String
  /// Pasta de configuração dentro da pasta pessoal (a conta "Principal").
  let pastaPadrao: String
  /// O que é compartilhado com a conta principal (link simbólico): ajustes, skills, plugins…
  let compartilhados: [String]

  static let claude = Ferramenta(id: "claude", nome: "Claude", nomeLongo: "Claude Code", variavel: "CLAUDE_CONFIG_DIR", cor: "#d97757",
                                 simbolo: "sparkle", atalho: "⇧⌘T", pastaPadrao: ".claude",
                                 compartilhados: ["settings.json", "CLAUDE.md", "skills", "plugins", "commands", "agents",
                                                  "statusline.sh", "keybindings.json", "output-styles", "hooks"])
  static let codex = Ferramenta(id: "codex", nome: "Codex", nomeLongo: "Codex", variavel: "CODEX_HOME", cor: "#10a37f",
                                simbolo: "chevron.left.forwardslash.chevron.right", atalho: "⇧⌘X", pastaPadrao: ".codex",
                                compartilhados: ["config.toml", "AGENTS.md", "skills", "prompts", "rules"])
  /// Gemini CLI: `GEMINI_CLI_HOME` troca a pasta pessoal que ele usa; a configuração fica em
  /// `<pasta>/.gemini` (packages/core/src/utils/paths.ts do gemini-cli).
  static let gemini = Ferramenta(id: "gemini", nome: "Gemini", nomeLongo: "Gemini CLI", variavel: "GEMINI_CLI_HOME", cor: "#4c8df6",
                                 simbolo: "diamond.fill", atalho: "⌥⌘G", pastaPadrao: ".gemini",
                                 compartilhados: ["settings.json", "GEMINI.md", "commands", "extensions"])

  static let todas = [claude, codex, gemini]
  static let ids = todas.map(\.id)
  static func de(_ id: String?) -> Ferramenta? { todas.first { $0.id == id } }
  static func eh(_ processo: String) -> Bool { ids.contains(processo) }

  var contaPrincipal: String { id + "-padrao" }

  /// Comando para retomar: a sessão exata se o id for conhecido, senão a última daquela pasta.
  func retomar(_ base: String, sessao: String?) -> String {
    switch id {
    case "claude": return sessao.map { "\(base) --resume \($0)" } ?? "\(base) --continue"
    case "codex": return sessao.map { "\(base) resume \($0)" } ?? "\(base) resume --last"
    default: return base
    }
  }
}

func nomeFerramenta(_ tipo: String) -> String { Ferramenta.de(tipo)?.nome ?? "Terminal" }
func nomeLongoFerramenta(_ tipo: String) -> String { Ferramenta.de(tipo)?.nomeLongo ?? "Terminal" }

/// O personagem de um agente: quem ele é na equipe. Nome e avatar próprios, uma cor e um papel
/// (o que ele faz). A ferramenta e a conta continuam sendo do painel.
struct Persona: Equatable {
  var nome: String
  var avatar: String      // forma do mascote (Mascote.formas)
  var cor: String
  var papel: String       // "Maestro", "Dev", "Revisor"… (vazio = sem papel definido)
  /// O que este agente faz e quando mandar trabalho para ele (os colegas leem em `orion equipe`).
  var descricao = ""

  var dicionario: [String: Any] {
    var d: [String: Any] = ["nome": nome, "avatar": avatar, "cor": cor, "papel": papel]
    if !descricao.isEmpty { d["descricao"] = descricao }
    return d
  }

  init(nome: String, avatar: String, cor: String, papel: String = "", descricao: String = "") {
    self.nome = nome; self.avatar = avatar; self.cor = cor; self.papel = papel; self.descricao = descricao
  }

  init?(_ d: [String: Any]?) {
    guard let d, let n = d["nome"] as? String, !n.isEmpty else { return nil }
    nome = n
    avatar = d["avatar"] as? String ?? ""
    cor = d["cor"] as? String ?? "#7aa2ff"
    papel = d["papel"] as? String ?? ""
    descricao = d["descricao"] as? String ?? ""
  }

  /// Elenco: estrelas e constelações (a família é Orion), cada uma com a sua forma e a sua cor.
  static let elenco: [Persona] = [
    Persona(nome: "Rigel", avatar: "gota", cor: "#ff9e66"), Persona(nome: "Vega", avatar: "bolha", cor: "#7aa2ff"),
    Persona(nome: "Lyra", avatar: "nuvem", cor: "#ff79c6"), Persona(nome: "Sirius", avatar: "pilula", cor: "#9aa7ff"),
    Persona(nome: "Nova", avatar: "hexa", cor: "#b79cff"), Persona(nome: "Atlas", avatar: "flor", cor: "#c9a27a"),
    Persona(nome: "Luna", avatar: "fantasma", cor: "#c8cbe6"), Persona(nome: "Altair", avatar: "losango", cor: "#f5d76e"),
    Persona(nome: "Cosmo", avatar: "gota", cor: "#9ee37d"), Persona(nome: "Astra", avatar: "bolha", cor: "#ff9ecb"),
    Persona(nome: "Polaris", avatar: "nuvem", cor: "#6fd6d6"), Persona(nome: "Mira", avatar: "pilula", cor: "#7ad7ff"),
    Persona(nome: "Castor", avatar: "hexa", cor: "#d9a066"), Persona(nome: "Pólux", avatar: "flor", cor: "#ffb454"),
    Persona(nome: "Antares", avatar: "fantasma", cor: "#ff6b6b"), Persona(nome: "Bella", avatar: "losango", cor: "#f0c94a"),
    Persona(nome: "Deneb", avatar: "gota", cor: "#b8c4ff"), Persona(nome: "Electra", avatar: "bolha", cor: "#7be0a0"),
    Persona(nome: "Hadar", avatar: "nuvem", cor: "#f2b05e"), Persona(nome: "Izar", avatar: "pilula", cor: "#5fb8ff"),
    Persona(nome: "Kuma", avatar: "hexa", cor: "#aab4c4"), Persona(nome: "Maia", avatar: "flor", cor: "#ff8fb0"),
    Persona(nome: "Naos", avatar: "fantasma", cor: "#7fd18b"), Persona(nome: "Talita", avatar: "losango", cor: "#c7a58a"),
  ]
  static var avatares: [String] { Mascote.formas }
  static let papeis = ["Maestro", "Dev", "Revisor", "Testes", "Pesquisa", "Design", "Conteúdo", "Dados", "Infra"]

  /// Próximo personagem livre (os nomes em uso ficam para depois; acabando, repete com número).
  static func proximo(emUso: [String]) -> Persona {
    if let livre = elenco.first(where: { !emUso.contains($0.nome) }) { return livre }
    var p = elenco[emUso.count % elenco.count]
    var n = 2
    while emUso.contains("\(p.nome) \(n)") { n += 1 }
    p.nome = "\(p.nome) \(n)"
    return p
  }
}

enum Nomes {
  /// Tarefa em poucas palavras, a partir da primeira mensagem: uma linha, sem cortesia nem
  /// pontuação sobrando, cortada numa palavra inteira.
  static func tarefaCurta(_ mensagem: String, limite: Int = 46) -> String? {
    var linha = mensagem.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty && !$0.hasPrefix("<") && !$0.hasPrefix("[") } ?? ""
    for prefixo in ["por favor, ", "por favor ", "olá, ", "oi, ", "please ", "você pode ", "voce pode ", "pode ", "preciso que você ", "quero que você "] {
      if linha.lowercased().hasPrefix(prefixo) { linha = String(linha.dropFirst(prefixo.count)) }
    }
    linha = linha.replacingOccurrences(of: #"@"?([^\s"]+)"?"#, with: "$1", options: .regularExpression)
    linha = linha.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?—-"))
    guard linha.count >= 3 else { return nil }
    if linha.count > limite {
      let corte = linha.prefix(limite)
      linha = (corte.lastIndex(of: " ").map { String(corte[..<$0]) } ?? String(corte)).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—-")) + "…"
    }
    return linha.prefix(1).uppercased() + linha.dropFirst()
  }

  /// Título que o programa manda por OSC, sem enfeite e sem os nomes genéricos.
  static func tituloUtil(_ osc: String, cwd: String) -> String? {
    let t = String(osc.drop(while: { "✳✻✶✢·*◐◓◑◒ ".contains($0) || ($0.unicodeScalars.first.map { (0x2800...0x28FF).contains($0.value) } ?? false) }))
      .trimmingCharacters(in: .whitespaces)
    let generico = ["", "claude", "claude code", "codex", "gemini", "gemini cli", "zsh", "bash", "-zsh", "node", (cwd as NSString).lastPathComponent.lowercased()]
    if generico.contains(t.lowercased()) || t.hasPrefix("/") || t.hasPrefix("~") { return nil }
    return t
  }
}

/// Sessões das ferramentas no disco: descobre o id da conversa de um agente olhando só nomes e
/// datas de arquivo (nunca o conteúdo), para reabrir exatamente aquela conversa depois.
enum Sessoes {
  /// Pasta em que o Claude Code guarda as conversas de um projeto: o caminho com tudo o que não
  /// é letra ou número trocado por "-".
  static func pastaDoClaude(config: String?, cwd: String) -> URL {
    let base = config ?? (NSHomeDirectory() + "/.claude")
    let slug = String(cwd.map { $0.isLetter && $0.isASCII || $0.isNumber ? $0 : "-" })
    return URL(fileURLWithPath: base).appendingPathComponent("projects").appendingPathComponent(slug)
  }

  /// Id da sessão mais provável: o arquivo mexido mais perto de `atividade` (a última saída do
  /// painel), criado depois que o agente abriu.
  static func descobrir(tipo: String, config: String?, cwd: String, desde: Date, atividade: Date, excluir: Set<String> = []) -> String? {
    let fm = FileManager.default
    var candidatos: [(String, Date)] = []
    func olhar(_ u: URL, id: (String) -> String?) {
      guard u.pathExtension == "jsonl", let v = try? u.resourceValues(forKeys: [.contentModificationDateKey]),
            let m = v.contentModificationDate, m >= desde.addingTimeInterval(-5), let i = id(u.deletingPathExtension().lastPathComponent),
            !excluir.contains(i) else { return }
      candidatos.append((i, m))
    }
    switch tipo {
    case "claude":
      let dir = pastaDoClaude(config: config, cwd: cwd)
      for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
        olhar(u) { $0.count == 36 ? $0 : nil }
      }
    case "codex":
      let raiz = URL(fileURLWithPath: (config ?? NSHomeDirectory() + "/.codex") + "/sessions")
      // Só os dias recentes: sessions/AAAA/MM/DD/rollout-…-<uuid>.jsonl
      let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"
      for dia in Set([desde, atividade, Date()].map { f.string(from: $0) }) {
        for u in (try? fm.contentsOfDirectory(at: raiz.appendingPathComponent(dia), includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
          olhar(u) { $0.count > 36 ? String($0.suffix(36)) : nil }
        }
      }
    default: return nil
    }
    return candidatos.min { abs($0.1.timeIntervalSince(atividade)) < abs($1.1.timeIntervalSince(atividade)) }?.0
  }
}

/// Um agente fechado há pouco, com o que é preciso para trazê-lo de volta.
struct Fechado: Identifiable, Equatable {
  let id: String              // id do painel que foi fechado
  let tipo: String
  let pasta: String
  let workspace: String
  let workspaceNome: String
  let conta: String
  let titulo: String
  let persona: Persona?
  let tarefa: String?
  let pai: String?
  let sessao: String?
  let em: Date

  var dicionario: [String: Any] {
    var d: [String: Any] = ["id": id, "tipo": tipo, "pasta": pasta, "workspace": workspace, "workspaceNome": workspaceNome,
                            "conta": conta, "titulo": titulo, "em": em.timeIntervalSince1970]
    if let p = persona { d["persona"] = p.dicionario }
    if let t = tarefa { d["tarefa"] = t }
    if let p = pai { d["pai"] = p }
    if let s = sessao { d["sessao"] = s }
    return d
  }

  init(id: String, tipo: String, pasta: String, workspace: String, workspaceNome: String, conta: String, titulo: String,
       persona: Persona?, tarefa: String?, pai: String?, sessao: String?, em: Date = Date()) {
    self.id = id; self.tipo = tipo; self.pasta = pasta; self.workspace = workspace; self.workspaceNome = workspaceNome
    self.conta = conta; self.titulo = titulo; self.persona = persona; self.tarefa = tarefa; self.pai = pai; self.sessao = sessao; self.em = em
  }

  init?(_ d: [String: Any]) {
    guard let i = d["id"] as? String, let t = d["tipo"] as? String, Ferramenta.eh(t) else { return nil }
    id = i; tipo = t
    pasta = d["pasta"] as? String ?? NSHomeDirectory()
    workspace = d["workspace"] as? String ?? ""
    workspaceNome = d["workspaceNome"] as? String ?? ""
    conta = d["conta"] as? String ?? ""
    titulo = d["titulo"] as? String ?? nomeLongoFerramenta(t)
    persona = Persona(d["persona"] as? [String: Any])
    tarefa = d["tarefa"] as? String
    pai = d["pai"] as? String
    sessao = d["sessao"] as? String
    em = Date(timeIntervalSince1970: d["em"] as? Double ?? 0)
  }
}
