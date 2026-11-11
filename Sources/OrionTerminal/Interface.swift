import SwiftUI
import AppKit

// MARK: - Janela

struct JanelaRaiz: View {
  @Bindable var loja: Loja
  let area: AreaTerminais
  @Estado private var largura: CGFloat = 1100

  var body: some View {
    let lateral = loja.ajustes.barraLateral
    // Janela estreita: a barra lateral cede espaço aos terminais (nunca mais que ~38% da largura).
    let larguraLateral = min(loja.larguraArrasto ?? loja.ajustes.larguraLateral, max(170, largura * 0.38 - 60))
    ZStack(alignment: .bottomTrailing) {
      Fundo(loja: loja)
      VStack(spacing: 0) {
        BarraTopo(loja: loja, largura: largura)
        HStack(spacing: 0) {
          if lateral {
            TrilhoNav(loja: loja)
            BarraLateral(loja: loja).frame(width: larguraLateral)
            AlcaLateral(loja: loja)
          }
          // Sem a barra de agentes, a doca flutua sobre a área: os painéis deixam espaço para ela.
          AreaRepresentavel(area: area, esquerda: lateral ? 4 : 12, baixo: loja.ajustes.barraAgentes ? 6 : (loja.ajustes.doca ? 60 : 12))
        }
        if loja.ajustes.barraAgentes { BarraAgentes(loja: loja, largura: largura) }
      }
      if loja.ajustes.doca { Doca(loja: loja, compacta: largura < 900).padding(.trailing, 12).padding(.bottom, loja.ajustes.barraAgentes ? 5 : 10) }
      if loja.quadroAberto {
        Quadro(loja: loja)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Cor.veu.onTapGesture { loja.abrirQuadro(false) })
          .transition(.opacity)
      }
      if loja.paletaAberta {
        Paleta(loja: loja)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .background(Cor.veu.opacity(0.5).onTapGesture { loja.paletaAberta = false })
          .transition(.opacity)
      }
      CamadaUso(loja: loja)
      CamadaDialogo(loja: loja, emAjustes: false)
    }
    .onGeometryChange(for: CGFloat.self) { ($0.size.width / 20).rounded() * 20 } action: { largura = $0 }
    .animation(.easeOut(duration: 0.13), value: loja.quadroAberto)
    .animation(.easeOut(duration: 0.1), value: loja.paletaAberta)
    .ignoresSafeArea()
    .preferredColorScheme(Cor.claro ? .light : .dark)
    .tint(Cor.acento)
  }
}

struct AreaRepresentavel: NSViewRepresentable {
  let area: AreaTerminais
  var esquerda: CGFloat = 6
  var baixo: CGFloat = 10
  func makeNSView(context: Context) -> AreaTerminais { area }
  func updateNSView(_ v: AreaTerminais, context: Context) {
    let m = NSEdgeInsets(top: 2, left: esquerda, bottom: baixo, right: 12)
    if m.left != v.margens.left || m.bottom != v.margens.bottom { v.margens = m }
  }
}

/// Fundo da janela: a cor do tema (um tom atrás da dos terminais) na opacidade escolhida. Abaixo
/// de 100% a janela é transparente de verdade e o que está atrás aparece (com ou sem desfoque).
struct Fundo: View {
  let loja: Loja
  /// Cor de fundo da interface (para contornos que "recortam" um ponto sobre o avatar).
  static var cor: Color { let _ = Aparencia.atual.versao; return Tema.atual.janelaUI }
  var body: some View {
    let _ = Aparencia.atual.versao
    loja.tema.janelaUI.opacity(loja.opacidade)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: loja.telaCheia ? 0 : 12, style: .continuous))
  }
}

// MARK: - Peças comuns

extension EstadoPainel {
  var cor: Color {
    switch self {
    case .trabalhando: return Cor.verde
    case .esperando: return Cor.ambar
    case .rodando: return Cor.azul
    case .saiu: return Cor.vermelho
    case .pronto: return Cor.verde.opacity(0.55)
    case .dormindo: return Cor.texto4
    }
  }
}

struct Capsula<Conteudo: View>: View {
  @ViewBuilder var conteudo: Conteudo
  var body: some View {
    // Ícones soltos, só com o realce do hover: sem caixa em volta.
    HStack(spacing: 2) { conteudo }
  }
}

struct BotaoIcone: View {
  let simbolo: String
  let dica: String
  var selo = 0
  var tamanho: CGFloat = 15
  var ativo = false
  let acao: () -> Void
  @Estado private var sobre = false

  init(_ simbolo: String, dica: String, selo: Int = 0, tamanho: CGFloat = 15, ativo: Bool = false, acao: @escaping () -> Void) {
    self.simbolo = simbolo; self.dica = dica; self.selo = selo; self.tamanho = tamanho; self.ativo = ativo; self.acao = acao
  }

  var body: some View {
    Button(action: acao) {
      Image(systemName: simbolo)
        .font(.system(size: tamanho, weight: .medium))
        .foregroundStyle(ativo ? Cor.acento : (sobre ? Cor.texto : Cor.texto2))
        .frame(width: 34, height: 28)
        .background(RoundedRectangle(cornerRadius: R.controle - 1, style: .continuous).fill(sobre || ativo ? Cor.vidro2 : .clear))
        .overlay(alignment: .topTrailing) { if selo > 0 { Selo(numero: selo).offset(x: 1, y: -1) } }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { sobre = $0 }
    .help(dica)
  }
}

struct Selo: View {
  let numero: Int
  var cor: Color = Cor.ambar
  var body: some View {
    Text(numero > 9 ? "9+" : "\(numero)").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Cor.claro ? .white : .black)
      .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
      .background(Capsule().fill(cor))
  }
}

/// Símbolo do workspace num quadrado arredondado na cor dele.
struct SimboloWorkspace: View {
  let ws: Workspace
  var tamanho: CGFloat = 36
  var ativo = true
  var body: some View {
    let cor = Color(hex: ws.cor)
    Image(systemName: ws.simbolo)
      .font(.system(size: tamanho * 0.42, weight: .semibold))
      .foregroundStyle(ativo ? cor : cor.opacity(0.75))
      .frame(width: tamanho, height: tamanho)
      .background(RoundedRectangle(cornerRadius: tamanho * 0.3, style: .continuous).fill(cor.opacity(ativo ? 0.24 : 0.11)))
      .overlay(RoundedRectangle(cornerRadius: tamanho * 0.3, style: .continuous).strokeBorder(cor.opacity(ativo ? 0.7 : 0.0), lineWidth: 1.2))
      .saturation(Cor.claro ? 1.25 : 1).brightness(Cor.claro ? -0.12 : 0)
  }
}

/// Ponto de estado de um painel ou de uma aba. Estático de propósito: um pulso animado em
/// loop mantinha o SwiftUI redesenhando o tempo todo (era ~15% de CPU com um agente à espera).
/// Quem trabalha ou pede atenção ganha um halo.
struct Ponto: View {
  let estado: EstadoPainel
  var atencao = false
  var tamanho: CGFloat = 7

  var body: some View {
    let vivo = estado == .trabalhando || atencao
    let cor: Color = atencao ? Cor.ambar : (estado == .pronto || estado == .dormindo ? .clear : estado.cor)
    Circle().fill(cor).frame(width: tamanho, height: tamanho)
      .background(Circle().fill(cor.opacity(vivo ? 0.28 : 0)).frame(width: tamanho + 6, height: tamanho + 6))
  }
}

struct PontoEstado: View {
  let loja: Loja
  let aba: Aba
  let tamanho: CGFloat
  var body: some View {
    let e = loja.estado(aba)
    Ponto(estado: e, atencao: aba.atencao, tamanho: tamanho)
      .help(aba.atencao ? "Pede atenção" : e.rotulo)
  }
}

/// Tempo no estado atual, atualizado sozinho a cada 20 s.
struct Ha: View {
  let desde: Date
  var prefixo = ""
  var body: some View {
    TimelineView(.periodic(from: .now, by: 20)) { _ in
      let d = Loja.duracao(desde: desde)
      Text(d == "agora" ? d : prefixo + d).fixedSize()
    }
  }
}

func nomeCor(_ hex: String) -> String {
  ["#ff9e66": "Laranja", "#ff6b6b": "Vermelho", "#f5d76e": "Amarelo", "#9ee37d": "Verde", "#6fd6d6": "Ciano",
   "#7aa2ff": "Azul", "#b79cff": "Roxo", "#ff79c6": "Rosa", "#a0a0aa": "Cinza"][hex] ?? hex
}


// MARK: - Barra do topo

/// A barra se adapta à largura: primeiro somem os rótulos dos botões das ferramentas, depois os
/// botões de navegação e a paleta (que continuam no teclado e no menu).
struct BarraTopo: View {
  @Bindable var loja: Loja
  let largura: CGFloat
  @Estado private var notificacoes = false
  @Estado private var fechados = false

  var body: some View {
    let c = loja.contagem()
    let lateral = loja.ajustes.barraLateral
    let apertado = largura < 980, minimo = largura < 840
    HStack(spacing: minimo ? 6 : 8) {
      Color.clear.frame(width: loja.telaCheia ? 6 : 76, height: 1)
      SeletorWorkspace(loja: loja, compacta: minimo)
      Capsula {
        BotaoIcone("sidebar.left", dica: lateral ? "Esconder a barra lateral  ⌘B" : "Mostrar a barra lateral  ⌘B", ativo: lateral) { loja.ajustes.barraLateral.toggle() }
        if !minimo { BotaoIcone("command", dica: "Paleta de comandos  ⌘P") { loja.paletaAberta.toggle() } }
      }
      if !apertado {
        Capsula {
          BotaoIcone("chevron.left", dica: "Voltar para a aba visitada antes  ⌥⌘[") { loja.navegarVisita(-1) }
          BotaoIcone("chevron.right", dica: "Avançar para a aba visitada depois  ⌥⌘]") { loja.navegarVisita(1) }
        }
      }
      if !lateral { AbasCompactas(loja: loja) } else { Spacer(minLength: 0) }
      BotaoAtualizacao()
      ForEach(loja.ferramentas) { f in ChipFerramenta(loja: loja, tipo: f.id, compacto: apertado) }
      Capsula {
        // Com a barra lateral à mostra, quadro, histórico, notificações e ajustes moram no trilho.
        if !lateral {
          BotaoIcone("square.grid.2x2", dica: "Quadro de agentes  ⇧⌘A\(c.esperando > 0 ? " — \(c.esperando) esperando você" : "")",
                     selo: c.esperando, ativo: loja.quadroAberto) { loja.abrirQuadro() }
          if !loja.fechados.isEmpty && !minimo {
            BotaoIcone("clock.arrow.circlepath", dica: "Agentes fechados há pouco — reabrir com a mesma conversa  ⌥⌘Z") { fechados.toggle() }
              .popover(isPresented: $fechados, arrowEdge: .bottom) { ListaFechados(loja: loja, aberto: $fechados) }
              .onChange(of: loja.pedirFechados) { _, _ in fechados = true }
          }
          BotaoIcone("bell", dica: "Notificações", selo: loja.naoLidas) { notificacoes.toggle(); loja.naoLidas = 0 }
            .popover(isPresented: $notificacoes, arrowEdge: .bottom) { ListaNotificacoes(loja: loja, aberto: $notificacoes) }
        }
        BotaoIcone("plus", dica: "Novo terminal  ⌘T   ·   ⌥ clique: novo agente com opções  ⌥⌘N") {
          if NSEvent.modifierFlags.contains(.option) { loja.novoAgentePerguntando() } else { loja.criarAba() }
        }
        if !lateral { BotaoIcone("slider.horizontal.3", dica: "Ajustes  ⌘,") { (NSApp.delegate as? Delegado)?.abrirAjustes() } }
      }
      .onChange(of: loja.fecharPopovers) { _, _ in fechados = false; notificacoes = false }
    }
    .padding(.trailing, 12)
    .frame(height: 52)
    .background(Color.white.opacity(0.0001).gesture(WindowDragGesture()))
    .onTapGesture(count: 2) { loja.janela?.zoom(nil) }
  }
}

/// Workspaces em fila na barra do topo (quando a barra lateral está escondida).
struct FaixaWorkspaces: View {
  @Bindable var loja: Loja
  var maximo = 9
  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(loja.workspaces.prefix(maximo).enumerated()), id: \.element.id) { i, w in
        let ativo = w.id == loja.workspaceAtivoID
        let c = loja.contagem(w)
        SimboloWorkspace(ws: w, tamanho: 26, ativo: ativo)
          .overlay(alignment: .topTrailing) {
            if c.esperando > 0 { Circle().fill(Cor.ambar).frame(width: 8, height: 8).offset(x: 2, y: -2) }
            else if c.trabalhando > 0 { Circle().fill(Cor.verde).frame(width: 7, height: 7).offset(x: 2, y: -2) }
          }
          .contentShape(Rectangle())
          .onTapGesture { loja.ativarWorkspace(w) }
          .help("\(w.nome)  ⌃\(i + 1)\(c.trabalhando > 0 ? " · \(c.trabalhando) trabalhando" : "")\(c.esperando > 0 ? " · \(c.esperando) esperando você" : "")")
          .contextMenu { MenuWorkspace(loja: loja, ws: w) }
      }
      if loja.workspaces.count > maximo {
        Text("+\(loja.workspaces.count - maximo)").font(F.ui(10.5, .medium)).foregroundStyle(Cor.texto3).help("Os outros estão no botão do workspace")
      }
    }
    .padding(4)
    .background(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).fill(Cor.vidro))
    .overlay(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).strokeBorder(Cor.linha))
    .animation(.easeOut(duration: 0.14), value: loja.workspaceAtivoID)
  }
}

struct MenuWorkspace: View {
  let loja: Loja
  let ws: Workspace
  var body: some View {
    Button("Novo terminal aqui") { loja.criarAba(workspace: ws.id) }
    ForEach(loja.ferramentas) { f in Button("Novo \(f.nome) aqui") { loja.criarAba(kind: f.id, workspace: ws.id) } }
    Button("Novo agente…") { loja.novoAgentePerguntando(workspace: ws.id) }
    Divider()
    Button("Renomear…") { loja.renomear(ws) }
    Button("Pasta do workspace…") { loja.escolherPasta(ws) }
    Menu("Cor") {
      ForEach(Cor.paletaGrupos, id: \.self) { c in
        Button { ws.cor = c; loja.salvarDepois() } label: { Label(nomeCor(c), systemImage: ws.cor == c ? "checkmark" : "circle.fill") }
      }
    }
    Menu("Símbolo") {
      ForEach(Workspace.simbolos, id: \.self) { s in
        Button { ws.simbolo = s; loja.salvarDepois() } label: { Label(ws.simbolo == s ? "\(s) ✓" : s, systemImage: s) }
      }
    }
    Button("Mostrar pasta no Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ws.pasta) }
    Divider()
    Button("Mover para cima") { loja.moverWorkspace(ws, -1) }
    Button("Mover para baixo") { loja.moverWorkspace(ws, 1) }
    Divider()
    Button("Fechar workspace…", role: .destructive) { loja.fecharWorkspace(ws) }
  }
}

struct AbasCompactas: View {
  @Bindable var loja: Loja
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(loja.abasEmOrdem) { a in
          let p = loja.painelPrincipal(a)
          Button { loja.ativar(a) } label: {
            HStack(spacing: 6) {
              if let persona = p?.persona, p?.tipoAgente != nil { AvatarPersona(persona: persona, tamanho: 20, estado: p?.estado) }
              else { IconePrograma(processo: loja.programa(a), tamanho: 18) }
              Text(loja.titulo(a)).lineLimit(1).font(F.ui(12.5)).frame(maxWidth: 150)
              PontoEstado(loja: loja, aba: a, tamanho: 6)
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(a.id == loja.abaAtivaID ? Cor.vidro2 : .clear))
            .foregroundStyle(a.id == loja.abaAtivaID ? Cor.texto : Cor.texto2)
          }
          .buttonStyle(.plain)
          .help(p.map { "\($0.persona.map { "\($0.nome) · " } ?? "")\(loja.titulo(a)) — \(Loja.encurtar($0.cwd))" } ?? loja.titulo(a))
          .contextMenu { MenuDaAba(loja: loja, aba: a) }
        }
      }
    }
    .frame(maxWidth: .infinity)
  }
}

extension Loja {
  /// Ferramentas à mostra na interface.
  var ferramentas: [Ferramenta] { Ferramenta.todas.filter { !ajustes.ferramentasOcultas.contains($0.id) } }

  /// Abas na ordem da lista, com os subagentes logo abaixo do maestro que os criou (nível 1, 2…).
  func hierarquia(_ lista: [Aba]) -> [(Aba, Int)] {
    func paiDe(_ a: Aba) -> Aba? {
      guard let idPai = a.arvore.folhas.first?.pai else { return nil }
      return lista.first { $0.id != a.id && $0.arvore.folha(idPai) != nil }
    }
    var filhos: [String: [Aba]] = [:]
    var raizes: [Aba] = []
    for a in lista { if let p = paiDe(a) { filhos[p.id, default: []].append(a) } else { raizes.append(a) } }
    var out: [(Aba, Int)] = []
    func por(_ a: Aba, _ nivel: Int) {
      out.append((a, nivel))
      if nivel < 4 { for f in filhos[a.id] ?? [] { por(f, nivel + 1) } }
    }
    raizes.forEach { por($0, 0) }
    return out
  }
}

struct BotaoNovo: View {
  let programa: String, rotulo: String?, dica: String, acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    Button(action: acao) {
      HStack(spacing: 5) {
        IconePrograma(processo: programa, tamanho: 18)
        if let rotulo { Text(rotulo).font(F.ui(11.5, .medium)).foregroundStyle(sobre ? Cor.texto : Cor.texto2).lineLimit(1).fixedSize() }
      }
      .padding(.horizontal, rotulo == nil ? 0 : 7)
      .frame(maxWidth: .infinity).frame(height: F.m(32))
      .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(sobre ? Cor.vidro2 : Cor.vidro))
      .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(Cor.linha))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).onHover { sobre = $0 }.help(dica)
  }
}

struct AlcaLateral: View {
  @Bindable var loja: Loja
  @Estado private var inicio: Double?
  @Estado private var sobre = false
  var body: some View {
    Rectangle().fill(sobre || inicio != nil ? Cor.linha : .clear).frame(width: 1).padding(.horizontal, 3.5).padding(.vertical, 8)
      .contentShape(Rectangle())
      .onHover { h in
        sobre = h
        if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
      }
      .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { v in
        if inicio == nil { inicio = loja.ajustes.larguraLateral; loja.arrastando = true }
        // Só a largura provisória muda durante o arrasto; os ajustes são gravados ao soltar.
        let nova = (min(420, max(180, (inicio ?? 240) + v.translation.width))).rounded()
        if nova != loja.larguraArrasto { loja.larguraArrasto = nova }
      }.onEnded { _ in
        if let l = loja.larguraArrasto { loja.ajustes.larguraLateral = l }
        loja.larguraArrasto = nil
        inicio = nil
        loja.arrastando = false
        for p in loja.paineis.values { p.caixa?.assentar() }
      })
      .onTapGesture(count: 2) { loja.ajustes.larguraLateral = 240 }
  }
}

struct MenuDaAba: View {
  let loja: Loja
  let aba: Aba
  var body: some View {
    let p = loja.painelPrincipal(aba)
    Button("Renomear…") { loja.renomear(aba) }
    if let p, p.tipoAgente != nil {
      Button("Personagem… (nome, avatar, cor, papel)") { loja.editarPersonagem(p) }
      Button("Novo subagente deste agente…") { loja.novoAgentePerguntando(kind: p.tipoAgente ?? "claude", workspace: aba.workspace, pai: p.id) }
      Button(p.maestro ? "Deixar de ser maestro" : "Marcar como maestro") { p.maestro.toggle(); loja.salvarDepois() }
      Button(p.conversa ? "Ver como terminal" : "Ver como conversa") { loja.ativar(aba); p.conversa.toggle() }
    }
    Button("Duplicar") { loja.duplicar(aba) }
    Button("Reiniciar sessão") { loja.paineisDaAba(aba).forEach { $0.reiniciar() } }
    Menu("Cor") {
      Button("Sem cor") { aba.cor = nil; loja.salvarDepois() }
      ForEach(Cor.paletaGrupos, id: \.self) { c in Button(nomeCor(c)) { aba.cor = c; loja.salvarDepois() } }
    }
    Menu("Mover para o workspace") {
      ForEach(loja.workspaces.filter { $0.id != aba.workspace }) { w in Button(w.nome) { loja.mover(aba: aba.id, paraWorkspace: w.id, antesDe: nil) } }
      Divider()
      Button("Novo workspace…") {
        loja.novoWorkspacePerguntando(pasta: loja.painelPrincipal(aba)?.cwd) { w in
          loja.mover(aba: aba.id, paraWorkspace: w.id, antesDe: nil)
        }
      }
    }
    ForEach(Ferramenta.todas) { f in
      if loja.contas(f.id).count > 1 {
        Menu("Conta do \(f.nome) nesta aba") {
          ForEach(loja.contas(f.id)) { ct in
            Button { loja.trocarConta(aba, para: ct) } label: {
              if aba.conta(f.id) == ct.id { Label(ct.nome, systemImage: "checkmark") } else { Text(ct.nome) }
            }
          }
        }
      }
    }
    Divider()
    Button("Mostrar pasta no Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: loja.painelPrincipal(aba)?.cwd ?? NSHomeDirectory()) }
    Button("Copiar caminho") {
      NSPasteboard.general.clearContents(); NSPasteboard.general.setString(loja.painelPrincipal(aba)?.cwd ?? "", forType: .string)
    }
    Button("Copiar ID (para o CLI orion)") {
      NSPasteboard.general.clearContents(); NSPasteboard.general.setString(aba.painelAtivo, forType: .string)
    }
    Divider()
    Button("Fechar aba", role: .destructive) { loja.fecharAba(aba) }
  }
}

/// Agentes fechados há pouco: um clique reabre com a mesma conversa.
struct ListaFechados: View {
  @Bindable var loja: Loja
  @Binding var aberto: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Fechados há pouco").font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
        Spacer()
        if !loja.fechados.isEmpty { Button("Esquecer todos") { loja.esquecerFechados() }.buttonStyle(.plain).foregroundStyle(Cor.texto3).font(F.ui(11.5)) }
      }
      .padding(12)
      Divider()
      if loja.fechados.isEmpty {
        Text("Quando você fecha um agente, ele fica aqui para reabrir com a mesma conversa.")
          .font(F.ui(12)).foregroundStyle(Cor.texto3).padding(16).frame(width: 320, alignment: .leading)
      } else {
        ScrollView {
          VStack(spacing: 1) {
            ForEach(loja.fechados) { f in
              Button { aberto = false; loja.reabrir(f) } label: {
                HStack(spacing: 10) {
                  if let p = f.persona { AvatarPersona(persona: p, tamanho: 30, ferramenta: f.tipo) } else { IconePrograma(processo: f.tipo, tamanho: 28) }
                  VStack(alignment: .leading, spacing: 2) {
                    Text(f.titulo).font(F.ui(12.5, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
                    Text([f.persona?.nome, f.workspaceNome, Loja.encurtar(f.pasta)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                      .font(F.ui(10.5)).foregroundStyle(Cor.texto3).lineLimit(1).truncationMode(.middle)
                  }
                  Spacer(minLength: 6)
                  VStack(alignment: .trailing, spacing: 2) {
                    Text(Loja.duracao(desde: f.em) == "agora" ? "agora" : "há \(Loja.duracao(desde: f.em))").font(F.ui(10.5)).foregroundStyle(Cor.texto4)
                    Text(f.sessao != nil ? "mesma conversa" : "última da pasta").font(F.ui(10)).foregroundStyle(f.sessao != nil ? Cor.verde : Cor.texto4)
                  }
                }
                .padding(.horizontal, 12).padding(.vertical, 7).contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .help(f.sessao != nil ? "Reabre exatamente esta conversa (id \(f.sessao!.prefix(8))…)" : "Reabre na mesma pasta e conta, continuando a última conversa de lá")
            }
          }
        }
        .frame(width: 380).frame(maxHeight: 360)
      }
    }
  }
}

// MARK: - Barra de agentes (embaixo)

/// Pulso da operação inteira, sempre à vista: quantos agentes trabalham, quais esperam você —
/// em todos os workspaces — e, à direita, servidores (portas) e memória.
struct BarraAgentes: View {
  @Bindable var loja: Loja
  let largura: CGFloat
  @Estado private var sobre = false

  var body: some View {
    let ativos = loja.agentes().filter { $0.estado == .esperando || $0.estado == .trabalhando }
      .sorted { Loja.colunaDoQuadro($0.estado) < Loja.colunaDoQuadro($1.estado) }
    let trabalhando = ativos.filter { $0.estado == .trabalhando }.count
    let esperando = ativos.count - trabalhando
    let estreita = largura < 900
    HStack(spacing: estreita ? 7 : 10) {
      Button { loja.abrirQuadro() } label: {
        HStack(spacing: 6) {
          Image(systemName: "square.grid.2x2").font(.system(size: 11.5, weight: .semibold))
          if !estreita { Text("Agentes").font(F.ui(11.5, .medium)) }
        }
        .foregroundStyle(sobre || loja.quadroAberto ? Cor.texto : Cor.texto2)
        .padding(.horizontal, 9).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(sobre || loja.quadroAberto ? Cor.vidro2 : Cor.vidro))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain).onHover { sobre = $0 }.help("Quadro de agentes  ⇧⌘A")
      if ativos.isEmpty {
        Text("nenhum agente rodando").foregroundStyle(Cor.texto3).lineLimit(1).layoutPriority(-1)
      } else {
        if esperando > 0 {
          HStack(spacing: 5) { Ponto(estado: .esperando, atencao: true, tamanho: 6); Text(estreita ? "\(esperando)" : "\(esperando) esperando você") }
            .foregroundStyle(Cor.ambar).fixedSize().help("\(esperando) agente\(esperando == 1 ? "" : "s") esperando você")
        }
        if trabalhando > 0 {
          HStack(spacing: 5) { Ponto(estado: .trabalhando, tamanho: 6); Text(estreita ? "\(trabalhando)" : "\(trabalhando) trabalhando") }
            .foregroundStyle(Cor.verde).fixedSize().help("\(trabalhando) agente\(trabalhando == 1 ? "" : "s") trabalhando")
        }
        Rectangle().fill(Cor.linha).frame(width: 1, height: 14)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 4) { ForEach(ativos, id: \.id) { p in ChipAgente(loja: loja, painel: p) } }
        }
      }
      Spacer(minLength: 0)
      if loja.ajustes.portas { IndicadorPortas(loja: loja) }
      if loja.ajustes.memoria { IndicadorMemoria(loja: loja, curto: estreita) }
    }
    .font(F.ui(11.5))
    .padding(.leading, 12)
    .padding(.trailing, loja.ajustes.doca ? Doca.largura(loja, compacta: largura < 900) + 20 : 12)
    .frame(height: loja.ajustes.doca ? 50 : 36)
  }
}

/// Servidores rodando: as portas em escuta. Clique lista, abre no navegador e libera a porta.
struct IndicadorPortas: View {
  @Bindable var loja: Loja
  @Estado private var aberto = false
  @Estado private var sobre = false
  var body: some View {
    let minhas = loja.portas.filter { $0.painel != nil }
    Button { aberto.toggle(); if aberto { loja.atualizarPortas() } } label: {
      HStack(spacing: 5) {
        Image(systemName: "network").font(.system(size: 11))
        if !minhas.isEmpty { Text(minhas.prefix(2).map { ":\($0.porta)" }.joined(separator: " ") + (minhas.count > 2 ? " +\(minhas.count - 2)" : "")).monospacedDigit() }
      }
      .font(F.ui(11)).foregroundStyle(minhas.isEmpty ? (sobre ? Cor.texto2 : Cor.texto3) : Cor.verde)
      .padding(.horizontal, 7).frame(height: 24)
      .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(sobre ? Cor.vidro : .clear))
      .contentShape(Rectangle()).fixedSize()
    }
    .buttonStyle(.plain).onHover { sobre = $0 }
    .help(minhas.isEmpty ? "Servidores e portas em uso — clique para ver" : "Servidores rodando nos seus painéis: \(minhas.map { "\($0.processo) :\($0.porta)" }.joined(separator: ", "))")
    .popover(isPresented: $aberto, arrowEdge: .top) { ListaPortas(loja: loja, aberto: $aberto) }
    .onChange(of: loja.pedirPortas) { _, _ in aberto = true }
    .onChange(of: loja.fecharPopovers) { _, _ in aberto = false }
  }
}

struct ListaPortas: View {
  @Bindable var loja: Loja
  @Binding var aberto: Bool
  @Estado private var todas = false
  var body: some View {
    let lista = loja.portas.filter { todas || $0.painel != nil }
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text("Portas em uso").font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
        if loja.portasLendo { ProgressView().controlSize(.mini) }
        Spacer()
        Pilula(rotulo: "Do Mac inteiro", simbolo: todas ? "checkmark" : nil, ativo: todas, dica: "Mostrar também servidores que não foram abertos pelo Orion Terminal") { todas.toggle() }
        BotaoMini("arrow.clockwise", "Reler as portas agora") { loja.atualizarPortas() }
      }
      .padding(12)
      Divider()
      if lista.isEmpty {
        Text(todas ? "Nenhuma porta em escuta." : "Nenhum servidor rodando nos seus painéis.\nSuba um (npm run dev, python -m http.server…) e ele aparece aqui.")
          .font(F.ui(12)).foregroundStyle(Cor.texto3).padding(16).frame(width: 340, alignment: .leading)
      } else {
        ScrollView {
          VStack(spacing: 1) { ForEach(lista) { p in LinhaPorta(loja: loja, porta: p, aberto: $aberto) } }
        }
        .frame(width: 400).frame(maxHeight: 340)
      }
    }
  }
}

struct LinhaPorta: View {
  let loja: Loja
  let porta: Porta
  @Binding var aberto: Bool
  @Estado private var sobre = false
  var body: some View {
    let painel = porta.painel.flatMap { loja.acharPainel($0) }
    HStack(spacing: 10) {
      Text(":\(String(porta.porta))").font(F.mono(13, .semibold)).foregroundStyle(painel != nil ? Cor.verde : Cor.texto2).frame(width: 58, alignment: .leading)
      VStack(alignment: .leading, spacing: 2) {
        Text(porta.processo).font(F.ui(12.5, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
        Text(painel.map { "\($0.aba.flatMap { loja.workspace(de: $0) }?.nome ?? "") · \($0.aba.flatMap { $0.titulo } ?? $0.titulo)" } ?? "fora do Orion · pid \(porta.pid)")
          .font(F.ui(10.5)).foregroundStyle(Cor.texto3).lineLimit(1)
      }
      Spacer(minLength: 4)
      if let painel { BotaoMini("arrow.up.forward.app", "Ir até o painel que subiu este servidor") { aberto = false; loja.focar(painel) } }
      BotaoMini("safari", "Abrir http://localhost:\(porta.porta) no navegador") { if let u = porta.url { MenuTerminal.abrirNoNavegador(u) } }
      BotaoMini("xmark.octagon", "Liberar a porta \(porta.porta): encerra o processo \(porta.processo)") { aberto = false; loja.liberarPerguntando(porta) }
    }
    .padding(.horizontal, 12).padding(.vertical, 6)
    .background(sobre ? Cor.vidro : Color.clear)
    .onHover { sobre = $0 }
  }
}

/// Memória do app e dos terminais, discreta; clique mostra quem está usando quanto.
struct IndicadorMemoria: View {
  @Bindable var loja: Loja
  var curto = false
  @Estado private var aberto = false
  @Estado private var sobre = false
  var body: some View {
    Button { aberto.toggle(); if aberto { loja.amostrarMemoria(forcar: true) } } label: {
      HStack(spacing: 5) {
        Image(systemName: "memorychip").font(.system(size: 11))
        Text(Memoria.texto(loja.memoriaApp)).monospacedDigit()
        if !curto && loja.memoriaPaineis > 50 * 1_048_576 {
          Text("+ \(Memoria.texto(loja.memoriaPaineis))").monospacedDigit().foregroundStyle(Cor.texto4)
        }
      }
      .font(F.ui(11)).foregroundStyle(sobre ? Cor.texto2 : Cor.texto3)
      .padding(.horizontal, 7).frame(height: 24)
      .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(sobre ? Cor.vidro : .clear))
      .contentShape(Rectangle()).fixedSize()
    }
    .buttonStyle(.plain).onHover { sobre = $0 }
    .help("Memória: o Orion Terminal usa \(Memoria.texto(loja.memoriaApp)); os terminais e agentes abertos nele, \(Memoria.texto(loja.memoriaPaineis)). Clique para ver por painel.")
    .popover(isPresented: $aberto, arrowEdge: .top) { ListaMemoria(loja: loja, aberto: $aberto) }
    .onChange(of: loja.fecharPopovers) { _, _ in aberto = false }
  }
}

struct ListaMemoria: View {
  @Bindable var loja: Loja
  @Binding var aberto: Bool
  var body: some View {
    let lista = loja.paineis.values.filter { $0.vivo }.sorted { $0.memoria > $1.memoria }
    let maior = max(1, lista.first?.memoria ?? 1)
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Memória").font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
        Spacer()
        Text("app \(Memoria.texto(loja.memoriaApp)) · terminais \(Memoria.texto(loja.memoriaPaineis))").font(F.ui(11)).monospacedDigit().foregroundStyle(Cor.texto3)
      }
      .padding(12)
      Divider()
      ScrollView {
        VStack(spacing: 1) {
          ForEach(lista, id: \.id) { p in
            Button { aberto = false; loja.focar(p) } label: {
              HStack(spacing: 9) {
                if let persona = p.persona, let t = p.tipoAgente { AvatarPersona(persona: persona, tamanho: 24, ferramenta: t) } else { IconePrograma(processo: p.programa, tamanho: 22) }
                VStack(alignment: .leading, spacing: 3) {
                  HStack(spacing: 6) {
                    Text(p.aba.flatMap { $0.titulo } ?? p.titulo).font(F.ui(12.5, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Memoria.texto(p.memoria)).font(F.ui(11.5, .medium)).monospacedDigit().foregroundStyle(Cor.texto2)
                  }
                  GeometryReader { g in
                    Capsule().fill(Cor.vidro2).overlay(alignment: .leading) {
                      Capsule().fill(Cor.acento.opacity(0.75)).frame(width: max(3, g.size.width * CGFloat(Double(p.memoria) / Double(maior))))
                    }
                  }.frame(height: 4)
                  Text("\(p.aba.flatMap { loja.workspace(de: $0) }?.nome ?? "") · \(Loja.encurtar(p.cwd)) · \(p.processos) processo\(p.processos == 1 ? "" : "s")")
                    .font(F.ui(10.5)).foregroundStyle(Cor.texto3).lineLimit(1).truncationMode(.middle)
                }
              }
              .padding(.horizontal, 12).padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
          if lista.isEmpty { Text("Nenhum terminal aberto.").font(F.ui(12)).foregroundStyle(Cor.texto3).padding(16) }
        }
      }
      .frame(maxHeight: 340)
    }
    .frame(width: 360)
  }
}

struct ChipAgente: View {
  let loja: Loja
  @Bindable var painel: Painel
  @Estado private var sobre = false
  var body: some View {
    let ws = painel.aba.flatMap { loja.workspace(de: $0) }
    let naTela = loja.painelAtivo === painel
    Button { loja.focar(painel) } label: {
      HStack(spacing: 6) {
        if let persona = painel.persona { AvatarPersona(persona: persona, tamanho: 18, estado: painel.estado) }
        else { Circle().fill(painel.estado.cor).frame(width: 6, height: 6); IconePrograma(processo: painel.tipoAgente ?? painel.programa, tamanho: 16) }
        Text(painel.persona?.nome ?? (painel.aba.flatMap { $0.titulo } ?? painel.titulo)).lineLimit(1)
        Text(painel.aba.flatMap { $0.titulo } ?? painel.titulo).foregroundStyle(Cor.texto3).lineLimit(1).frame(maxWidth: 130, alignment: .leading)
          .opacity(painel.persona == nil ? 0 : 1).frame(width: painel.persona == nil ? 0 : nil)
        if let ws, ws.id != loja.workspaceAtivoID {
          Text(ws.nome).foregroundStyle(Color(hex: ws.cor)).brightness(Cor.claro ? -0.25 : 0).lineLimit(1)
        }
      }
      .foregroundStyle(sobre || naTela ? Cor.texto : Cor.texto2)
      .padding(.horizontal, 7).frame(height: 26)
      .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(naTela ? Cor.vidro2 : (sobre ? Cor.vidro : .clear)))
      .contentShape(Rectangle())
      .fixedSize()
    }
    .buttonStyle(.plain).onHover { sobre = $0 }
    .help("\(painel.estado.rotulo) há \(Loja.duracao(desde: painel.desde)) · workspace \(ws?.nome ?? "") · \(Loja.encurtar(painel.cwd))\(painel.memoria > 0 ? " · \(Memoria.texto(painel.memoria))" : "") — clique para ir até ele")
  }
}

// MARK: - Doca

struct Doca: View {
  @Bindable var loja: Loja
  var compacta = false
  @Estado private var sobre = false

  /// Largura que a doca ocupa (a barra de agentes deixa esse espaço livre).
  @MainActor static func largura(_ loja: Loja, compacta: Bool) -> CGFloat {
    let lado: CGFloat = compacta ? 34 : 38
    return CGFloat(loja.ferramentas.count + 2) * (lado + 5) + 10
  }

  var body: some View {
    let c = loja.contagem()
    let lado: CGFloat = compacta ? 34 : 38
    HStack(spacing: 5) {
      BotaoDoca(simbolo: "square.grid.2x2", dica: "Quadro de agentes  ⇧⌘A", selo: c.esperando, lado: lado) { loja.abrirQuadro() }
      Rectangle().fill(Cor.linha).frame(width: 1, height: 22)
      ForEach(loja.ferramentas) { f in BotaoAgente(loja: loja, tipo: f.id, lado: lado) }
      BotaoDoca(programa: "shell", dica: "Novo terminal  ⌘T", lado: lado) { loja.criarAba() }
    }
    .padding(2)
    .background(Capsule().fill(Cor.elevado))
    .overlay(Capsule().strokeBorder(Cor.linhaForte))
  }
}

struct BotaoDoca: View {
  var simbolo: String? = nil
  var programa: String? = nil
  let dica: String
  var selo = 0
  var lado: CGFloat = 38
  let acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    Button(action: acao) {
      Group {
        if let programa { IconePrograma(processo: programa, tamanho: lado * 0.68) }
        else { Image(systemName: simbolo ?? "square").font(.system(size: 16, weight: .medium)).foregroundStyle(Cor.texto2) }
      }
      .frame(width: lado, height: lado)
      .background(Circle().fill(sobre ? Cor.vidro2 : .clear))
      .overlay(alignment: .topTrailing) { if selo > 0 { Selo(numero: selo).offset(x: -2, y: 2) } }
      .contentShape(Circle())
    }
    .buttonStyle(.plain).onHover { sobre = $0 }.help(dica)
  }
}

/// Ícone do Claude/Codex/Gemini na doca. Passar o mouse mostra o resumo; o clique abre o painel
/// da ferramenta (contas, uso, agentes, "Novo …"); ⌥-clique ou duplo clique abre um agente direto.
/// O anel é o uso de 5 h da conta padrão.
struct BotaoAgente: View {
  @Bindable var loja: Loja
  let tipo: String
  var lado: CGFloat = 38
  @Estado private var sobre = false

  var body: some View {
    let conta = loja.contaPadrao(tipo)
    let rodando = loja.paineis.values.filter { $0.vivo && $0.agente == tipo }.count
    let nome = nomeFerramenta(tipo)
    AnelUso(loja: loja, tipo: tipo, tamanho: lado, espessura: 2.2) { IconePrograma(processo: tipo, tamanho: lado * 0.68) }
      .overlay(alignment: .topTrailing) {
        if rodando > 0 {
          Text("\(rodando)").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Cor.claro ? .white : .black)
            .frame(minWidth: 16, minHeight: 16).background(Circle().fill(Cor.claro ? Color.black.opacity(0.75) : .white)).offset(x: 3, y: -3)
        }
      }
      .background(Circle().fill(sobre ? Cor.vidro2 : .clear))
      .contentShape(Circle())
      .onHover { sobre = $0 }
      .modifier(AncoraUso(loja: loja, tipo: tipo, nome: "doca-\(tipo)", clique: true))
      .contextMenu {
        Section("Abrir \(nome) com") {
          ForEach(loja.contas(tipo)) { c in Button("\(c.nome)\(c.email.isEmpty ? "" : " · \(c.email)")") { loja.criarAba(kind: tipo, conta: c.id) } }
        }
        Section("Conta padrão (novos agentes)") {
          ForEach(loja.contas(tipo)) { c in
            Button { loja.definirPadrao(c) } label: { if c.id == conta?.id { Label(c.nome, systemImage: "checkmark") } else { Text(c.nome) } }
          }
        }
        Button("Novo agente…") { loja.novoAgentePerguntando(kind: tipo) }
        Button("Gerenciar contas…") { (NSApp.delegate as? Delegado)?.abrirAjustes(aba: "contas") }
      }
  }
}

// MARK: - Notificações

struct ListaNotificacoes: View {
  @Bindable var loja: Loja
  @Binding var aberto: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Notificações").font(F.ui(13, .semibold))
        Spacer()
        if !loja.notificacoes.isEmpty { Button("Limpar") { loja.notificacoes.removeAll() }.buttonStyle(.plain).foregroundStyle(Cor.texto3).font(F.ui(12)) }
      }
      .padding(12)
      Divider()
      if loja.notificacoes.isEmpty {
        Text("Avisos do Claude, do Codex e de comandos demorados aparecem aqui.")
          .font(F.ui(12)).foregroundStyle(Cor.texto3).padding(16).frame(width: 320, alignment: .leading)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(loja.notificacoes) { n in
              Button {
                if let a = loja.aba(n.aba) { loja.ativar(a) }
                aberto = false
              } label: {
                HStack(alignment: .top, spacing: 10) {
                  IconePrograma(processo: n.processo, tamanho: 26)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(n.titulo).font(F.ui(12.5, .medium)).foregroundStyle(Cor.texto)
                    Text(n.corpo).font(F.ui(11.5)).foregroundStyle(Cor.texto3).lineLimit(2)
                  }
                  Spacer()
                  Text(Loja.duracao(desde: n.em)).font(F.ui(10.5)).foregroundStyle(Cor.texto4)
                }
                .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .help("Ir até quem mandou este aviso")
            }
          }
        }
        .frame(width: 360, height: min(420, CGFloat(loja.notificacoes.count) * 58 + 10))
      }
    }
  }
}

// MARK: - Estado vazio (workspace sem abas)

struct EstadoVazio: View {
  @Bindable var loja: Loja
  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        if let w = loja.workspaceAtivo {
          SimboloWorkspace(ws: w, tamanho: 56)
          Text(w.nome).font(F.ui(20, .semibold)).foregroundStyle(Cor.texto)
          Text(Loja.encurtar(w.pasta)).font(F.mono(12)).foregroundStyle(Cor.texto3).lineLimit(1).truncationMode(.head)
          Text("Workspace vazio. Abra um terminal ou um agente — eles começam nesta pasta.")
            .font(F.ui(13)).foregroundStyle(Cor.texto3).multilineTextAlignment(.center)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 124), spacing: 10)], spacing: 10) {
            BotaoGrande(programa: "shell", texto: "Terminal", atalho: "⌘T") { loja.criarAba() }
            ForEach(loja.ferramentas) { f in BotaoGrande(programa: f.id, texto: f.nome, atalho: f.atalho) { loja.criarAba(kind: f.id) } }
          }
          .frame(maxWidth: 540)
          .padding(.top, 6)
          if let f = loja.fechados.first {
            Button { loja.reabrir(f) } label: {
              Label("Reabrir “\(f.titulo)” (fechado há \(Loja.duracao(desde: f.em)))", systemImage: "clock.arrow.circlepath").font(F.ui(12))
            }.buttonStyle(.plain).foregroundStyle(Cor.acento)
          }
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.never)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .preferredColorScheme(Cor.claro ? .light : .dark)
  }
}

struct BotaoGrande: View {
  let programa: String, texto: String, atalho: String, acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    Button(action: acao) {
      VStack(spacing: 7) {
        IconePrograma(processo: programa, tamanho: 40)
        Text(texto).font(F.ui(13, .medium)).foregroundStyle(Cor.texto)
        Text(atalho).font(F.ui(11)).foregroundStyle(Cor.texto3)
      }
      .frame(maxWidth: .infinity).frame(height: 108)
      .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(sobre ? Cor.vidro2 : Cor.elevado))
      .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linhaForte))
    }.buttonStyle(.plain).onHover { sobre = $0 }.help("Novo \(texto)  \(atalho)")
  }
}
