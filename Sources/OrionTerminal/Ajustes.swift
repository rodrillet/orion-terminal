import Foundation

/// Preferências do app. Qualquer campo ausente no arquivo volta ao padrão; campos de versões
/// antigas (`tema`, `aurora`, `usoNaDoca`) são lidos e convertidos, nunca quebram a leitura.
struct Ajustes: Codable, Equatable {
  // Aparência
  var aparencia = "escuro"           // escuro | claro | sistema
  var temaEscuro = "orion"
  var temaClaro = "orion-claro"
  var fonte = "JetBrainsMono Nerd Font"
  var tamanho: Double = 13           // fonte do terminal
  var escalaUI: Double = 1.0         // fonte da interface (1 = padrão), separada da do terminal
  var raio: Double = 14              // arredondamento dos cartões
  var sombras = true                 // profundidade: sombra nos painéis
  var opacidade: Double = 0.78       // fundo da janela
  var desfoque = true
  var vidroPuro = false              // só o desfoque do macOS, sem a cor do tema por cima
  var cursor = "barra"               // barra | bloco | sublinhado
  var gpu = true                     // renderização Metal
  var margem: Double = 10
  // Terminal
  var shell = ""
  var novaAbaNaPastaAtual = true
  var rolagem = 5000
  var optionMeta = true
  var copiarAoSelecionar = false
  var comandoClaude = "claude"
  var comandoCodex = "codex"
  var comandoGemini = "gemini"
  // Abas
  var restaurar = true
  var retomarAgentes = true
  var confirmarFechar = true
  var barraLateral = true
  var larguraLateral: Double = 248
  // Compose (caixa de escrita do painel)
  var compose = "agentes"            // agentes | sempre | manual
  // Autocomplete
  var sugestoes = true
  var sugestoesAuto = true
  // Notificações
  var avisarAgentes = true
  var avisarComandos = true
  var comandoLongo: Double = 20
  // Contas
  var contaClaude = "claude-padrao"
  var contaCodex = "codex-padrao"
  var contaGemini = "gemini-padrao"
  var usoClaude = "perguntar"        // perguntar | ligado | desligado (o do Codex é local, sempre ligado)
  var usoIntervalo: Double = 5       // minutos entre atualizações em segundo plano
  var cliqueFerramenta = "painel"    // clique no botão do Claude/Codex: painel (expande) | novo (abre um agente)
  var doca = true
  var barraAgentes = true
  var atualizacao = "automatica"     // automatica | avisar | desligada
  var memoria = true                 // mostra o uso de memória (app e agentes)
  var portas = true                  // mostra os servidores (portas em escuta) dos painéis
  var ferramentasOcultas: [String] = []   // ferramentas que não aparecem na interface (ex.: ["gemini"])
  var desfoqueRaio: Double = 10      // desfoque do que está atrás da janela (0 = nenhum, vê-se nítido)

  init() {}

  /// Chaves que só existem em arquivos de versões anteriores.
  private enum Legado: String, CodingKey { case tema, usoNaDoca }

  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: CodingKeys.self)
    let antigo = try? d.container(keyedBy: Legado.self)
    let p = Ajustes()
    func v<T: Decodable>(_ k: CodingKeys, _ padrao: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil ?? padrao }
    // v0.3 tinha um tema só (sempre escuro), em `tema`.
    let temaAntigo = (try? antigo?.decodeIfPresent(String.self, forKey: .tema)) ?? nil
    aparencia = v(.aparencia, p.aparencia)
    if !["escuro", "claro", "sistema"].contains(aparencia) { aparencia = "escuro" }
    temaEscuro = v(.temaEscuro, temaAntigo ?? p.temaEscuro); temaClaro = v(.temaClaro, p.temaClaro)
    fonte = v(.fonte, p.fonte); tamanho = v(.tamanho, p.tamanho)
    escalaUI = min(1.4, max(0.85, v(.escalaUI, p.escalaUI))); raio = min(22, max(4, v(.raio, p.raio))); sombras = v(.sombras, p.sombras)
    opacidade = v(.opacidade, p.opacidade); desfoque = v(.desfoque, p.desfoque); vidroPuro = v(.vidroPuro, p.vidroPuro)
    cursor = v(.cursor, p.cursor); gpu = v(.gpu, p.gpu); margem = v(.margem, p.margem)
    shell = v(.shell, p.shell); novaAbaNaPastaAtual = v(.novaAbaNaPastaAtual, p.novaAbaNaPastaAtual)
    rolagem = v(.rolagem, p.rolagem); optionMeta = v(.optionMeta, p.optionMeta)
    copiarAoSelecionar = v(.copiarAoSelecionar, p.copiarAoSelecionar)
    comandoClaude = v(.comandoClaude, p.comandoClaude); comandoCodex = v(.comandoCodex, p.comandoCodex)
    comandoGemini = v(.comandoGemini, p.comandoGemini); contaGemini = v(.contaGemini, p.contaGemini)
    restaurar = v(.restaurar, p.restaurar); retomarAgentes = v(.retomarAgentes, p.retomarAgentes)
    confirmarFechar = v(.confirmarFechar, p.confirmarFechar); barraLateral = v(.barraLateral, p.barraLateral)
    larguraLateral = v(.larguraLateral, p.larguraLateral)
    compose = v(.compose, p.compose)
    if !["agentes", "sempre", "manual"].contains(compose) { compose = "agentes" }
    sugestoes = v(.sugestoes, p.sugestoes); sugestoesAuto = v(.sugestoesAuto, p.sugestoesAuto)
    avisarAgentes = v(.avisarAgentes, p.avisarAgentes); avisarComandos = v(.avisarComandos, p.avisarComandos)
    comandoLongo = v(.comandoLongo, p.comandoLongo)
    contaClaude = v(.contaClaude, p.contaClaude); contaCodex = v(.contaCodex, p.contaCodex)
    // v0.2 guardava "uso na doca" (sim/não); virou `usoClaude`.
    let usoNaDoca = ((try? antigo?.decodeIfPresent(Bool.self, forKey: .usoNaDoca)) ?? nil) ?? false
    usoClaude = v(.usoClaude, usoNaDoca ? "ligado" : p.usoClaude)
    usoIntervalo = v(.usoIntervalo, p.usoIntervalo)
    cliqueFerramenta = v(.cliqueFerramenta, p.cliqueFerramenta)
    doca = v(.doca, p.doca); barraAgentes = v(.barraAgentes, p.barraAgentes); atualizacao = v(.atualizacao, p.atualizacao); memoria = v(.memoria, p.memoria)
    portas = v(.portas, p.portas)
    ferramentasOcultas = v(.ferramentasOcultas, p.ferramentasOcultas).filter { Ferramenta.eh($0) }
    // v0.4 tinha desfoque ligado/desligado (forte demais para ver o fundo) e "vidro puro" (sem cor).
    // v0.5: um controle só — quanto de cor (opacidade) e quanto de desfoque.
    desfoqueRaio = min(40, max(0, v(.desfoqueRaio, desfoque ? p.desfoqueRaio : 0)))
    if vidroPuro { opacidade = min(opacidade, 0.35); vidroPuro = false }
    desfoque = desfoqueRaio > 0
    opacidade = min(1, max(0.1, opacidade))
    // Nomes antigos do cursor (em inglês) que ficaram em arquivos de versões anteriores.
    cursor = ["bar": "barra", "block": "bloco", "underline": "sublinhado"][cursor] ?? cursor
  }

  /// Conta padrão (a dos próximos agentes) de uma ferramenta.
  func contaPadrao(_ tipo: String) -> String {
    switch tipo { case "claude": return contaClaude; case "codex": return contaCodex; default: return contaGemini }
  }
  mutating func definirContaPadrao(_ tipo: String, _ id: String) {
    switch tipo { case "claude": contaClaude = id; case "codex": contaCodex = id; default: contaGemini = id }
  }
  var contasPadrao: [String: String] { ["claude": contaClaude, "codex": contaCodex, "gemini": contaGemini] }
  /// Comando que abre a ferramenta (o nome dela, se o campo estiver vazio).
  func comando(_ tipo: String) -> String? {
    guard Ferramenta.eh(tipo) else { return nil }
    let c: String
    switch tipo { case "claude": c = comandoClaude; case "codex": c = comandoCodex; default: c = comandoGemini }
    return c.isEmpty ? tipo : c
  }

  static func carregar() -> Ajustes {
    guard let d = try? Data(contentsOf: Armazem.pasta.appendingPathComponent("ajustes.json")),
          let a = try? JSONDecoder().decode(Ajustes.self, from: d) else { return Ajustes() }
    return a
  }

  func salvar() {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let d = try? e.encode(self) { try? d.write(to: Armazem.pasta.appendingPathComponent("ajustes.json"), options: .atomic) }
  }
}
