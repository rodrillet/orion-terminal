import Cocoa
import SwiftUI
import SwiftTerm
import Observation

/// Resultado de um comando, capturado entre as marcas OSC 133 C e D da integração com o zsh.
struct ResultadoComando {
  let comando: String
  let codigo: Int?
  let saida: String
  let duracao: TimeInterval
}

/// Um painel: um terminal SwiftTerm ligado a um PTY. O terminal é criado só quando o painel
/// aparece pela primeira vez (abas restauradas não gastam memória até serem abertas).
@MainActor @Observable
final class Painel: TerminalViewDelegate {
  let id: String
  @ObservationIgnored weak var aba: Aba?
  @ObservationIgnored let no: No
  @ObservationIgnored unowned let loja: Loja

  var cwd: String
  var processo = ""
  var ocioso = true
  var tituloOSC = ""
  var branch = ""
  var alterados = 0
  var ocupado = false
  var iniciado = false
  var vivo = false
  var codigoSaida: Int32?
  var noPrompt = false
  var progresso: Int?          // OSC 9;4
  var zoom: Double
  /// Estado para quem orquestra (quadro de agentes, barra lateral) e desde quando está nele.
  var estado = EstadoPainel.dormindo
  var desde = Date()
  /// Última linha útil que o agente escreveu (prévia na barra lateral). Lida só quando ele para.
  var previa = ""
  /// Marca do quadro feita à mão ("revisar" | "concluido"); some quando o agente volta a trabalhar.
  var marca: String?
  /// Memória do shell deste painel e de tudo o que ele abriu (bytes), e quantos processos são.
  var memoria: UInt64 = 0
  var processos = 0
  /// A caixa de escrita (compose) está à vista neste painel.
  var composeVisivel = false
  /// Personagem do agente, de quem ele é filho e a tarefa em poucas palavras (espelham o nó salvo).
  var persona: Persona? { didSet { no.persona = persona } }
  var pai: String? { didSet { no.pai = pai } }
  var maestro = false { didSet { no.maestro = maestro } }
  var tarefa: String? { didSet { no.tarefa = tarefa } }
  /// Vista de conversa (chat) por cima do terminal.
  var conversa = false { didSet { if conversa != oldValue { caixa?.atualizarConversa() } } }
  /// Portas TCP em escuta abertas por este painel (servidores que ele subiu).
  var portas: [Int] = []

  @ObservationIgnored private(set) var view: TerminalView?
  @ObservationIgnored private(set) var caixa: CaixaPainel?
  @ObservationIgnored private var sessao: Sessao?
  @ObservationIgnored var ultimaEntrada = Date.distantPast
  @ObservationIgnored var inicioAtividade = Date()
  @ObservationIgnored var inicioLinha: (linha: Int, coluna: Int)?
  @ObservationIgnored var comandoAtual = ""
  @ObservationIgnored var inicioComando: Date?
  @ObservationIgnored var ultimoResultado: ResultadoComando?
  @ObservationIgnored var aoTerminarComando: [(ResultadoComando) -> Void] = []
  @ObservationIgnored var ultimoSino = Date.distantPast
  @ObservationIgnored let leitor = LeitorSaida()
  /// Só para testes (`orion depurar estado`): congela o estado mostrado.
  @ObservationIgnored var estadoFixo: EstadoPainel?
  @ObservationIgnored private var tamanhoPendente: (cols: Int, linhas: Int)?
  @ObservationIgnored private var envioTamanho: DispatchWorkItem?
  /// Rascunho do compose (texto, anexos, menções) — criado quando alguém escreve.
  @ObservationIgnored lazy var rascunho = Rascunho()
  /// Altura que o compose pede (a view informa; o layout da caixa usa).
  @ObservationIgnored var alturaCompose: CGFloat = 0 { didSet { if alturaCompose != oldValue { caixa?.needsLayout = true } } }
  /// Mensagens mandadas pelo compose, com a linha do terminal em que cada uma entrou (para a conversa).
  @ObservationIgnored var enviadas: [Conversa.Enviada] = []
  @ObservationIgnored var iniciadoEm = Date()
  @ObservationIgnored private var pidNomeado: pid_t = -1

  init(no: No, aba: Aba, loja: Loja) {
    self.id = no.id
    self.no = no
    self.aba = aba
    self.loja = loja
    self.cwd = no.cwd
    self.zoom = no.zoom
    self.marca = no.marca
    self.persona = no.persona
    self.pai = no.pai
    self.maestro = no.maestro
    self.tarefa = no.tarefa
  }

  /// pid do shell deste painel (raiz da árvore de processos), se estiver rodando.
  var pidShell: pid_t? { sessao.flatMap { $0.pid > 0 && !$0.encerrada ? $0.pid : nil } }

  var tipo: String { no.kind }
  var agente: String? { Ferramenta.eh(processo) && !ocioso ? processo : nil }
  /// A ferramenta ("claude", "codex", "gemini") se este painel é (ou foi aberto como) um agente; nil para terminal comum.
  var tipoAgente: String? {
    if let a = agente { return a }
    if estadoFixo != nil && tipo != "shell" { return tipo }
    if tipo != "shell" && (!iniciado || !vivo || estado == .dormindo) { return tipo }
    if !iniciado, Ferramenta.eh(no.ultimoProcesso) { return no.ultimoProcesso }
    return nil
  }

  private func calcularEstado() -> EstadoPainel {
    if !iniciado { return .dormindo }
    if !vivo { return .saiu }
    if progresso != nil || ocupado { return agente != nil ? .trabalhando : .rodando }
    if !ocioso { return agente != nil ? .esperando : .rodando }
    return .pronto
  }

  func atualizarEstado() {
    if estadoFixo != nil { return }
    let novo = calcularEstado()
    if novo != estado {
      let antes = estado
      estado = novo; desde = Date()
      if antes == .trabalhando, novo == .esperando || novo == .pronto {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.lerPrevia() }
      }
      // Voltou a trabalhar: a marca "revisar"/"concluído" já não vale.
      if novo == .trabalhando, marca != nil { marca = nil; no.marca = nil; loja.salvarDepois() }
    }
    // Um terminal que virou agente (alguém digitou `claude`) ganha o seu personagem.
    if persona == nil, tipoAgente != nil { persona = loja.novaPersona() }
    atualizarCompose()
  }

  func lerPrevia() {
    guard let texto = baloes().last(where: { !$0.meu })?.texto else { return }
    let linha = texto.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
      .last { $0.count > 3 && !$0.allSatisfy { "─━═-_>❯⏵·•*│ ".contains($0) } } ?? ""
    let curta = String(linha.prefix(160))
    if curta != previa { previa = curta }
  }

  /// O compose aparece nos agentes (ajuste "agentes"), em todos ("sempre") ou só quando chamado
  /// (⌘E); abrir ou fechar à mão vale para este painel até ele ser fechado.
  func atualizarCompose() {
    let modo = loja.ajustes.compose
    let quer = rascunho.manual ?? (modo == "sempre" || (modo == "agentes" && tipoAgente != nil))
    if quer != composeVisivel {
      composeVisivel = quer
      caixa?.needsLayout = true
    }
  }

  /// ⌘E: leva o teclado para o compose (abrindo-o se preciso) ou de volta para o terminal.
  func alternarFocoDoCompose() {
    if composeVisivel, let c = rascunho.campo, c.window?.firstResponder === c, c.isDescendant(of: caixa ?? NSView()) {
      if let v = view { v.window?.makeFirstResponder(v) }
      return
    }
    if !composeVisivel { rascunho.manual = true; atualizarCompose() }
    focarCompose()
  }

  func focarCompose() {
    caixa?.layoutSubtreeIfNeeded()
    DispatchQueue.main.async { [weak self] in
      guard let self, let c = self.caixa?.campoDoCompose else { return }
      c.window?.makeFirstResponder(c)
    }
  }

  /// ⇧⌘E: mostra ou esconde o compose deste painel.
  func alternarCompose() {
    rascunho.manual = !composeVisivel
    atualizarCompose()
    if composeVisivel { focarCompose() } else if let v = view { v.window?.makeFirstResponder(v) }
  }

  /// Interrompe o que está rodando: Esc para o Claude (é o que ele entende como "pare"), ⌃C para o resto.
  func interromper() {
    guard vivo else { return }
    escrever(agente == "claude" || agente == "gemini" ? "\u{1b}" : "\u{03}")
  }
  /// O que mostrar como ícone: o agente rodando, o tipo da aba, ou o programa em primeiro plano.
  var programa: String {
    if let a = agente { return a }
    if !iniciado && tipo != "shell" { return tipo }
    return ocioso ? "shell" : processo
  }

  var titulo: String {
    // Agente: o título que ele mesmo manda (a tarefa em curso), senão a tarefa da primeira
    // mensagem; sem nenhum dos dois, "Nova conversa".
    if !ocioso, let t = Nomes.tituloUtil(tituloOSC, cwd: cwd) { return t }
    if let ag = tipoAgente {
      if let t = tarefa, !t.isEmpty { return t }
      return persona == nil ? nomeLongoFerramenta(ag) : "Nova conversa"
    }
    if !ocioso && !processo.isEmpty { return processo }
    return Loja.nomeDaPasta(cwd)
  }

  // MARK: - Terminal

  func garantirCaixa() -> CaixaPainel {
    if let c = caixa { return c }
    let v = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500), font: loja.fonte(zoom: zoom))
    v.terminalDelegate = self
    configurar(v)
    // Arrastar arquivos e imagens é com a caixa do painel (compose nos agentes, caminho no shell).
    v.unregisterDraggedTypes()
    view = v
    let c = CaixaPainel(painel: self, terminal: v)
    caixa = c
    return c
  }

  /// Abre o shell/agente sem o painel estar na tela (agente criado em segundo plano pelo CLI
  /// ou acordado pelo quadro). Usa o tamanho da área de terminais para não redimensionar depois.
  func acordar() {
    guard !iniciado else { return }
    let c = garantirCaixa()
    if c.window == nil {
      let tam = loja.tamanhoDaArea?() ?? NSSize(width: 900, height: 600)
      c.frame = NSRect(origin: .zero, size: NSSize(width: max(300, tam.width), height: max(200, tam.height)))
      c.layoutSubtreeIfNeeded()
    }
    if !iniciado { iniciar() }
  }

  func configurar(_ v: TerminalView) {
    let a = loja.ajustes
    let t = loja.tema
    v.installColors(t.coresTerminal)
    v.nativeForegroundColor = t.corTexto
    v.nativeBackgroundColor = t.corFundo.withAlphaComponent(0)
    v.caretColor = t.corAcento
    v.selectedTextBackgroundColor = t.corAcento.withAlphaComponent(t.claro ? 0.26 : 0.32)
    v.optionAsMetaKey = a.optionMeta
    v.scrollerStyle = .overlay
    v.useBrightColors = false
    v.bellStyle = .none
    v.linkHighlightMode = .hoverWithModifier
    v.changeScrollback(a.rolagem)
    v.font = loja.fonte(zoom: zoom)
    let estilo: CursorStyle = a.cursor == "bloco" ? .steadyBlock : a.cursor == "sublinhado" ? .steadyUnderline : .steadyBar
    v.setCursorStyle(estilo)
    if a.gpu != v.isUsingMetalRenderer { try? v.setUseMetal(a.gpu) }
    Painel.fixarCamadas(v)
  }

  /// Texto nítido ao redimensionar: enquanto o terminal não redesenha no tamanho novo, a camada
  /// antiga fica ancorada no canto de cima à esquerda, no tamanho real — nunca esticada (era o
  /// que deixava a letra borrada durante o arrasto da janela e das divisões).
  static func fixarCamadas(_ v: NSView) {
    v.layerContentsPlacement = .topLeft
    v.layer?.contentsGravity = .topLeft
    for s in v.subviews where !(s is NSScroller) {
      s.layerContentsPlacement = .topLeft
      s.layer?.contentsGravity = .topLeft
      // Duas superfícies de desenho em vez de três: uma tela de terminal a menos na memória de vídeo
      // por painel (um terminal não precisa da terceira, que só serve a animação contínua).
      if let metal = s.layer as? CAMetalLayer, metal.maximumDrawableCount > 2 { metal.maximumDrawableCount = 2 }
    }
  }

  /// Arquivos ou imagem soltos no painel (ou colados com o terminal em foco). Num agente vão para
  /// o compose (imagem como anexo, o resto como @caminho); num shell, o caminho é digitado.
  @discardableResult
  func receber(_ pb: NSPasteboard) -> Bool {
    let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    let tipos = pb.types ?? []
    let temImagem = tipos.contains(.png) || tipos.contains(.tiff)
    guard !urls.isEmpty || temImagem else { return false }
    if tipoAgente == nil {
      guard !urls.isEmpty, vivo else { return false }
      escrever(urls.map { Compose.entreAspas($0.path) }.joined(separator: " ") + " ")
      return true
    }
    if !urls.isEmpty { anexar(caminhos: urls.map(\.path)) }
    else if let caminho = Compose.salvarImagem(de: pb) {
      rascunho.anexar(Anexo(tipo: .imagem, valor: caminho, rotulo: "imagem colada"))
      if !composeVisivel { rascunho.manual = true; atualizarCompose() }
    }
    focarCompose()
    return true
  }

  func aplicarAjustes() {
    if let v = view { configurar(v); v.needsDisplay = true }
    atualizarCompose()
    caixa?.atualizarVisual()
    caixa?.needsLayout = true
  }

  func mudarZoom(_ delta: Double) {
    zoom = delta == 0 ? 0 : min(12, max(-6, zoom + delta))
    no.zoom = zoom
    view?.font = loja.fonte(zoom: zoom)
    loja.salvarDepois()
  }

  // MARK: - Sessão

  func iniciar(comando forcado: String? = nil) {
    guard let v = view else { return }
    iniciado = true
    iniciadoEm = Date()
    vivo = true
    codigoSaida = nil
    let dim = v.terminalInputStateSnapshot()?.dimensions
    let s = Sessao(id: id)
    let env = loja.ambiente(aba: aba)
    let comando = forcado ?? no.comando
    no.comando = (no.kind == "shell") ? nil : loja.comandoDoTipo(no.kind)   // retomar só na primeira vez
    let lancamento = Shell.preparar(shell: loja.ajustes.shell.isEmpty ? nil : loja.ajustes.shell,
                                    comando: comando, extra: env, idAba: id)
    leitor.aoEvento = { [weak self] ev in DispatchQueue.main.async { self?.evento(ev) } }
    s.aoReceber = { [weak self, weak v] bytes in
      v?.feed(byteArray: bytes)
      self?.leitor.ler(bytes)
    }
    s.aoSair = { [weak self] codigo in self?.saiu(codigo) }
    var dir = (cwd as NSString).expandingTildeInPath
    var ehDir: ObjCBool = false
    if !FileManager.default.fileExists(atPath: dir, isDirectory: &ehDir) || !ehDir.boolValue { dir = NSHomeDirectory() }
    do {
      try s.iniciar(executavel: lancamento.executavel, argv: lancamento.argv, env: lancamento.env, cwd: dir,
                    cols: dim?.cols ?? 100, linhas: dim?.rows ?? 30)
      sessao = s
    } catch {
      vivo = false
      v.feed(text: "\r\n\u{1b}[31mNão consegui abrir o shell: \(error.localizedDescription)\u{1b}[0m\r\n")
    }
    atualizarEstado()
  }

  func reiniciar(comando: String? = nil) {
    sessao?.aoSair = nil
    sessao?.matar()
    sessao = nil
    view?.resetToInitialState()
    iniciar(comando: comando)
  }

  func escrever(_ texto: String) {
    ultimaEntrada = Date()
    sessao?.escrever(Data(texto.utf8))
  }

  func encerrar() {
    envioTamanho?.cancel()
    sessao?.aoSair = nil
    sessao?.matar()
    sessao = nil
    vivo = false
    caixa?.removeFromSuperview()
  }

  private func saiu(_ codigo: Int32) {
    vivo = false
    codigoSaida = codigo
    noPrompt = false
    ocupado = false
    progresso = nil
    sessao = nil
    atualizarEstado()
    if codigo == 0 { loja.fecharPainel(self, confirmado: true); return }
    view?.feed(text: "\r\n\u{1b}[2m[processo encerrado · código \(codigo) · Enter reinicia · ⌘W fecha]\u{1b}[0m\r\n")
  }

  /// Atualização periódica (1 s) do processo em primeiro plano e da pasta.
  func vigiar() {
    guard let s = sessao, let p = s.pidAtivo() else { return }
    let shellNoTopo = p == s.pid
    // O nome do processo só é relido quando o processo em primeiro plano muda (ler os argumentos
    // de um processo a cada segundo, por painel, era o que mais custava no tique).
    if p != pidNomeado { pidNomeado = p; let nome = Sessao.nomeDoProcesso(p); if processo != nome { processo = nome } }
    let novaPasta = (shellNoTopo ? s.pastaAtual() : nil) ?? cwd
    if ocioso != shellNoTopo { ocioso = shellNoTopo; if shellNoTopo { tituloOSC = ""; progresso = nil } }
    if shellNoTopo && novaPasta != cwd { cwd = novaPasta; no.cwd = novaPasta; atualizarGit() }
    no.ultimoProcesso = shellNoTopo ? "" : processo
    // Atividade: saída recente = ocupado.
    let ultima = leitor.ultimaSaida
    let agora = Date()
    let estava = ocupado
    let ativo = agora.timeIntervalSince(ultima) < 2.0 && ultima.timeIntervalSince(ultimaEntrada) > 0.4 && !shellNoTopo
    if ativo && !estava { inicioAtividade = ultima }
    if ativo != estava {
      ocupado = ativo
      if !ativo { loja.parouDeTrabalhar(self, durou: ultima.timeIntervalSince(inicioAtividade)) }
    }
    atualizarEstado()
  }

  func atualizarGit() {
    let dir = cwd
    DispatchQueue.global(qos: .utility).async {
      let g = Armazem.gitInfo(dir)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.cwd == dir else { return }
        self.branch = g["branch"] as? String ?? ""
        self.alterados = g["alterados"] as? Int ?? 0
      }
    }
  }

  // MARK: - Integração com o shell (eventos do LeitorSaida)

  private func evento(_ ev: LeitorSaida.Evento) {
    switch ev {
    case .prompt:
      noPrompt = true
      inicioLinha = nil
    case .comandoComecou(let cmd):
      noPrompt = false
      inicioLinha = nil
      if !cmd.isEmpty { comandoAtual = cmd }
      inicioComando = Date()
      loja.sugestoes.fechar()
    case .comandoTerminou(let codigo, let saida):
      let inicio = inicioComando ?? Date()
      let r = ResultadoComando(comando: comandoAtual, codigo: codigo, saida: saida, duracao: Date().timeIntervalSince(inicio))
      if inicioComando != nil {
        ultimoResultado = r
        let esperas = aoTerminarComando
        aoTerminarComando = []
        esperas.forEach { $0(r) }
        loja.comandoTerminou(self, r)
        if !comandoAtual.isEmpty { loja.sugestoes.lembrar(comandoAtual) }
      }
      inicioComando = nil
      comandoAtual = ""
    case .comando(let cmd):
      comandoAtual = cmd
    case .notificacao(let titulo, let corpo):
      loja.notificacaoDoPrograma(self, titulo: titulo, corpo: corpo)
    case .progresso(let pct):
      progresso = pct
      atualizarEstado()
    }
  }

  // MARK: - Linha digitada (autocomplete)

  /// Texto entre o fim do prompt e o cursor, lido da tela.
  func linhaAtual() -> String? {
    guard noPrompt, let v = view, let ini = inicioLinha,
          let snap = v.terminalContentSnapshot(region: .history(maximumScrollbackRows: 0)) else { return nil }
    let yCursor = snap.cursorRow, xCursor = snap.cursorColumn
    guard yCursor >= ini.linha, yCursor - ini.linha < 8 else { return nil }
    var texto = ""
    for row in snap.rows where row.absoluteRow >= ini.linha && row.absoluteRow <= yCursor {
      var celulas = row.cells
      if row.absoluteRow == yCursor { celulas = Array(celulas.prefix(xCursor)) }
      if row.absoluteRow == ini.linha { celulas = Array(celulas.dropFirst(min(ini.coluna, celulas.count))) }
      texto += celulas.map { $0.text.isEmpty ? " " : $0.text }.joined()
    }
    return texto
  }

  func marcarInicioDaLinha() {
    guard noPrompt, inicioLinha == nil, let snap = view?.terminalContentSnapshot(region: .history(maximumScrollbackRows: 0)) else { return }
    inicioLinha = (snap.cursorRow, snap.cursorColumn)
  }

  /// Posição do cursor em pontos, relativa à view do terminal (origem no topo).
  func posicaoDoCursor() -> NSPoint? {
    guard let v = view, let s = v.terminalInputStateSnapshot() else { return nil }
    let st = v.terminalStateSnapshot()
    let largura = v.bounds.width / CGFloat(max(1, s.dimensions.cols))
    let altura = v.bounds.height / CGFloat(max(1, s.dimensions.rows))
    return NSPoint(x: CGFloat(st.cursor.col) * largura, y: CGFloat(st.cursor.row + 1) * altura)
  }

  /// Texto da tela (e da rolagem, se pedido) para o CLI `orion ler`.
  func texto(linhas: Int?) -> String {
    guard let v = view else { return "" }
    let regiao: TerminalContentRegion = linhas.map { .history(maximumScrollbackRows: max(0, $0)) } ?? .all
    guard let snap = v.terminalContentSnapshot(region: regiao) else { return "" }
    var out: [String] = []
    for r in snap.rows {
      let t = r.text.replacingOccurrences(of: "\u{0}", with: " ").replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
      if r.isWrapped, !out.isEmpty { out[out.count - 1] += t } else { out.append(t) }
    }
    while out.last?.isEmpty == true { out.removeLast() }
    if let n = linhas, out.count > n + (snap.dimensions.rows) { out = Array(out.suffix(n + snap.dimensions.rows)) }
    return out.joined(separator: "\n")
  }

  // MARK: - TerminalViewDelegate

  /// O tamanho novo só vai para o PTY (SIGWINCH) quando para de mudar: arrastar a janela, uma
  /// divisão ou a barra lateral gera dezenas de tamanhos por segundo, e cada um faria o programa
  /// (Claude, vim, htop…) redesenhar a tela inteira.
  func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
    tamanhoPendente = (newCols, newRows)
    envioTamanho?.cancel()
    let aoVivo = loja.arrastando || source.inLiveResize
    let w = DispatchWorkItem { [weak self] in
      guard let self, let t = self.tamanhoPendente else { return }
      self.tamanhoPendente = nil
      self.sessao?.redimensionar(cols: t.cols, linhas: t.linhas)
    }
    envioTamanho = w
    DispatchQueue.main.asyncAfter(deadline: .now() + (aoVivo ? 0.12 : 0.03), execute: w)
  }

  func setTerminalTitle(source: TerminalView, title: String) {
    tituloOSC = title
  }

  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
    guard var d = directory, !d.isEmpty else { return }
    if d.hasPrefix("file://"), let u = URL(string: d) { d = u.path }
    if d != cwd { cwd = d; no.cwd = d; atualizarGit(); loja.salvarDepois() }
  }

  func send(source: TerminalView, data: ArraySlice<UInt8>) {
    if !vivo {
      if data.contains(13) && iniciado { reiniciar() }
      return
    }
    ultimaEntrada = Date()
    if noPrompt { marcarInicioDaLinha() }
    sessao?.escrever(Data(data))
    loja.sugestoes.digitou(self, Array(data))
  }

  func scrolled(source: TerminalView, position: Double) { loja.sugestoes.fechar() }

  func requestOpenLink(source: TerminalView, request: TerminalLinkRequest) {
    guard let u = URL(string: request.link), let esquema = u.scheme?.lowercased(),
          ["http", "https", "file", "mailto"].contains(esquema) else { return }
    NSWorkspace.shared.open(u)
  }

  func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
    if let u = URL(string: link) { NSWorkspace.shared.open(u) }
  }

  func bell(source: TerminalView) { loja.sino(self) }

  func clipboardCopy(source: TerminalView, content: Data) {
    if let s = String(data: content, encoding: .utf8) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(s, forType: .string)
    }
  }

  func clipboardRead(source: TerminalView) -> Data? {
    NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
  }

  func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
  func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
    if noPrompt { loja.sugestoes.agendar(self) }
  }
}

/// Lê a saída bruta do PTY (na fila de leitura) procurando as marcas OSC da integração e
/// guardando a saída de cada comando. Barato: só olha bytes ESC.
final class LeitorSaida {
  enum Evento {
    case prompt
    case comandoComecou(String)
    case comandoTerminou(Int?, String)
    case comando(String)
    case notificacao(String?, String)
    case progresso(Int?)
  }

  var aoEvento: ((Evento) -> Void)?
  private let trava = NSLock()
  private var _ultimaSaida = Date.distantPast
  var ultimaSaida: Date { trava.lock(); defer { trava.unlock() }; return _ultimaSaida }

  private enum Estado { case texto, esc, osc, oscEsc }
  private var estado = Estado.texto
  private var osc: [UInt8] = []
  private var capturando = false
  private var captura: [UInt8] = []
  private let limiteCaptura = 512 * 1024

  // Posições dentro do bloco que está sendo lido: a captura da saída de um comando é exata ao
  // byte, mesmo quando o começo (133;C), a saída e o fim (133;D) chegam no mesmo bloco — o caso
  // de comandos instantâneos como `echo`.
  private var inicioCaptura = 0      // de onde copiar neste bloco
  private var inicioOSC = 0          // onde começou a sequência OSC em andamento
  private var cursor = 0

  func ler(_ bytes: ArraySlice<UInt8>) {
    trava.lock(); _ultimaSaida = Date(); trava.unlock()
    inicioCaptura = bytes.startIndex
    if estado != .texto { inicioOSC = bytes.startIndex }   // OSC começou no bloco anterior
    var i = bytes.startIndex
    let fim = bytes.endIndex
    while i < fim {
      let b = bytes[i]
      cursor = i
      switch estado {
      case .texto:
        if b == 0x1b { estado = .esc; inicioOSC = i }
      case .esc:
        if b == 0x5d { estado = .osc; osc.removeAll(keepingCapacity: true) } else { estado = .texto }
      case .osc:
        if b == 0x07 { fimOSC(bytes); estado = .texto }
        else if b == 0x1b { estado = .oscEsc }
        else if osc.count < 4096 { osc.append(b) }
      case .oscEsc:
        if b == 0x5c { fimOSC(bytes) }
        estado = .texto
      }
      i += 1
    }
    if capturando { guardar(bytes[inicioCaptura..<fim]) }
  }

  private func guardar(_ pedaco: ArraySlice<UInt8>) {
    guard !pedaco.isEmpty else { return }
    captura.append(contentsOf: pedaco)
    if captura.count > limiteCaptura { captura.removeFirst(captura.count - limiteCaptura) }
  }

  private func fimOSC(_ bytes: ArraySlice<UInt8>) {
    let s = String(decoding: osc, as: UTF8.self)
    guard let i = s.firstIndex(of: ";") else { return }
    let codigo = s[..<i], resto = String(s[s.index(after: i)...])
    switch codigo {
    case "133":
      if resto.hasPrefix("A") { aoEvento?(.prompt) }
      else if resto.hasPrefix("C") {
        capturando = true
        captura.removeAll(keepingCapacity: true)
        inicioCaptura = cursor + 1          // a saída começa logo depois desta marca
        aoEvento?(.comandoComecou(""))
      } else if resto.hasPrefix("D") {
        let codigo = resto.split(separator: ";").dropFirst().first.flatMap { Int($0) }
        if capturando, inicioOSC > inicioCaptura { guardar(bytes[inicioCaptura..<inicioOSC]) }   // até antes da marca D
        let saida = capturando ? LeitorSaida.limpar(captura) : ""
        capturando = false
        captura.removeAll()
        aoEvento?(.comandoTerminou(codigo, saida))
      }
    case "633":
      if resto.hasPrefix("E;") { aoEvento?(.comando(String(resto.dropFirst(2)).trimmingCharacters(in: .whitespaces))) }
    case "9":
      if resto.hasPrefix("4;") {
        let p = resto.split(separator: ";")
        let est = p.count > 1 ? Int(p[1]) ?? 0 : 0
        aoEvento?(.progresso(est == 0 ? nil : (p.count > 2 ? Int(p[2]) ?? 0 : 0)))
      } else { aoEvento?(.notificacao(nil, resto)) }
    case "777":
      let p = resto.split(separator: ";", maxSplits: 2).map(String.init)
      if p.first == "notify" { aoEvento?(.notificacao(p.count > 1 ? p[1] : nil, p.count > 2 ? p[2] : "")) }
    default: break
    }
  }

  /// Tira sequências de escape e aplica \r / backspace para virar texto legível.
  static func limpar(_ bytes: [UInt8]) -> String {
    var out: [UInt8] = []
    var linha: [UInt8] = []
    var i = 0
    let n = bytes.count
    func fechaLinha() { out.append(contentsOf: linha); out.append(10); linha.removeAll() }
    while i < n {
      let b = bytes[i]
      if b == 0x1b {
        i += 1
        guard i < n else { break }
        let c = bytes[i]
        if c == 0x5b {           // CSI
          i += 1
          while i < n && !(0x40...0x7e).contains(bytes[i]) { i += 1 }
        } else if c == 0x5d {    // OSC
          i += 1
          while i < n && bytes[i] != 0x07 && !(bytes[i] == 0x1b && i + 1 < n && bytes[i + 1] == 0x5c) { i += 1 }
          if i < n && bytes[i] == 0x1b { i += 1 }
        }
        i += 1
        continue
      }
      if b == 10 { fechaLinha() }
      else if b == 13 { if i + 1 < n && bytes[i + 1] == 10 { } else { linha.removeAll() } }
      else if b == 8 { if !linha.isEmpty { linha.removeLast() } }
      else if b >= 0x20 || b == 9 { linha.append(b) }
      i += 1
    }
    out.append(contentsOf: linha)
    return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// A caixa de um painel: um cartão com cabeçalho (SwiftUI), terminal (AppKit) e, embaixo, o
/// compose. O cartão tem fundo próprio, borda e sombra — é o que separa um terminal do outro
/// e da janela.
final class CaixaPainel: NSView {
  let painel: Painel
  let terminal: TerminalView
  let cabecalho: NSHostingView<CabecalhoPainel>
  /// Conteúdo recortado nos cantos arredondados (a sombra fica fora, na camada da própria caixa).
  private let conteudo = NSView()
  private let sombra = CALayer()
  private var compose: NSHostingView<ComposeHospedado>?
  private var mencoes: NSHostingView<ListaMencoes>?
  private var conversa: NSHostingView<ConversaView>?
  private var estadoConversa: EstadoConversa?
  private var soltando = false { didSet { if soltando != oldValue { atualizarVisual() } } }
  static var alturaCabecalho: CGFloat { (48 * max(1, Aparencia.atual.escala)).rounded() }

  @MainActor init(painel: Painel, terminal: TerminalView) {
    self.painel = painel
    self.terminal = terminal
    self.cabecalho = NSHostingView(rootView: CabecalhoPainel(painel: painel))
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    sombra.shadowOffset = CGSize(width: 0, height: -3)
    sombra.shadowColor = NSColor.black.cgColor
    layer?.addSublayer(sombra)
    conteudo.wantsLayer = true
    conteudo.layer?.masksToBounds = true
    conteudo.layer?.cornerCurve = .continuous
    addSubview(conteudo)
    conteudo.addSubview(cabecalho)
    conteudo.addSubview(terminal)
    registerForDraggedTypes([.fileURL, .png, .tiff])
    atualizarVisual()
  }

  // MARK: Arrastar arquivos e imagens para o painel

  private func aceita(_ info: NSDraggingInfo) -> Bool {
    let t = info.draggingPasteboard.types ?? []
    return t.contains(.fileURL) || t.contains(.png) || t.contains(.tiff)
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard aceita(sender) else { return [] }
    soltando = true
    return .copy
  }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { aceita(sender) ? .copy : [] }
  override func draggingExited(_ sender: NSDraggingInfo?) { soltando = false }
  override func draggingEnded(_ sender: NSDraggingInfo) { soltando = false }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    soltando = false
    return MainActor.assumeIsolated {
      painel.loja.focar(painel, teclado: false)
      return painel.receber(sender.draggingPasteboard)
    }
  }

  // MARK: Vista de conversa (por cima do terminal)

  @MainActor func atualizarConversa() {
    if painel.conversa {
      if conversa == nil {
        let e = EstadoConversa()
        let v = NSHostingView(rootView: ConversaView(painel: painel, estado: e))
        v.sizingOptions = []
        conteudo.addSubview(v, positioned: .above, relativeTo: terminal)
        conversa = v
        estadoConversa = e
        e.comecar(painel)
      }
      terminal.isHidden = true
    } else {
      estadoConversa?.parar()
      conversa?.removeFromSuperview()
      conversa = nil
      estadoConversa = nil
      terminal.isHidden = false
    }
    needsLayout = true
  }

  required init?(coder: NSCoder) { fatalError() }

  var destacado = false { didSet { if destacado != oldValue { atualizarVisual() } } }
  /// A aba tem mais de um painel à vista (o ativo ganha destaque, os outros recuam).
  var comBorda = false { didSet { if comBorda != oldValue { atualizarVisual() } } }

  /// O campo de texto do compose desta caixa (para dar o foco).
  var campoDoCompose: CampoTexto? {
    guard let c = compose else { return nil }
    func achar(_ v: NSView) -> CampoTexto? {
      if let t = v as? CampoTexto { return t }
      for s in v.subviews { if let t = achar(s) { return t } }
      return nil
    }
    return achar(c)
  }

  /// Cores, borda, raio e sombra do cartão, pelo tema e pelos ajustes em uso.
  @MainActor func atualizarVisual() {
    let loja = painel.loja
    let t = loja.tema
    let raio = CGFloat(loja.ajustes.raio)
    let o = loja.opacidade
    conteudo.layer?.cornerRadius = raio
    // O cartão soma um pouco de cor à da janela: o terminal fica mais legível que as barras em
    // volta, mas continua deixando ver o fundo quando a janela é translúcida.
    let alfa: CGFloat = o >= 0.995 ? 1 : max(0.10, o * 0.55)
    conteudo.layer?.backgroundColor = t.corFundo.withAlphaComponent(alfa).cgColor
    let ativo = comBorda && destacado
    conteudo.layer?.borderWidth = soltando ? 2 : 1
    let base: NSColor = soltando ? t.corAcento : (t.claro ? .black : .white)
    conteudo.layer?.borderColor = (ativo || soltando ? t.corAcento.withAlphaComponent(soltando ? 0.9 : (t.claro ? 0.55 : 0.5))
                                         : base.withAlphaComponent(t.claro ? 0.11 : (o < 0.5 ? 0.14 : 0.09))).cgColor
    let comSombra = loja.ajustes.sombras
    sombra.isHidden = !comSombra
    sombra.shadowOpacity = t.claro ? (ativo || !comBorda ? 0.16 : 0.09) : (ativo || !comBorda ? 0.5 : 0.3)
    sombra.shadowRadius = ativo || !comBorda ? 12 : 7
    terminal.alphaValue = comBorda && !destacado ? 0.8 : 1
    needsLayout = true
  }

  private var quadroPendente: NSRect?
  private var aplicarAgendado = false

  override func layout() {
    super.layout()
    conteudo.frame = bounds
    // Sombra só por fora do cartão: o fundo é translúcido e não pode escurecer por dentro.
    let raio = conteudo.layer?.cornerRadius ?? 12
    if !sombra.isHidden {
      CATransaction.begin(); CATransaction.setDisableActions(true)
      sombra.frame = bounds
      let forma = CGPath(roundedRect: bounds, cornerWidth: raio, cornerHeight: raio, transform: nil)
      sombra.shadowPath = forma
      let mascara = (sombra.mask as? CAShapeLayer) ?? CAShapeLayer()
      let fora = CGMutablePath()
      fora.addRect(bounds.insetBy(dx: -48, dy: -48))
      fora.addPath(forma)
      mascara.path = fora
      mascara.fillRule = .evenOdd
      mascara.frame = bounds
      sombra.mask = mascara
      CATransaction.commit()
    }
    let h = CaixaPainel.alturaCabecalho
    let m = CGFloat(painel.loja.ajustes.margem)
    cabecalho.frame = NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
    // Compose embaixo (só existe quando está à vista).
    var hc: CGFloat = 0
    if painel.composeVisivel {
      if compose == nil {
        let c = NSHostingView(rootView: ComposeHospedado(painel: painel))
        c.sizingOptions = []
        conteudo.addSubview(c)
        compose = c
      }
      hc = min(max(painel.alturaCompose, 46), max(46, bounds.height * 0.5)).rounded(.up)
      compose?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: hc)
    } else if let c = compose {
      c.removeFromSuperview()
      compose = nil
      painel.alturaCompose = 0
    }
    // Sempre em pixels inteiros: um terminal em meia posição desenha a letra borrada.
    let alvo = backingAlignedRect(NSRect(x: m, y: hc + m * 0.4, width: max(10, bounds.width - m * 2 + 4), height: max(10, bounds.height - h - hc - m * 0.6)),
                                  options: .alignAllEdgesNearest)
    conversa?.frame = NSRect(x: 0, y: hc, width: bounds.width, height: max(10, bounds.height - h - hc))
    if painel.loja.arrastando && painel.iniciado {
      // Arrastando uma divisão ou a barra lateral: o terminal refaz as linhas (reflow) no máximo
      // ~20 vezes por segundo, não a cada pixel. O topo fica alinhado ao cabeçalho enquanto isso.
      quadroPendente = alvo
      terminal.setFrameOrigin(NSPoint(x: alvo.minX, y: alvo.maxY - terminal.frame.height))
      if !aplicarAgendado {
        aplicarAgendado = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.aplicarQuadro() }
      }
    } else {
      quadroPendente = nil
      if terminal.frame != alvo { terminal.frame = alvo }
    }
    posicionarMencoes()
    if !painel.iniciado && bounds.width > 50 {
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.painel.iniciado, self.window != nil else { return }
        self.painel.iniciar()
      }
    }
  }

  private func aplicarQuadro() {
    aplicarAgendado = false
    guard let q = quadroPendente else { return }
    quadroPendente = nil
    if terminal.frame != q { terminal.frame = q }
  }

  /// Fim de um arrasto: aplica o tamanho final na hora.
  func assentar() { needsLayout = true }

  // MARK: Lista de menções (@) por cima do terminal, colada ao compose

  @MainActor func atualizarMencoes() {
    let r = painel.rascunho
    let aqui = r.mencaoAberta && (r.campo.map { $0.isDescendant(of: self) } ?? false)
    if aqui {
      if mencoes == nil {
        let v = NSHostingView(rootView: ListaMencoes(painel: painel))
        addSubview(v)
        mencoes = v
      }
      posicionarMencoes()
      DispatchQueue.main.async { [weak self] in self?.posicionarMencoes() }   // depois de o SwiftUI medir a lista nova
    } else if let v = mencoes {
      v.removeFromSuperview()
      mencoes = nil
    }
  }

  private func posicionarMencoes() {
    guard let v = mencoes, let c = compose else { return }
    let largura = min(460, bounds.width - 20)
    let alt = min(v.fittingSize.height, max(80, bounds.height - c.frame.height - 60))
    v.frame = NSRect(x: 10, y: c.frame.maxY - 4, width: largura, height: alt)
  }

  override func mouseDown(with event: NSEvent) {
    painel.loja.focar(painel)
    super.mouseDown(with: event)
  }

  /// Sino com o painel à vista: a borda pisca na cor de destaque.
  @MainActor func piscar() {
    let anim = CABasicAnimation(keyPath: "borderWidth")
    anim.fromValue = 2.5; anim.toValue = 1; anim.duration = 0.4
    let cor = CABasicAnimation(keyPath: "borderColor")
    cor.fromValue = painel.loja.tema.corAcento.cgColor; cor.toValue = conteudo.layer?.borderColor; cor.duration = 0.4
    conteudo.layer?.add(anim, forKey: "piscar")
    conteudo.layer?.add(cor, forKey: "piscarCor")
  }
}
