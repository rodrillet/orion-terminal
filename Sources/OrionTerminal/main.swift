import Cocoa
import SwiftUI
import SwiftTerm
import UserNotifications

// Orion Terminal — app nativo: AppKit + SwiftUI + SwiftTerm, PTY próprio (Pty.swift).

/// Desfoque do que está atrás de uma janela transparente, com raio ajustável. É a chamada do
/// servidor de janelas que os terminais usam (não há equivalente público com intensidade);
/// procurada em tempo de execução — se um dia sumir, a janela só fica sem desfoque.
enum Vidro {
  private typealias Conexao = @convention(c) () -> Int32
  private typealias Desfoque = @convention(c) (Int32, Int, Int32) -> Int32
  private static let funcoes: (Conexao, Desfoque)? = {
    guard let h = dlopen(nil, RTLD_NOW), let c = dlsym(h, "CGSMainConnectionID"), let d = dlsym(h, "CGSSetWindowBackgroundBlurRadius") else { return nil }
    return (unsafeBitCast(c, to: Conexao.self), unsafeBitCast(d, to: Desfoque.self))
  }()
  static var disponivel: Bool { funcoes != nil }

  static func desfocar(_ janela: NSWindow, raio: Int) {
    guard let (conexao, desfoque) = funcoes, janela.windowNumber > 0 else { return }
    _ = desfoque(conexao(), janela.windowNumber, Int32(max(0, min(60, raio))))
  }
}

MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegado = Delegado()
  app.delegate = delegado
  app.setActivationPolicy(Armazem.semFoco ? .accessory : .regular)
  app.run()
}

final class JanelaPrincipal: NSWindow {
  override var canBecomeKey: Bool { true }
}

@MainActor
final class Delegado: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
  var janela: JanelaPrincipal!
  var vidro: NSView!
  let loja = Loja()
  var controle: Controle!
  var area: AreaTerminais!
  var janelaAjustes: NSWindow?
  var monitorTeclas: Any?
  var monitorCliques: Any?
  var observadorAparencia: NSKeyValueObservation?
  private var saindo = false

  func applicationDidFinishLaunching(_ n: Notification) {
    signal(SIGPIPE, SIG_IGN)
    Shell.instalarIntegracao()
    UNUserNotificationCenter.current().delegate = self
    montarJanela()
    montarMenu()
    loja.janela = janela
    loja.comecar()
    controle = Controle(loja: loja)
    controle.iniciar()
    Atualizador.shared.comecar(modo: loja.ajustes.atualizacao, loja: loja)
    instalarMonitores()
    // Aparência "igual ao sistema": acompanha o macOS quando ele troca entre claro e escuro.
    observadorAparencia = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          // A do app pode estar fixada por nós; o que vale é a do sistema.
          let escuro = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
          self?.loja.sistemaMudouAparencia(escuro: escuro)
        }
      }
    }
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.loja.sistemaMudouAparencia(escuro: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
      }
    }
    loja.sistemaMudouAparencia(escuro: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
    if !Armazem.semFoco { NSApp.activate(ignoringOtherApps: true) }
  }

  // MARK: - Janela

  /// Tamanho confortável para abrir: ~1100×720, nunca mais que uma fração da tela.
  static func tamanhoInicial(_ tela: NSRect) -> NSSize {
    NSSize(width: min(1100, (tela.width * 0.86).rounded()), height: min(720, (tela.height * 0.86).rounded()))
  }

  func montarJanela() {
    let tela = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let tam = Delegado.tamanhoInicial(tela)
    janela = JanelaPrincipal(contentRect: NSRect(origin: .zero, size: tam),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
    janela.titlebarAppearsTransparent = true
    janela.titleVisibility = .hidden
    janela.title = "Orion Terminal"
    janela.isOpaque = false
    janela.backgroundColor = .clear
    janela.minSize = NSSize(width: 760, height: 440)
    janela.delegate = self
    janela.collectionBehavior = [.fullScreenPrimary]
    janela.isReleasedWhenClosed = false
    // v0.4 usa um nome novo para o quadro salvo: a janela antiga podia estar gravada do tamanho da tela.
    let nomeQuadro = Armazem.desenvolvimento ? "OrionTerminalJanelaDev4" : "OrionTerminalJanela4"
    let tinhaQuadro = janela.setFrameUsingName(nomeQuadro)
    janela.setFrameAutosaveName(nomeQuadro)
    if tinhaQuadro { limitarQuadro() } else { janela.center() }

    // Sem NSVisualEffectView: o fundo é a própria janela transparente (menos uma camada de
    // composição e alguns MB a menos); o desfoque, quando há, é aplicado na janela.
    vidro = NSView()
    vidro.wantsLayer = true
    vidro.layer?.cornerRadius = 12
    vidro.layer?.masksToBounds = true

    area = AreaTerminais(loja: loja)
    let raiz = NSHostingView(rootView: JanelaRaiz(loja: loja, area: area))
    raiz.sizingOptions = []      // quem manda no tamanho é a janela, nunca o conteúdo (um diálogo alto não a estica)
    raiz.translatesAutoresizingMaskIntoConstraints = false
    vidro.addSubview(raiz)
    NSLayoutConstraint.activate([
      raiz.leadingAnchor.constraint(equalTo: vidro.leadingAnchor), raiz.trailingAnchor.constraint(equalTo: vidro.trailingAnchor),
      raiz.topAnchor.constraint(equalTo: vidro.topAnchor), raiz.bottomAnchor.constraint(equalTo: vidro.bottomAnchor),
    ])
    janela.contentView = vidro
    aplicarVidro()
    if Armazem.semFoco { janela.orderBack(nil) } else { janela.makeKeyAndOrderFront(nil) }
    posicionarSemaforo()
  }

  /// Ao abrir, a janela não ocupa a tela inteira: um quadro salvo maior que ~92% da tela volta
  /// ao tamanho inicial, centralizado. (Depois de aberta, você redimensiona como quiser.)
  func limitarQuadro() {
    guard let tela = (janela.screen ?? NSScreen.main)?.visibleFrame else { return }
    var f = janela.frame
    let grande = f.width > tela.width * 0.92 || f.height > tela.height * 0.92
    if grande {
      f.size = Delegado.tamanhoInicial(tela)
      f.origin = NSPoint(x: tela.midX - f.width / 2, y: tela.midY - f.height / 2)
    }
    // Sempre inteira dentro da tela.
    f.origin.x = min(max(f.origin.x, tela.minX), max(tela.minX, tela.maxX - f.width))
    f.origin.y = min(max(f.origin.y, tela.minY), max(tela.minY, tela.maxY - f.height))
    if f != janela.frame { janela.setFrame(f, display: false) }
  }

  /// Aparência das janelas (claro ou escuro) e o vidro: a janela é transparente de verdade — a
  /// cor do tema entra com a opacidade escolhida e o que está atrás aparece, nítido ou desfocado
  /// na medida do ajuste (o mesmo desfoque de janela que iTerm2 e Ghostty usam).
  func aplicarVidro() {
    let claro = loja.tema.claro
    let ap = NSAppearance(named: claro ? .aqua : .darkAqua)
    if janela?.appearance?.name != ap?.name {
      janela?.appearance = ap
      // Trocar a aparência refaz a barra de título: o semáforo volta ao lugar dele.
      DispatchQueue.main.async { [weak self] in self?.posicionarSemaforo() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.posicionarSemaforo() }
    }
    janelaAjustes?.appearance = ap
    guard let janela else { return }
    let opaco = loja.opacidade >= 0.995
    Vidro.desfocar(janela, raio: opaco ? 0 : Int(loja.ajustes.desfoqueRaio.rounded()))
    janela.invalidateShadow()
  }

  /// Semáforo centralizado na barra de 52 pt.
  func posicionarSemaforo() {
    guard janela != nil, !janela.styleMask.contains(.fullScreen), let fechar = janela.standardWindowButton(.closeButton),
          let barra = fechar.superview, let container = barra.superview else { return }
    let altura: CGFloat = 52
    container.frame = NSRect(x: 0, y: janela.frame.height - altura, width: janela.frame.width, height: altura)
    barra.frame = container.bounds
    for (i, tipo) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
      guard let b = janela.standardWindowButton(tipo) else { continue }
      b.setFrameOrigin(NSPoint(x: 18 + CGFloat(i) * 20, y: (altura - b.frame.height) / 2))
    }
  }

  /// O delegado atende a janela principal e a de ajustes; o que segue só vale para a principal.
  private func principal(_ n: Notification) -> Bool { (n.object as? NSWindow) === janela }
  func windowDidResize(_ n: Notification) { if principal(n) { posicionarSemaforo() } }
  func windowWillStartLiveResize(_ n: Notification) { if principal(n) { loja.fecharUso(); loja.sugestoes.fechar() } }
  func windowDidBecomeKey(_ n: Notification) {
    guard principal(n) else { return }
    posicionarSemaforo()
    loja.janelaFocada = true
    if let a = loja.abaAtiva, a.atencao { a.atencao = false; loja.atualizarSelo() }
  }
  func windowDidResignKey(_ n: Notification) { if principal(n) { loja.janelaFocada = false; loja.sugestoes.fechar() } }
  func windowWillEnterFullScreen(_ n: Notification) { if principal(n) { vidro.layer?.cornerRadius = 0; loja.telaCheia = true } }
  func windowWillExitFullScreen(_ n: Notification) { if principal(n) { vidro.layer?.cornerRadius = 12; loja.telaCheia = false } }
  func windowDidExitFullScreen(_ n: Notification) {
    guard principal(n) else { return }
    posicionarSemaforo()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.posicionarSemaforo() }
  }

  /// O botão vermelho só esconde: as abas continuam rodando. ⌘Q encerra.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === janela { janela.orderOut(nil); return false }
    return true
  }

  /// Ajustes fechados: solta a árvore de views (temas, fontes, seletores de cor) para devolver memória.
  func windowWillClose(_ n: Notification) {
    guard let j = n.object as? NSWindow, j === janelaAjustes else { return }
    loja.temaEmEdicao = nil
    if loja.dialogo?.emAjustes == true { loja.cancelarDialogo() }
    // A janela inteira vai embora (views, camadas e superfícies); abrir de novo cria outra.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.janelaAjustes === j, !j.isVisible else { return }
      j.contentView = nil
      j.delegate = nil
      self.janelaAjustes = nil
      Memoria.aliviar()
    }
  }

  func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
    janela.makeKeyAndOrderFront(nil); return true
  }

  func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
    let ocupados = loja.paineis.values.filter { $0.vivo && !$0.ocioso }
    if !ocupados.isEmpty && !saindo {
      // O diálogo é do app (não trava a thread): o macOS espera a resposta em `reply`.
      janela.makeKeyAndOrderFront(nil)
      loja.confirmar(ocupados.count == 1 ? "Um painel ainda está rodando algo" : "\(ocupados.count) painéis ainda estão rodando algo",
                     "Sair encerra: \(Set(ocupados.map(\.processo)).sorted().joined(separator: ", ")). As abas voltam na próxima abertura (Claude e Codex retomam a última conversa).",
                     "Sair", destrutivo: true, simbolo: "power",
                     senao: { NSApp.reply(toApplicationShouldTerminate: false) }) { [weak self] in
        self?.saindo = true
        self?.encerrarTudo()
        NSApp.reply(toApplicationShouldTerminate: true)
      }
      return .terminateLater
    }
    encerrarTudo()
    return .terminateNow
  }

  func applicationDidBecomeActive(_ n: Notification) { Atualizador.shared.appAtivou() }

  private func encerrarTudo() {
    Atualizador.shared.aoSair()
    loja.anotarSessoes()      // cada agente volta exatamente na conversa em que estava
    loja.salvar()
    loja.paineis.values.forEach { $0.encerrar() }
    controle.parar()
  }

  // MARK: - Teclado e mouse

  /// Painel cujo terminal está com o foco do teclado.
  func painelComFoco() -> Painel? {
    guard let r = janela.firstResponder as? TerminalView else { return nil }
    return loja.paineis.values.first { $0.view === r }
  }

  func instalarMonitores() {
    monitorTeclas = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
      guard let self else { return e }
      let mods = e.modifierFlags.intersection([.command, .control, .option])
      // Diálogo do app aberto (em qualquer janela): esc cancela, ↩ confirma.
      if let d = self.loja.dialogo, e.window === (d.emAjustes ? self.janelaAjustes : self.janela), mods.isEmpty {
        if e.keyCode == 53 { self.loja.cancelarDialogo(); return nil }
        if (e.keyCode == 36 || e.keyCode == 76) && !e.modifierFlags.contains(.shift) {
          if let t = e.window?.firstResponder as? NSTextView, t.hasMarkedText() { return e }
          self.loja.confirmarDialogo()
          return nil
        }
        return e
      }
      guard e.window === self.janela else { return e }
      // Quadro de agentes aberto: setas, ↩, M, R, C, N e esc são dele. Num campo de texto, só o esc.
      if self.loja.quadroAberto && mods.isEmpty {
        let campo = self.janela.firstResponder as? NSTextView
        if let campo {
          // No compose de um cartão, o esc fecha primeiro a lista de menções (é do campo).
          if e.keyCode == 53, !((campo as? CampoTexto)?.rascunho?.mencaoAberta ?? false), self.loja.teclaDoQuadro(53) { return nil }
          return e
        }
        _ = self.loja.teclaDoQuadro(e.keyCode)
        return nil      // nada do que se digita com o quadro aberto vai parar no terminal
      }
      if e.keyCode == 53 && mods.isEmpty, let h = self.loja.usoHover, h.fixo { self.loja.fecharUso(); return nil }
      guard let p = self.painelComFoco() else { return e }
      // ⌘V num agente com imagem ou arquivo copiado: vira anexo do compose (texto segue normal).
      if e.keyCode == 9, e.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command], p.tipoAgente != nil,
         NSPasteboard.general.string(forType: .string) == nil, p.receber(NSPasteboard.general) { return nil }
      if self.loja.sugestoes.tecla(e, painel: p) { return nil }
      let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
      var envio: String?
      if m == [.command] || m == [.command, .numericPad, .function] || m == [.command, .function] {
        switch e.keyCode {
        case 123: envio = "\u{01}"     // ⌘← início da linha
        case 124: envio = "\u{05}"     // ⌘→ fim da linha
        case 51: envio = "\u{15}"      // ⌘⌫ apaga a linha
        default: break
        }
      } else if m == [.shift] && (e.keyCode == 36 || e.keyCode == 76) {
        envio = "\u{1b}\r"             // ⇧↩ nova linha no Claude / Codex
      }
      if let envio { p.escrever(envio); return nil }
      return e
    }
    // Cliques num terminal: foca o painel; ⌘-clique abre o caminho ou o link sob o mouse;
    // o botão direito abre o menu do app.
    monitorCliques = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp]) { [weak self] e in
      guard let self, e.window === self.janela, self.loja.dialogo == nil else { return e }
      // Copiar ao selecionar: quando o arrasto de seleção termina, o texto vai para a área de transferência.
      if e.type == .leftMouseUp {
        if self.loja.ajustes.copiarAoSelecionar, let tv = self.janela.firstResponder as? TerminalView, tv.selectionActive {
          DispatchQueue.main.async {
            if let s = tv.getSelection(), !s.isEmpty, NSPasteboard.general.string(forType: .string) != s {
              MenuTerminal.copiar(s)
              self.loja.avisoRapido("Copiado")
            }
          }
        }
        return e
      }
      guard let alvo = self.janela.contentView?.hitTest(e.locationInWindow) else { return e }
      var v: NSView? = alvo
      var noTerminal = false
      while let x = v, !(x is CaixaPainel) { if x is TerminalView { noTerminal = true }; v = x.superview }
      guard let c = v as? CaixaPainel else { return e }
      let p = c.painel
      if e.type == .rightMouseDown {
        guard noTerminal else { return e }
        if p.aba?.painelAtivo != p.id { self.loja.focar(p, teclado: false) }
        MenuTerminal.mostrar(painel: p, evento: e)
        return nil
      }
      if p.aba?.painelAtivo != p.id { self.loja.focar(p, teclado: false) }
      if noTerminal, e.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command], let tv = p.view,
         let a = p.alvo(em: tv.convert(e.locationInWindow, from: nil)) {
        p.abrir(a)
        return nil
      }
      return e
    }
  }

  // MARK: - Ajustes e CLI

  func abrirAjustes(aba: String = "aparencia") {
    func mostrar(_ j: NSWindow) { if Armazem.semFoco { j.orderBack(nil) } else { j.makeKeyAndOrderFront(nil) } }
    func hospedar(_ secao: String) -> NSView {
      let h = NSHostingView(rootView: AjustesView(loja: loja, secao: secao))
      h.sizingOptions = []      // a janela manda no tamanho, não o conteúdo
      return h
    }
    if let j = janelaAjustes {
      j.contentView = hospedar(aba)
      mostrar(j)
      return
    }
    let j = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 640), styleMask: [.titled, .closable, .fullSizeContentView],
                     backing: .buffered, defer: false)
    j.title = "Ajustes"
    j.titleVisibility = .hidden
    j.titlebarAppearsTransparent = true
    j.isReleasedWhenClosed = false
    j.isMovableByWindowBackground = true
    j.appearance = NSAppearance(named: loja.tema.claro ? .aqua : .darkAqua)
    j.contentView = hospedar(aba)
    j.delegate = self
    j.center()
    mostrar(j)
    janelaAjustes = j
  }

  /// Link em ~/.local/bin/orion apontando para o CLI dentro do app.
  func instalarCLI() {
    guard let cli = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("orion").path else { return }
    let destinoDir = NSHomeDirectory() + "/.local/bin"
    let destino = destinoDir + "/orion"
    try? FileManager.default.createDirectory(atPath: destinoDir, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(atPath: destino)
    do {
      try FileManager.default.createSymbolicLink(atPath: destino, withDestinationPath: cli)
      loja.avisar("Comando orion instalado", "\(destino) → \(cli)\n\nAbas novas já encontram o comando; nas abertas, rode `rehash`.", simbolo: "checkmark.circle.fill")
    } catch {
      loja.avisar("Não consegui instalar", error.localizedDescription, simbolo: "exclamationmark.triangle.fill")
    }
  }

  // MARK: - Notificações

  nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                          withCompletionHandler fim: @escaping () -> Void) {
    let aba = r.notification.request.content.userInfo["aba"] as? String
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        self.janela.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let id = aba, let a = self.loja.aba(id) { self.loja.ativar(a) }
      }
    }
    fim()
  }

  nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                          withCompletionHandler fim: @escaping (UNNotificationPresentationOptions) -> Void) {
    fim([.banner, .sound])
  }

  // MARK: - Menu

  @objc func acaoMenu(_ item: NSMenuItem) {
    guard let nome = item.representedObject as? String else { return }
    let p = loja.painelAtivo
    switch nome {
    case "novaAba": loja.criarAba()
    case "novoClaude": loja.criarAba(kind: "claude")
    case "novoCodex": loja.criarAba(kind: "codex")
    case "novoGemini": loja.criarAba(kind: "gemini")
    case "proximoEsperando": loja.irParaProximoEsperando()
    case "reabrir": if let f = loja.fechados.first { loja.reabrir(f) } else { loja.avisar("Nada para reabrir", "Nenhum agente foi fechado há pouco.") }
    case "conversa": if let p, p.tipoAgente != nil { p.conversa.toggle() }
    case "copiarResultado": p?.copiarUltimoResultado()
    case "subagente": if let p, let t = p.tipoAgente { loja.novoAgentePerguntando(kind: t, pai: p.id) }
    case "portas": loja.atualizarPortas(); loja.paletaAberta = false; loja.pedirPortas += 1
    case "novoWorkspace": loja.novoWorkspacePerguntando()
    case "novoAgente": loja.novoAgentePerguntando()
    case "compose": (loja.quadroAberto ? nil : p)?.alternarFocoDoCompose()
    case "composeMostrar": p?.alternarCompose()
    case "anexar": if let p { p.anexarPeloSeletor() }
    case "quadro": loja.abrirQuadro()
    case "proximoWorkspace": loja.workspaceRelativo(1)
    case "workspaceAnterior": loja.workspaceRelativo(-1)
    case "focoEsquerda": loja.painelNaDirecao(dx: -1, dy: 0)
    case "focoDireita": loja.painelNaDirecao(dx: 1, dy: 0)
    case "focoCima": loja.painelNaDirecao(dx: 0, dy: -1)
    case "focoBaixo": loja.painelNaDirecao(dx: 0, dy: 1)
    case "interromper": p?.interromper()
    case "barraAgentes": loja.ajustes.barraAgentes.toggle()
    case "atualizarUso": loja.atualizarUsos(forcar: true)
    case "dividirH": _ = loja.dividir(horizontal: true)
    case "dividirV": _ = loja.dividir(horizontal: false)
    case "maximizar": loja.maximizar()
    case "fecharPainel": loja.fecharPainel(p)
    case "fecharAba": loja.fecharAba(loja.abaAtiva)
    case "renomear": if let a = loja.abaAtiva { loja.renomear(a) }
    case "duplicar": if let a = loja.abaAtiva { loja.duplicar(a) }
    case "reiniciar": p?.reiniciar()
    case "proximaAba": loja.abaRelativa(1)
    case "abaAnterior": loja.abaRelativa(-1)
    case "proximoPainel": loja.painelRelativo(1)
    case "painelAnterior": loja.painelRelativo(-1)
    case "voltar": loja.navegarVisita(-1)
    case "avancar": loja.navegarVisita(1)
    case "limpar": if let p, let v = p.view { v.clearScrollback(); if p.noPrompt { p.escrever("\u{0c}") } }
    case "paleta": loja.abrirQuadro(false); loja.paletaAberta.toggle()
    case "barraLateral": loja.ajustes.barraLateral.toggle()
    case "zoomMais": p?.mudarZoom(1)
    case "zoomMenos": p?.mudarZoom(-1)
    case "zoomZero": p?.mudarZoom(0)
    case "ajustes": abrirAjustes()
    case "contas": abrirAjustes(aba: "contas")
    case "mostrarJanela": janela.makeKeyAndOrderFront(nil)
    case "instalarCLI": instalarCLI()
    case "atualizacoes": abrirAjustes(aba: "sobre")
    default:
      if nome.hasPrefix("aba"), let n = Int(nome.dropFirst(3)) { loja.abaNumero(n) }
      else if nome.hasPrefix("ws"), let n = Int(nome.dropFirst(2)) { loja.workspaceNumero(n) }
    }
  }

  func montarMenu() {
    let principal = NSMenu()
    func item(_ titulo: String, _ acao: String, _ tecla: String = "", _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
      let i = NSMenuItem(title: titulo, action: #selector(acaoMenu(_:)), keyEquivalent: tecla)
      i.keyEquivalentModifierMask = mods
      i.representedObject = acao
      i.target = self
      return i
    }
    func sistema(_ titulo: String, _ sel: Selector, _ tecla: String, _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
      let i = NSMenuItem(title: titulo, action: sel, keyEquivalent: tecla)
      i.keyEquivalentModifierMask = mods
      return i
    }
    func submenu(_ titulo: String, _ itens: [NSMenuItem]) {
      let m = NSMenu(title: titulo)
      itens.forEach { m.addItem($0) }
      let raiz = NSMenuItem(title: titulo, action: nil, keyEquivalent: "")
      raiz.submenu = m
      principal.addItem(raiz)
    }
    submenu("Orion Terminal", [
      sistema("Sobre o Orion Terminal", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""), .separator(),
      item("Procurar atualizações…", "atualizacoes"), .separator(),
      item("Ajustes…", "ajustes", ","), item("Contas…", "contas", ",", [.command, .shift]),
      item("Instalar o comando orion…", "instalarCLI"), .separator(),
      sistema("Ocultar Orion Terminal", #selector(NSApplication.hide(_:)), "h"),
      sistema("Ocultar Outros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]), .separator(),
      sistema("Sair do Orion Terminal", #selector(NSApplication.terminate(_:)), "q"),
    ])
    submenu("Shell", [
      item("Novo terminal", "novaAba", "t"), item("Novo Claude", "novoClaude", "t", [.command, .shift]),
      item("Novo Codex", "novoCodex", "x", [.command, .shift]), item("Novo Gemini", "novoGemini", "g", [.command, .option]),
      item("Novo agente…", "novoAgente", "n", [.command, .option]), item("Novo subagente deste agente…", "subagente", "n", [.command, .option, .shift]),
      item("Reabrir agente fechado", "reabrir", "z", [.command, .option]), .separator(),
      item("Ver como conversa / terminal", "conversa", "c", [.command, .option]),
      item("Escrever no compose", "compose", "e"), item("Mostrar/esconder o compose", "composeMostrar", "e", [.command, .shift]),
      item("Anexar ao compose…", "anexar", "a", [.command, .option]), .separator(),
      item("Dividir à direita", "dividirH", "d"), item("Dividir abaixo", "dividirV", "d", [.command, .shift]),
      item("Maximizar painel", "maximizar", "\r", [.command, .shift]), .separator(),
      item("Renomear aba…", "renomear", "r", [.command, .shift]), item("Duplicar aba", "duplicar", "u", [.command, .shift]),
      item("Reiniciar sessão", "reiniciar", "r", [.command, .option]), .separator(),
      item("Fechar painel", "fecharPainel", "w"), item("Fechar aba", "fecharAba", "w", [.command, .shift]),
    ])
    let buscar = sistema("Buscar…", #selector(NSTextView.performFindPanelAction(_:)), "f")
    buscar.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
    let proximo = sistema("Buscar próximo", #selector(NSTextView.performFindPanelAction(_:)), "g")
    proximo.tag = Int(NSFindPanelAction.next.rawValue)
    submenu("Editar", [
      sistema("Copiar", #selector(NSText.copy(_:)), "c"), item("Copiar o último resultado", "copiarResultado", "c", [.command, .shift]),
      sistema("Colar", #selector(NSText.paste(_:)), "v"),
      sistema("Selecionar tudo", #selector(NSText.selectAll(_:)), "a"), .separator(),
      buscar, proximo, item("Limpar", "limpar", "k"), .separator(),
      item("Paleta de comandos", "paleta", "p"),
    ])
    submenu("Visualizar", [
      item("Barra lateral", "barraLateral", "b"), item("Barra de agentes", "barraAgentes", "b", [.command, .shift]),
      item("Portas em uso", "portas", "p", [.command, .option]), .separator(),
      item("Aumentar fonte", "zoomMais", "="), item("Aumentar fonte ", "zoomMais", "+"),
      item("Diminuir fonte", "zoomMenos", "-"), item("Tamanho normal", "zoomZero", "0"), .separator(),
      sistema("Tela cheia", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
    ])
    let esq = String(UnicodeScalar(NSLeftArrowFunctionKey)!), dir = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    let cima = String(UnicodeScalar(NSUpArrowFunctionKey)!), baixo = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    var itensWs: [NSMenuItem] = [
      item("Quadro de agentes", "quadro", "a", [.command, .shift]),
      item("Próximo agente esperando você", "proximoEsperando", "j"),
      item("Interromper o agente", "interromper", ".", [.command]),
      item("Atualizar o uso das contas", "atualizarUso", "u", [.command, .option]), .separator(),
      item("Novo workspace…", "novoWorkspace", "g", [.command, .shift]),
      item("Próximo workspace", "proximoWorkspace", baixo, [.command, .control]),
      item("Workspace anterior", "workspaceAnterior", cima, [.command, .control]), .separator(),
    ]
    for n in 1...9 { itensWs.append(item("Workspace \(n)", "ws\(n)", "\(n)", [.control])) }
    submenu("Workspaces", itensWs)
    var itensJanela: [NSMenuItem] = [
      sistema("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
      item("Mostrar janela", "mostrarJanela", "0", [.command, .option]), .separator(),
      item("Próxima aba", "proximaAba", "]", [.command, .shift]), item("Aba anterior", "abaAnterior", "[", [.command, .shift]),
      item("Próximo painel", "proximoPainel", "]"), item("Painel anterior", "painelAnterior", "["),
      item("Painel à esquerda", "focoEsquerda", esq, [.command, .option]), item("Painel à direita", "focoDireita", dir, [.command, .option]),
      item("Painel acima", "focoCima", cima, [.command, .option]), item("Painel abaixo", "focoBaixo", baixo, [.command, .option]),
      item("Voltar", "voltar", "[", [.command, .option]), item("Avançar", "avancar", "]", [.command, .option]), .separator(),
    ]
    for n in 1...9 { itensJanela.append(item("Aba \(n)", "aba\(n)", "\(n)")) }
    submenu("Janela", itensJanela)
    NSApp.mainMenu = principal
  }
}
