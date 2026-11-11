import Cocoa
import SwiftUI
import Observation
import UserNotifications

/// Estado central do app: workspaces, abas, painéis, contas, notificações e ajustes.
@MainActor @Observable
final class Loja {
  var ajustes: Ajustes { didSet { if ajustes != oldValue { ajustesMudaram(oldValue) } } }
  var workspaces: [Workspace] = []
  var workspaceAtivoID: String?
  var abas: [Aba] = []
  var abaAtivaID: String?
  var contas: [Conta] = []
  var usos: [String: Uso] = [:]
  var usoCarregando: Set<String> = []
  var usoHover: UsoHover?
  var notificacoes: [Notificacao] = []
  var naoLidas = 0
  var janelaFocada = true
  var paletaAberta = false
  var telaCheia = false
  var filtro = ""
  /// Largura da barra lateral enquanto a alça é arrastada (só vai para os ajustes ao soltar).
  var larguraArrasto: Double?
  /// Diálogo do app aberto (confirmar, renomear, novo workspace…). Veja Dialogos.swift.
  var dialogo: Dialogo?
  /// O macOS está em modo escuro (para a aparência "igual ao sistema").
  var escuroDoSistema = true
  /// Memória do app e a soma dos painéis (bytes), amostradas a cada poucos segundos.
  var memoriaApp: UInt64 = 0
  var memoriaPaineis: UInt64 = 0
  /// Muda quando a lista de temas do usuário muda (o editor observa).
  var versaoTemas = 0
  /// Tema aberto no editor (Ajustes → Aparência).
  var temaEmEdicao: String?
  /// Agentes fechados há pouco (para reabrir com a mesma conversa).
  var fechados: [Fechado] = []
  /// Portas TCP em escuta (servidores), com o painel de cada uma quando é deste app.
  var portas: [Porta] = []
  var portasLendo = false
  /// Muda quando alguém pede a lista de portas (atalho, CLI): o indicador da barra abre o popover.
  var pedirPortas = 0
  var pedirFechados = 0
  /// Muda para mandar fechar os popovers abertos (portas, memória, fechados, notificações).
  var fecharPopovers = 0

  // Quadro de agentes
  var quadroAberto = false
  var quadroSel: String?          // painel selecionado
  var quadroFiltro: String?       // workspace (nil = todos)
  var quadroFerramenta: String?   // "claude" | "codex" (nil = todas)
  var quadroBusca = ""
  var quadroTudo = false          // inclui terminais comuns
  var quadroMensagem: String?     // painel com o compose aberto no cartão
  var quadroRenomeando: String?   // painel com o título em edição

  @ObservationIgnored var paineis: [String: Painel] = [:]
  @ObservationIgnored var aoMudarLayout: (() -> Void)?
  @ObservationIgnored var aoMudarFoco: (() -> Void)?
  @ObservationIgnored var tamanhoDaArea: (() -> NSSize)?
  @ObservationIgnored let sugestoes = Sugestoes()
  @ObservationIgnored private var visitas: [String] = []
  @ObservationIgnored private var posVisita = -1
  @ObservationIgnored private var relogio: Timer?
  @ObservationIgnored private var salvarAgendado: DispatchWorkItem?
  @ObservationIgnored private var salvarAjustesAgendado: DispatchWorkItem?
  @ObservationIgnored var usoAgendado: DispatchWorkItem?
  @ObservationIgnored var proximoUso = Date.distantPast
  @ObservationIgnored var ancoras: [String: CGRect] = [:]   // depuração: onde cada âncora de uso está
  /// Divisão ou barra lateral sendo arrastada: os terminais agrupam o redimensionamento.
  @ObservationIgnored var arrastando = false
  @ObservationIgnored weak var janela: NSWindow?
  /// Mensagens já enviadas pelo compose (mais recente primeiro), para ↑ / ↓.
  @ObservationIgnored var historicoCompose: [String] = []
  @ObservationIgnored private var contadorMemoria = 0
  @ObservationIgnored private var amostrando = false

  init() {
    ajustes = Ajustes.carregar()
    escuroDoSistema = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
    sugestoes.loja = self
    aplicarAparencia(avisar: false)
    historicoCompose = (Armazem.ler("compose.json") as? [String]) ?? []
    fechados = ((Armazem.ler("fechados.json") as? [[String: Any]]) ?? []).compactMap(Fechado.init)
    Compose.limparAnexosAntigos()
  }

  // MARK: - Aparência

  /// A interface está no modo claro? (escolha fixa ou a do sistema)
  var modoClaro: Bool { ajustes.aparencia == "claro" || (ajustes.aparencia == "sistema" && !escuroDoSistema) }
  /// Tema em uso: o escolhido para o modo atual.
  var tema: Tema { Tema.porId(modoClaro ? ajustes.temaClaro : ajustes.temaEscuro) }
  /// Opacidade do fundo: a do tema, se ele tiver uma própria; senão a dos ajustes.
  var opacidade: Double { tema.opacidade ?? ajustes.opacidade }
  /// A janela deixa ver o que está atrás (opacidade abaixo de 100%).
  var translucido: Bool { opacidade < 0.995 }

  /// Escolhe um tema: ele entra no modo a que pertence (claro ou escuro) e a aparência o acompanha.
  func escolherTema(_ t: Tema) {
    var a = ajustes
    if t.claro { a.temaClaro = t.id } else { a.temaEscuro = t.id }
    if a.aparencia != "sistema" || t.claro != modoClaro { a.aparencia = t.claro ? "claro" : "escuro" }
    if a == ajustes { aplicarAparencia() } else { ajustes = a }
  }

  /// Recalcula tema, fonte e raios e redesenha tudo o que depende deles (todas as janelas e terminais).
  func aplicarAparencia(avisar: Bool = true) {
    Tema.atual = tema
    let ap = Aparencia.atual
    ap.escala = CGFloat(ajustes.escalaUI)
    ap.raio = CGFloat(ajustes.raio)
    ap.sombras = ajustes.sombras
    guard avisar else { return }
    ap.versao += 1
    (NSApp.delegate as? Delegado)?.aplicarVidro()
    paineis.values.forEach { $0.aplicarAjustes() }
    aoMudarLayout?()
  }

  func sistemaMudouAparencia(escuro: Bool) {
    guard escuro != escuroDoSistema else { return }
    escuroDoSistema = escuro
    if ajustes.aparencia == "sistema" { aplicarAparencia() }
  }

  func comecar() {
    carregarCacheDeUso()
    carregarContas { [weak self] in self?.atualizarUsos() }
    if !restaurar() {
      let w = Workspace(id: "w-geral", nome: "Geral", cor: Cor.paletaGrupos[0], simbolo: "house")
      workspaces = [w]
      workspaceAtivoID = w.id
      criarAba(kind: "shell", cwd: NSHomeDirectory())
    }
    relogio = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tique() }
    }
    relogio?.tolerance = 0.25      // deixa o sistema juntar este despertar com outros
    sugestoes.carregarHistorico()
  }

  // MARK: - Consultas

  var workspaceAtivo: Workspace? { workspaces.first { $0.id == workspaceAtivoID } ?? workspaces.first }
  func workspace(_ id: String) -> Workspace? { workspaces.first { $0.id == id } }
  func workspace(de a: Aba) -> Workspace? { workspace(a.workspace) }
  func abas(de w: Workspace) -> [Aba] { abas.filter { $0.workspace == w.id } }
  /// Abas do workspace na tela (é nelas que ⌘1…9 e ⇧⌘[ ] navegam).
  var abasEmOrdem: [Aba] { workspaceAtivo.map { abas(de: $0) } ?? [] }
  var todasEmOrdem: [Aba] { workspaces.flatMap { abas(de: $0) } }

  var abaAtiva: Aba? { abas.first { $0.id == abaAtivaID } }
  func aba(_ id: String) -> Aba? { abas.first { $0.id == id } }

  /// Acha um workspace por id, nome (sem diferenciar maiúsculas) ou posição (1, 2, 3…).
  func buscarWorkspace(_ ref: String) -> Workspace? {
    let r = ref.trimmingCharacters(in: .whitespaces)
    if let w = workspaces.first(where: { $0.id == r }) { return w }
    if let w = workspaces.first(where: { $0.nome.compare(r, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) { return w }
    if let n = Int(r), n >= 1, n <= workspaces.count { return workspaces[n - 1] }
    return nil
  }

  var painelAtivo: Painel? {
    guard let a = abaAtiva else { return nil }
    return painel(id: a.painelAtivo, aba: a) ?? a.arvore.folhas.first.flatMap { painel(id: $0.id, aba: a) }
  }

  /// Painel de um nó (cria o objeto na primeira vez; o terminal só nasce quando aparece).
  func painel(id: String, aba: Aba) -> Painel? {
    if let p = paineis[id] { return p }
    guard let no = aba.arvore.folha(id) else { return nil }
    let p = Painel(no: no, aba: aba, loja: self)
    paineis[id] = p
    return p
  }

  func paineisDaAba(_ a: Aba) -> [Painel] { a.arvore.folhas.compactMap { painel(id: $0.id, aba: a) } }
  func painelExistente(_ id: String) -> Painel? { paineis[id] }
  func painelPrincipal(_ a: Aba) -> Painel? { painel(id: a.painelAtivo, aba: a) }

  /// Painel pelo id, em qualquer workspace (cria o objeto se a aba ainda não foi aberta).
  func acharPainel(_ id: String) -> Painel? {
    if let p = paineis[id] { return p }
    for a in abas where a.arvore.folha(id) != nil { return painel(id: id, aba: a) }
    return nil
  }

  func titulo(_ a: Aba) -> String {
    if let t = a.titulo, !t.isEmpty { return t }
    return painelPrincipal(a)?.titulo ?? "Terminal"
  }

  func programa(_ a: Aba) -> String { painelPrincipal(a)?.programa ?? a.kind }

  /// Estado da aba = o mais "urgente" entre os painéis dela.
  func estado(_ a: Aba) -> EstadoPainel {
    let ps = a.arvore.folhas.compactMap { paineis[$0.id] }
    if ps.isEmpty { return .dormindo }
    for e in [EstadoPainel.trabalhando, .esperando, .rodando] where ps.contains(where: { $0.estado == e }) { return e }
    if ps.allSatisfy({ $0.estado == .dormindo }) { return .dormindo }
    if ps.allSatisfy({ $0.estado == .saiu || $0.estado == .dormindo }) { return .saiu }
    return .pronto
  }

  // MARK: - Agentes

  /// Todos os agentes (Claude/Codex), de todos os workspaces, na ordem da barra lateral.
  /// `tudo` inclui também os terminais comuns.
  func agentes(tudo: Bool = false, workspace: String? = nil) -> [Painel] {
    var out: [Painel] = []
    for a in todasEmOrdem where workspace == nil || a.workspace == workspace {
      for p in paineisDaAba(a) where tudo || p.tipoAgente != nil { out.append(p) }
    }
    return out
  }

  /// Quantos agentes estão trabalhando e quantos esperam você (num workspace ou em todos).
  func contagem(_ w: Workspace? = nil) -> (trabalhando: Int, esperando: Int) {
    var t = 0, e = 0
    for p in paineis.values where p.tipoAgente != nil {
      guard let a = p.aba, w == nil || a.workspace == w!.id else { continue }
      if p.estado == .trabalhando { t += 1 } else if p.estado == .esperando { e += 1 }
    }
    return (t, e)
  }

  /// Digita uma mensagem no agente e manda Enter logo depois (separado: os agentes tratam
  /// texto + Enter no mesmo bloco como colagem e não enviam).
  func enviarMensagem(_ p: Painel, _ texto: String) {
    guard p.vivo, !texto.isEmpty else { return }
    p.escrever(texto)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak p] in p?.escrever("\r") }
  }

  func reiniciarAgente(_ p: Painel, confirmado: Bool = false) {
    let reiniciar = { [weak self, weak p] in
      guard let self, let p else { return }
      p.reiniciar(comando: p.tipoAgente.flatMap(self.comandoDoTipo))
    }
    if !confirmado && p.vivo && !p.ocioso {
      confirmar("Reiniciar “\(p.titulo)”?", "O processo atual (\(p.processo)) é encerrado e a sessão começa de novo.", "Reiniciar",
                simbolo: "arrow.clockwise", entao: reiniciar)
    } else { reiniciar() }
  }

  /// Marca do quadro, feita à mão: "revisar", "concluido" ou nil (volta ao estado automático).
  func marcar(_ p: Painel, _ marca: String?) {
    p.marca = marca
    p.no.marca = marca
    salvarDepois()
  }

  // MARK: - Utilidades de texto

  nonisolated static func nomeDaPasta(_ p: String) -> String {
    if p == NSHomeDirectory() || p.isEmpty { return "~" }
    return (p as NSString).lastPathComponent
  }

  nonisolated static func encurtar(_ p: String) -> String {
    let h = NSHomeDirectory()
    if p == h { return "~" }
    if p.hasPrefix(h + "/") { return "~" + p.dropFirst(h.count) }
    return p
  }

  /// "agora", "3 min", "1 h 05", "2 d".
  nonisolated static func duracao(desde d: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(d)))
    if s < 60 { return "agora" }
    if s < 3600 { return "\(s / 60) min" }
    if s < 86400 { return "\(s / 3600) h \(String(format: "%02d", (s % 3600) / 60))" }
    return "\(s / 86400) d"
  }

  func fonte(zoom: Double = 0) -> NSFont {
    let tam = CGFloat(max(8, ajustes.tamanho + zoom))
    return NSFont(name: ajustes.fonte, size: tam)
      ?? NSFont(name: "JetBrains Mono", size: tam)
      ?? NSFont.monospacedSystemFont(ofSize: tam, weight: .regular)
  }

  func comandoDoTipo(_ kind: String) -> String? { ajustes.comando(kind) }

  func ambiente(aba: Aba?) -> [String: String] {
    Contas.ambiente(aba?.contas ?? ajustes.contasPadrao)
  }

  // MARK: - Personagens e hierarquia (maestro → subagentes)

  /// Próximo personagem livre do elenco.
  func novaPersona(papel: String = "") -> Persona {
    var p = Persona.proximo(emUso: abas.flatMap { $0.arvore.folhas.compactMap { $0.persona?.nome } })
    p.papel = papel
    return p
  }

  /// Subagentes de um painel (os que ele criou), na ordem da barra lateral.
  func filhos(de id: String) -> [Painel] {
    var out: [Painel] = []
    for a in todasEmOrdem { for n in a.arvore.folhas where n.pai == id { if let p = painel(id: n.id, aba: a) { out.append(p) } } }
    return out
  }

  func ehMaestro(_ p: Painel) -> Bool { p.maestro || abas.contains { $0.arvore.folhas.contains { $0.pai == p.id } } }

  /// Um subagente parou de trabalhar e foi criado com retorno: o maestro recebe o aviso com o
  /// resultado (num arquivo, para não inundar a conversa dele).
  func entregarAoPai(_ filho: Painel) {
    guard filho.no.retorno, let idPai = filho.pai, let pai = acharPainel(idPai), pai.vivo, pai.agente != nil else { return }
    let bloco = Compose.contexto(de: filho, apelido: filho.apelido, loja: self, linhas: 120, sempreArquivo: true)
    enviarComposto(de: pai, texto: "[Subagente @\(filho.apelido) terminou — \(filho.titulo)]\n\(bloco)", anexos: [], lembrar: false)
  }

  // MARK: - Workspaces

  @discardableResult
  func criarWorkspace(_ nome: String, pasta: String? = nil, cor: String? = nil, simbolo: String? = nil) -> Workspace {
    let usadas = Set(workspaces.map(\.cor))
    let corLivre = Cor.paletaGrupos.first { !usadas.contains($0) } ?? Cor.paletaGrupos[workspaces.count % Cor.paletaGrupos.count]
    let w = Workspace(nome: nome, cor: cor ?? corLivre, simbolo: simbolo ?? "folder",
                      pasta: pasta.map { ($0 as NSString).expandingTildeInPath } ?? NSHomeDirectory())
    workspaces.append(w)
    salvarDepois()
    return w
  }

  func ativarWorkspace(_ w: Workspace) {
    guard workspaceAtivoID != w.id || abaAtiva?.workspace != w.id else { return }
    workspaceAtivoID = w.id
    filtro = ""
    if let a = w.abaAtiva.flatMap({ aba($0) }).flatMap({ $0.workspace == w.id ? $0 : nil }) ?? abas(de: w).first {
      ativar(a)
    } else {
      abaAtivaID = nil
      sugestoes.fechar()
      aoMudarLayout?()
      salvarDepois()
    }
  }

  func workspaceNumero(_ n: Int) {
    guard n >= 1, n <= workspaces.count else { return }
    ativarWorkspace(workspaces[n - 1])
  }

  func workspaceRelativo(_ delta: Int) {
    guard !workspaces.isEmpty else { return }
    let i = workspaces.firstIndex { $0.id == workspaceAtivoID } ?? 0
    ativarWorkspace(workspaces[(i + delta + workspaces.count) % workspaces.count])
  }

  func moverWorkspace(_ w: Workspace, _ delta: Int) {
    guard let i = workspaces.firstIndex(where: { $0.id == w.id }) else { return }
    let j = i + delta
    guard j >= 0, j < workspaces.count else { return }
    workspaces.swapAt(i, j)
    salvarDepois()
  }

  /// Fecha o workspace e as abas dele. Sempre sobra pelo menos um workspace.
  func fecharWorkspace(_ w: Workspace, confirmado: Bool = false) {
    let dele = abas(de: w)
    let ocupados = dele.flatMap { paineisDaAba($0) }.filter { $0.vivo && !$0.ocioso }
    if !confirmado && !dele.isEmpty {
      let detalhe = ocupados.isEmpty ? "As \(dele.count) aba(s) dele são fechadas."
        : "Ainda está rodando: \(Set(ocupados.map(\.processo)).sorted().joined(separator: ", ")). As \(dele.count) aba(s) são fechadas."
      confirmar("Fechar o workspace “\(w.nome)”?", detalhe, "Fechar workspace", destrutivo: true) { [weak self] in
        self?.fecharWorkspace(w, confirmado: true)
      }
      return
    }
    for a in dele {
      for n in a.arvore.folhas { if let p = paineis[n.id] { lembrarFechado(p) }; paineis[n.id]?.encerrar(); paineis[n.id] = nil }
      visitas.removeAll { $0 == a.id }
    }
    abas.removeAll { $0.workspace == w.id }
    let i = workspaces.firstIndex { $0.id == w.id } ?? 0
    workspaces.removeAll { $0.id == w.id }
    if workspaces.isEmpty {
      workspaces = [Workspace(id: "w-geral", nome: "Geral", cor: Cor.paletaGrupos[0], simbolo: "house")]
    }
    if workspaceAtivoID == w.id {
      workspaceAtivoID = nil
      abaAtivaID = nil
      ativarWorkspace(workspaces[min(i, workspaces.count - 1)])
    }
    aoMudarLayout?()
    atualizarSelo()
    salvarDepois()
  }

  // MARK: - Criar e fechar abas

  @discardableResult
  func criarAba(kind: String = "shell", cwd: String? = nil, workspace: String? = nil, conta: String? = nil,
                comando: String? = nil, titulo: String? = nil, ativar: Bool = true,
                persona: Persona? = nil, papel: String? = nil, pai: String? = nil, tarefa: String? = nil) -> Aba {
    let w = workspace.flatMap { self.workspace($0) } ?? workspaceAtivo ?? criarWorkspace("Geral", simbolo: "house")
    let atual = abaAtiva?.workspace == w.id ? painelAtivo : nil
    let pasta = cwd ?? (ajustes.novaAbaNaPastaAtual ? atual?.cwd : nil) ?? w.pasta
    let no = No(painel: "p-" + UUID().uuidString.prefix(10).lowercased(), cwd: pasta, kind: kind, comando: comando ?? comandoDoTipo(kind))
    let a = Aba(workspace: w.id, kind: kind, arvore: no, contas: ajustes.contasPadrao)
    if let c = conta, let ct = contas.first(where: { $0.id == c }) { a.definirConta(ct.tipo, c) }
    a.titulo = titulo
    if Ferramenta.eh(kind) {
      no.persona = persona ?? novaPersona(papel: papel ?? (pai != nil ? "Subagente" : ""))
      no.pai = pai
      no.tarefa = tarefa.flatMap { Nomes.tarefaCurta($0) }
      no.sessao = nil
    }
    if let i = abas.firstIndex(where: { $0.id == abaAtivaID }), abaAtiva?.workspace == w.id { abas.insert(a, at: i + 1) } else { abas.append(a) }
    if ativar { self.ativar(a) } else if w.abaAtiva == nil { w.abaAtiva = a.id }
    salvarDepois()
    return a
  }

  func dividir(horizontal: Bool, comando: String? = nil) -> Painel? {
    guard let a = abaAtiva, let atual = painelAtivo else { return nil }
    a.maximizado = nil
    let novo = No(painel: "p-" + UUID().uuidString.prefix(10).lowercased(), cwd: atual.cwd, kind: "shell", comando: comando, zoom: atual.zoom)
    let div = No(divisao: horizontal, a: atual.no, b: novo)
    if let pai = a.arvore.pai(de: atual.no) {
      if pai.a === atual.no { pai.a = div } else { pai.b = div }
    } else { a.arvore = div }
    a.painelAtivo = novo.id
    mudouArvore(a)
    return painel(id: novo.id, aba: a)
  }

  func fecharPainel(_ p: Painel?, confirmado: Bool = false) {
    guard let p, let a = p.aba else { return }
    if !confirmado && ajustes.confirmarFechar && p.vivo && !p.ocioso {
      confirmar("Fechar “\(p.titulo)”?", "Ainda está rodando: \(p.processo). Fechar encerra o processo.", "Fechar", destrutivo: true) { [weak self, weak p] in
        self?.fecharPainel(p, confirmado: true)
      }
      return
    }
    let folhas = a.arvore.folhas
    if folhas.count <= 1 { removerAba(a); return }
    lembrarFechado(p)
    guard let pai = a.arvore.pai(de: p.no) else { return }
    let irmao = pai.a === p.no ? pai.b! : pai.a!
    if let avo = a.arvore.pai(de: pai) {
      if avo.a === pai { avo.a = irmao } else { avo.b = irmao }
    } else { a.arvore = irmao }
    p.encerrar()
    paineis[p.id] = nil
    if a.maximizado == p.id { a.maximizado = nil }
    if a.painelAtivo == p.id { a.painelAtivo = irmao.folhas.first?.id ?? "" }
    if quadroSel == p.id { quadroSel = nil }
    if quadroMensagem == p.id { quadroMensagem = nil }
    mudouArvore(a)
  }

  func fecharAba(_ a: Aba?, confirmado: Bool = false) {
    guard let a else { return }
    let ocupados = paineisDaAba(a).filter { $0.vivo && !$0.ocioso }
    if !confirmado && ajustes.confirmarFechar && !ocupados.isEmpty {
      confirmar("Fechar a aba “\(titulo(a))”?", "Ainda está rodando: \(ocupados.map(\.processo).joined(separator: ", ")).", "Fechar", destrutivo: true) { [weak self] in
        self?.fecharAba(a, confirmado: true)
      }
      return
    }
    removerAba(a)
  }

  private func removerAba(_ a: Aba) {
    for n in a.arvore.folhas { if let p = paineis[n.id] { lembrarFechado(p) }; paineis[n.id]?.encerrar(); paineis[n.id] = nil }
    let irmas = abas.filter { $0.workspace == a.workspace }
    let i = irmas.firstIndex { $0.id == a.id } ?? 0
    abas.removeAll { $0.id == a.id }
    visitas.removeAll { $0 == a.id }
    let w = workspace(a.workspace)
    let restantes = abas.filter { $0.workspace == a.workspace }
    let prox = restantes.isEmpty ? nil : restantes[min(i, restantes.count - 1)]
    if w?.abaAtiva == a.id { w?.abaAtiva = prox?.id }
    if abaAtivaID == a.id {
      abaAtivaID = nil
      if let prox { ativar(prox) } else { aoMudarLayout?() }   // workspace vazio: mostra o estado vazio dele
    } else {
      aoMudarLayout?()
    }
    atualizarSelo()
    salvarDepois()
  }

  func duplicar(_ a: Aba) {
    let p = painelPrincipal(a)
    let nova = criarAba(kind: a.kind, cwd: p?.cwd, workspace: a.workspace, ativar: true)
    nova.contas = a.contas
  }

  /// Move uma aba para outro workspace (ou reordena dentro do mesmo).
  func mover(aba id: String, paraWorkspace w: String, antesDe alvo: String?) {
    guard let i = abas.firstIndex(where: { $0.id == id }), workspace(w) != nil else { return }
    let a = abas.remove(at: i)
    let origem = a.workspace
    a.workspace = w
    if let alvo, let j = abas.firstIndex(where: { $0.id == alvo }) { abas.insert(a, at: j) } else { abas.append(a) }
    if origem != w {
      if let wo = workspace(origem), wo.abaAtiva == id { wo.abaAtiva = abas(de: wo).first?.id }
      if abaAtivaID == id {      // a aba na tela foi embora: o workspace atual mostra outra
        abaAtivaID = nil
        if let wo = workspace(origem), let outra = wo.abaAtiva.flatMap({ aba($0) }) { ativar(outra) } else { aoMudarLayout?() }
      }
      if let wd = workspace(w), wd.abaAtiva == nil { wd.abaAtiva = id }
    }
    salvarDepois()
  }

  // MARK: - Navegação

  func ativar(_ a: Aba, registrar: Bool = true) {
    abaAtivaID = a.id
    workspaceAtivoID = a.workspace
    workspace(a.workspace)?.abaAtiva = a.id
    a.atencao = false
    if registrar {
      if quadroAberto { quadroAberto = false; quadroMensagem = nil }    // navegar fecha o quadro
      if posVisita < visitas.count - 1 { visitas = Array(visitas.prefix(posVisita + 1)) }
      visitas.removeAll { $0 == a.id }
      visitas.append(a.id)
      if visitas.count > 50 { visitas.removeFirst() }
      posVisita = visitas.count - 1
    }
    sugestoes.fechar()
    aoMudarLayout?()
    atualizarSelo()
    salvarDepois()
  }

  func navegarVisita(_ delta: Int) {
    let alvo = posVisita + delta
    guard alvo >= 0, alvo < visitas.count, let a = aba(visitas[alvo]) else { return }
    posVisita = alvo
    ativar(a, registrar: false)
  }

  func abaRelativa(_ delta: Int) {
    let lista = abasEmOrdem
    guard !lista.isEmpty else { return }
    let i = lista.firstIndex { $0.id == abaAtivaID } ?? 0
    ativar(lista[(i + delta + lista.count) % lista.count])
  }

  func abaNumero(_ n: Int) {
    let lista = abasEmOrdem
    guard !lista.isEmpty else { return }
    ativar(n == 9 ? lista[lista.count - 1] : lista[min(n - 1, lista.count - 1)])
  }

  func painelRelativo(_ delta: Int) {
    guard let a = abaAtiva else { return }
    let f = a.arvore.folhas
    let i = f.firstIndex { $0.id == a.painelAtivo } ?? 0
    if let p = painel(id: f[(i + delta + f.count) % f.count].id, aba: a) { focar(p) }
  }

  /// Foco no painel vizinho na direção pedida (dx, dy = -1, 0 ou 1), pela posição na tela.
  func painelNaDirecao(dx: CGFloat, dy: CGFloat) {
    guard let a = abaAtiva, a.maximizado == nil, let atual = painelAtivo, let ca = atual.caixa, ca.window != nil else { return }
    let ra = ca.convert(ca.bounds, to: nil)
    var melhor: (Painel, CGFloat)?
    for p in paineisDaAba(a) where p !== atual {
      guard let c = p.caixa, c.window != nil else { continue }
      let r = c.convert(c.bounds, to: nil)
      let vx = r.midX - ra.midX, vy = r.midY - ra.midY      // janela: y cresce para cima
      let avanco = dx != 0 ? vx * dx : vy * -dy
      guard avanco > 1 else { continue }
      let lateral = dx != 0 ? abs(vy) : abs(vx)
      let custo = avanco + lateral * 2
      if melhor == nil || custo < melhor!.1 { melhor = (p, custo) }
    }
    if let m = melhor { focar(m.0) }
  }

  func focar(_ p: Painel, teclado: Bool = true) {
    guard let a = p.aba else { return }
    if abaAtivaID != a.id {
      a.painelAtivo = p.id
      if a.maximizado != nil && a.maximizado != p.id { a.maximizado = nil; a.versaoArvore += 1 }
      ativar(a)
    } else if a.painelAtivo != p.id {
      a.painelAtivo = p.id
      sugestoes.fechar()
      if a.maximizado != nil { a.maximizado = nil; mudouArvore(a) } else { aoMudarFoco?() }
    }
    if teclado, let v = p.view { v.window?.makeFirstResponder(v) }
  }

  func maximizar() {
    guard let a = abaAtiva, a.arvore.folhas.count > 1 else { return }
    a.maximizado = a.maximizado == nil ? a.painelAtivo : nil
    mudouArvore(a)
  }

  private func mudouArvore(_ a: Aba) {
    a.versaoArvore += 1
    aoMudarLayout?()
    salvarDepois()
  }

  // MARK: - Quadro de agentes

  func abrirQuadro(_ aberto: Bool? = nil) {
    let novo = aberto ?? !quadroAberto
    guard novo != quadroAberto else { return }
    if novo {
      paletaAberta = false
      quadroMensagem = nil
      let lista = agentesDoQuadro()
      if quadroSel == nil || !lista.contains(where: { $0.id == quadroSel }) {
        quadroSel = (lista.first { $0.estado == .esperando } ?? lista.first)?.id
      }
    } else {
      quadroMensagem = nil
      DispatchQueue.main.async { [weak self] in
        if let v = self?.painelAtivo?.view { v.window?.makeFirstResponder(v) }
      }
    }
    quadroAberto = novo
  }

  /// Colunas do quadro, na ordem: esperando você · trabalhando · revisar · parados · concluído.
  /// "Revisar" e "Concluído" são marcas feitas à mão; as outras vêm do estado do agente.
  static let colunasDoQuadro = 5

  /// Agentes na ordem em que o quadro mostra (coluna a coluna), já com os filtros aplicados.
  func agentesDoQuadro() -> [Painel] {
    var todos = agentes(tudo: quadroTudo, workspace: quadroFiltro)
    if let f = quadroFerramenta { todos = todos.filter { $0.tipoAgente == f } }
    let b = quadroBusca.trimmingCharacters(in: .whitespaces).lowercased()
    if !b.isEmpty {
      todos = todos.filter { p in
        let ws = p.aba.flatMap { workspace(de: $0) }?.nome ?? ""
        return "\(p.aba?.titulo ?? "") \(p.titulo) \(ws) \(p.cwd) \(p.branch)".lowercased().contains(b)
      }
    }
    return (0..<Loja.colunasDoQuadro).flatMap { c in todos.filter { Loja.colunaDoQuadro($0) == c } }
  }

  static func colunaDoQuadro(_ e: EstadoPainel) -> Int {
    switch e {
    case .esperando: return 0
    case .trabalhando, .rodando: return 1
    default: return 3
    }
  }

  /// Coluna de um agente: quem trabalha fica sempre em "trabalhando"; fora isso, vale a marca.
  static func colunaDoQuadro(_ p: Painel) -> Int {
    if p.estado == .trabalhando || p.estado == .rodando { return 1 }
    if p.marca == "revisar" { return 2 }
    if p.marca == "concluido" { return 4 }
    return colunaDoQuadro(p.estado)
  }

  /// Arrastar um cartão para uma coluna: revisar / concluído marcam; esperando / parados tiram a marca.
  func soltarNoQuadro(_ id: String, coluna: Int) {
    guard let p = acharPainel(id) else { return }
    switch coluna {
    case 2: marcar(p, "revisar")
    case 4: marcar(p, "concluido")
    case 0, 3: marcar(p, nil)
    default: break
    }
    quadroSel = p.id
  }

  /// Teclas do quadro (vindas do monitor de teclado). Devolve true se consumiu.
  func teclaDoQuadro(_ codigo: UInt16) -> Bool {
    let lista = agentesDoQuadro()
    let i = lista.firstIndex { $0.id == quadroSel }
    switch codigo {
    case 53:                                   // esc
      if quadroRenomeando != nil { quadroRenomeando = nil }
      else if quadroMensagem != nil { quadroMensagem = nil } else { abrirQuadro(false) }
      return true
    case 125, 124, 48:                         // ↓ → ⇥
      if !lista.isEmpty { quadroSel = lista[((i ?? -1) + 1) % lista.count].id }
      return true
    case 126, 123:                             // ↑ ←
      if !lista.isEmpty { quadroSel = lista[((i ?? 0) - 1 + lista.count) % lista.count].id }
      return true
    case 36, 76:                               // ↩
      if let i { let p = lista[i]; abrirQuadro(false); focar(p) }
      return true
    case 46:                                   // M: mensagem
      if let i, lista[i].vivo { quadroMensagem = lista[i].id }
      return true
    case 15:                                   // R: marcar para revisar (de novo, tira)
      if let i { marcar(lista[i], lista[i].marca == "revisar" ? nil : "revisar") }
      return true
    case 8:                                    // C: concluído (de novo, tira)
      if let i { marcar(lista[i], lista[i].marca == "concluido" ? nil : "concluido") }
      return true
    case 45:                                   // N: renomear
      if let i { quadroRenomeando = lista[i].id }
      return true
    default: return false
    }
  }

  // MARK: - Atividade e notificações

  private func tique() {
    for p in paineis.values where p.vivo { p.vigiar() }
    if Date() >= proximoUso { atualizarUsos() }
    contadorMemoria += 1
    // Memória a cada 10 s e portas a cada 12 s — e só com a janela à vista.
    if contadorMemoria % 10 == 2 { amostrarMemoria() }
    if contadorMemoria % 12 == 5, ajustes.portas, paineis.values.contains(where: { $0.vivo && !$0.ocioso }) { atualizarPortas() }
    // De minuto em minuto, devolve ao sistema a memória que ficou livre no heap.
    if contadorMemoria % 60 == 30 { Memoria.aliviar() }
  }

  /// Memória do app e de cada painel, a cada ~4 s e só com a janela à vista. A passada pela
  /// tabela de processos roda fora da thread principal.
  func amostrarMemoria(forcar: Bool = false) {
    guard ajustes.memoria, !amostrando else { return }
    guard forcar || (janela?.occlusionState.contains(.visible) ?? false) else { return }
    amostrando = true
    let raizes: [(String, pid_t)] = paineis.values.compactMap { p in p.pidShell.map { (p.id, $0) } }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let app = Memoria.doApp()
      let arvores = Memoria.arvores(raizes.map(\.1))
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self else { return }
          self.amostrando = false
          if self.memoriaApp != app { self.memoriaApp = app }
          var soma: UInt64 = 0
          for (id, pid) in raizes {
            guard let p = self.paineis[id], let a = arvores[pid] else { continue }
            soma += a.bytes
            // Só republica se mudou de forma visível (evita redesenhar a cada amostra).
            if p.memoria / 1_048_576 != a.bytes / 1_048_576 { p.memoria = a.bytes }
            if p.processos != a.processos { p.processos = a.processos }
          }
          for p in self.paineis.values where !p.vivo && p.memoria != 0 { p.memoria = 0; p.processos = 0 }
          if self.memoriaPaineis / 1_048_576 != soma / 1_048_576 { self.memoriaPaineis = soma }
        }
      }
    }
  }

  func parouDeTrabalhar(_ p: Painel, durou: TimeInterval) {
    if durou > 2 { entregarAoPai(p) }
    guard ajustes.avisarAgentes, let ag = p.agente, durou > 5, !estaVendo(p) else { return }
    notificar(p, titulo: "\(p.persona?.nome ?? nomeFerramenta(ag)) parou — aguardando você",
              corpo: "\(p.aba.map(titulo) ?? "") · \(Loja.encurtar(p.cwd)) · \(Int(durou)) s de trabalho")
  }

  func comandoTerminou(_ p: Painel, _ r: ResultadoComando) {
    guard ajustes.avisarComandos, r.duracao >= ajustes.comandoLongo, !estaVendo(p) else { return }
    let cmd = r.comando.split(separator: " ").first.map(String.init) ?? ""
    if (Ferramenta.ids + ["vim", "nvim", "ssh", "less", "man", "top", "htop"]).contains(cmd) { return }
    let ok = r.codigo == nil || r.codigo == 0
    notificar(p, titulo: ok ? "Comando terminou" : "Comando falhou (código \(r.codigo ?? -1))",
              corpo: "\(r.comando) · \(Int(r.duracao)) s")
  }

  func notificacaoDoPrograma(_ p: Painel, titulo: String?, corpo: String) {
    guard !estaVendo(p), !corpo.isEmpty else { return }
    notificar(p, titulo: titulo ?? p.persona?.nome ?? p.agente.map(nomeFerramenta) ?? p.titulo, corpo: corpo)
  }

  func sino(_ p: Painel) {
    if estaVendo(p) { p.caixa?.piscar(); return }
    guard Date().timeIntervalSince(p.ultimoSino) > 4 else { return }
    p.ultimoSino = Date()
    let nome = p.persona?.nome ?? p.agente.map(nomeFerramenta) ?? p.titulo
    notificar(p, titulo: "\(nome) pede atenção", corpo: "\(p.aba.map(titulo) ?? "") · \(Loja.encurtar(p.cwd))")
  }

  private func estaVendo(_ p: Painel) -> Bool {
    janelaFocada && !quadroAberto && p.aba?.id == abaAtivaID && (p.caixa?.window != nil)
  }

  func notificar(_ p: Painel, titulo: String, corpo: String) {
    guard let a = p.aba else { return }
    if a.id != abaAtivaID || !janelaFocada { a.atencao = true }
    let ws = workspace(a.workspace)?.nome ?? ""
    let texto = workspaces.count > 1 && !ws.isEmpty ? "\(ws) · \(corpo)" : corpo
    notificacoes.insert(Notificacao(titulo: titulo, corpo: texto, aba: a.id, processo: p.programa), at: 0)
    if notificacoes.count > 60 { notificacoes.removeLast(notificacoes.count - 60) }
    naoLidas += 1
    let c = UNUserNotificationCenter.current()
    c.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
      guard ok else { return }
      let n = UNMutableNotificationContent()
      n.title = titulo; n.body = texto; n.sound = .default; n.userInfo = ["aba": a.id]
      c.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
    }
    atualizarSelo()
  }

  func atualizarSelo() {
    let n = abas.filter(\.atencao).count
    NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
  }

  // MARK: - Ajustes

  private func ajustesMudaram(_ antes: Ajustes) {
    if antes.atualizacao != ajustes.atualizacao { Atualizador.shared.mudouModo(ajustes.atualizacao) }
    // Grava com atraso: um controle deslizante muda o valor dezenas de vezes por segundo.
    salvarAjustesAgendado?.cancel()
    let w = DispatchWorkItem { [weak self] in self?.ajustes.salvar() }
    salvarAjustesAgendado = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    let aparencia = antes.aparencia != ajustes.aparencia || antes.temaEscuro != ajustes.temaEscuro || antes.temaClaro != ajustes.temaClaro ||
      antes.escalaUI != ajustes.escalaUI || antes.raio != ajustes.raio || antes.sombras != ajustes.sombras ||
      antes.opacidade != ajustes.opacidade || antes.desfoqueRaio != ajustes.desfoqueRaio
    let terminais = antes.fonte != ajustes.fonte || antes.tamanho != ajustes.tamanho ||
      antes.cursor != ajustes.cursor || antes.gpu != ajustes.gpu || antes.optionMeta != ajustes.optionMeta ||
      antes.rolagem != ajustes.rolagem || antes.margem != ajustes.margem || antes.compose != ajustes.compose
    if aparencia { aplicarAparencia() }
    else if terminais { paineis.values.forEach { $0.aplicarAjustes() } }
    if antes.memoria != ajustes.memoria, ajustes.memoria { amostrarMemoria(forcar: true) }
    if antes.usoClaude != ajustes.usoClaude && ajustes.usoClaude == "ligado" { atualizarUsos(forcar: true) }
  }

  // MARK: - Persistência

  func salvarDepois() {
    salvarAgendado?.cancel()
    let w = DispatchWorkItem { [weak self] in self?.salvar() }
    salvarAgendado = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
  }

  func salvar() {
    salvarAgendado?.cancel()
    salvarAjustesAgendado?.cancel()
    ajustes.salvar()
    let dados: [String: Any] = [
      "versao": 3,
      "workspaceAtivo": workspaceAtivoID ?? "",
      "workspaces": workspaces.map { w -> [String: Any] in
        ["id": w.id, "nome": w.nome, "cor": w.cor, "simbolo": w.simbolo, "pasta": w.pasta, "abaAtiva": w.abaAtiva ?? ""]
      },
      "abas": abas.map { a -> [String: Any] in
        var d: [String: Any] = ["id": a.id, "workspace": a.workspace, "kind": a.kind, "contaClaude": a.conta("claude"),
                                "contaCodex": a.conta("codex"), "contaGemini": a.conta("gemini"), "painelAtivo": a.painelAtivo,
                                "arvore": a.arvore.dicionario(painel: { self.paineis[$0] })]
        if let t = a.titulo { d["titulo"] = t }
        if let c = a.cor { d["cor"] = c }
        return d
      },
    ]
    Armazem.gravar("estado.json", dados)
  }

  private func restaurar() -> Bool {
    guard ajustes.restaurar, let bruto = Armazem.ler("estado.json") as? [String: Any] else { return false }
    let d = Migracao.paraV3(bruto)
    guard (d["versao"] as? Int) == 3, let lista = d["abas"] as? [[String: Any]] else { return false }
    workspaces = ((d["workspaces"] as? [[String: Any]]) ?? []).map { g in
      let w = Workspace(id: g["id"] as? String ?? UUID().uuidString, nome: g["nome"] as? String ?? "Workspace",
                        cor: g["cor"] as? String ?? Cor.paletaGrupos[0], simbolo: g["simbolo"] as? String ?? "folder",
                        pasta: g["pasta"] as? String ?? NSHomeDirectory())
      if let a = g["abaAtiva"] as? String, !a.isEmpty { w.abaAtiva = a }
      return w
    }
    if workspaces.isEmpty { workspaces = [Workspace(id: "w-geral", nome: "Geral", cor: Cor.paletaGrupos[0], simbolo: "house")] }
    for ad in lista {
      guard let arvore = (ad["arvore"] as? [String: Any]).flatMap(No.de) else { continue }
      for f in arvore.folhas { prepararRetomada(f) }
      let w = ad["workspace"] as? String ?? workspaces[0].id
      let a = Aba(id: ad["id"] as? String ?? UUID().uuidString, workspace: workspace(w) != nil ? w : workspaces[0].id,
                  kind: ad["kind"] as? String ?? "shell", arvore: arvore,
                  contas: ["claude": ad["contaClaude"] as? String ?? ajustes.contaClaude,
                           "codex": ad["contaCodex"] as? String ?? ajustes.contaCodex,
                           "gemini": ad["contaGemini"] as? String ?? ajustes.contaGemini])
      a.titulo = ad["titulo"] as? String
      a.cor = ad["cor"] as? String
      if let pa = ad["painelAtivo"] as? String, arvore.folha(pa) != nil { a.painelAtivo = pa }
      abas.append(a)
    }
    guard !abas.isEmpty || workspaces.count > 1 else { return false }
    let w = workspace(d["workspaceAtivo"] as? String ?? "") ?? workspaces[0]
    workspaceAtivoID = w.id
    if let alvo = w.abaAtiva.flatMap({ aba($0) }) ?? abas(de: w).first { ativar(alvo) }
    return true
  }

  /// Claude e Codex voltam na última conversa daquela pasta.
  private func prepararRetomada(_ f: No) {
    let agente = Ferramenta.eh(f.ultimoProcesso) ? f.ultimoProcesso : (f.kind != "shell" ? f.kind : nil)
    guard let ag = agente, let base = comandoDoTipo(ag), let fer = Ferramenta.de(ag) else { f.comando = nil; return }
    // Com o id da conversa guardado ao sair, volta exatamente ela; sem ele, a última daquela pasta.
    f.comando = ajustes.retomarAgentes ? fer.retomar(base, sessao: f.sessao) : base
  }

  // MARK: - Compose

  func lembrarNoCompose(_ texto: String) {
    let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    historicoCompose.removeAll { $0 == t }
    historicoCompose.insert(t, at: 0)
    if historicoCompose.count > 200 { historicoCompose.removeLast(historicoCompose.count - 200) }
    Armazem.gravar("compose.json", historicoCompose)
  }
}

/// Converte o estado salvo por versões antigas para o formato atual (versão 3).
enum Migracao {
  /// v2 tinha grupos na barra lateral; cada grupo vira um workspace com as mesmas abas.
  /// O arquivo antigo fica guardado em `estado.v2.json`.
  static func paraV3(_ d: [String: Any]) -> [String: Any] {
    guard (d["versao"] as? Int) == 2 else { return d }
    let copia = Armazem.pasta.appendingPathComponent("estado.v2.json")
    if !FileManager.default.fileExists(atPath: copia.path) {
      try? FileManager.default.copyItem(at: Armazem.pasta.appendingPathComponent("estado.json"), to: copia)
    }
    let abas = (d["abas"] as? [[String: Any]]) ?? []
    var grupos = (d["grupos"] as? [[String: Any]]) ?? []
    if grupos.isEmpty { grupos = [["id": "g-geral", "nome": "Geral", "cor": Cor.paletaGrupos[0]]] }
    let ativa = d["abaAtiva"] as? String ?? ""
    var wsAtivo = grupos.first?["id"] as? String ?? ""
    let ids = Set(grupos.compactMap { $0["id"] as? String })
    var novasAbas: [[String: Any]] = []
    for var a in abas {
      var g = a["grupo"] as? String ?? ""
      if !ids.contains(g) { g = grupos[0]["id"] as? String ?? "" }
      a["workspace"] = g
      a["grupo"] = nil
      if a["id"] as? String == ativa { wsAtivo = g }
      novasAbas.append(a)
    }
    func pastas(_ no: [String: Any]?) -> [String] {
      guard let no else { return [] }
      if no["tipo"] as? String == "divisao" { return pastas(no["a"] as? [String: Any]) + pastas(no["b"] as? [String: Any]) }
      return (no["cwd"] as? String).map { [$0] } ?? []
    }
    let home = NSHomeDirectory()
    let workspaces = grupos.enumerated().map { (i, g) -> [String: Any] in
      let id = g["id"] as? String ?? "w-\(i)"
      let dele = novasAbas.filter { $0["workspace"] as? String == id }
      // Pasta do workspace: a mais usada entre os painéis do grupo; no empate, a pasta pessoal
      // se ela estiver entre as empatadas, senão a primeira.
      let todas = dele.flatMap { pastas($0["arvore"] as? [String: Any]) }.filter { !$0.isEmpty }
      let contagem = Dictionary(todas.map { ($0, 1) }, uniquingKeysWith: +)
      let maior = contagem.values.max() ?? 0
      let empatadas = todas.filter { contagem[$0] == maior }
      let pasta = empatadas.contains(home) ? home : (empatadas.first ?? home)
      let nome = g["nome"] as? String ?? "Workspace"
      let abaAtiva = dele.first { $0["id"] as? String == ativa }?["id"] as? String ?? dele.first?["id"] as? String ?? ""
      return ["id": id, "nome": nome, "cor": g["cor"] as? String ?? Cor.paletaGrupos[i % Cor.paletaGrupos.count],
              "simbolo": nome.lowercased() == "geral" ? "house" : "folder", "pasta": pasta, "abaAtiva": abaAtiva]
    }
    return ["versao": 3, "workspaceAtivo": wsAtivo, "workspaces": workspaces, "abas": novasAbas]
  }
}
