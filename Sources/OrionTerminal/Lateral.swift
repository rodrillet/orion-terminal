import SwiftUI
import AppKit

// MARK: - Trilho de navegação
//
// Coluna fina à esquerda, só com ícones de traço: o que a barra lateral mostra (agentes ou
// histórico) e o que abre por cima (quadro, portas, notificações, ajustes). Os workspaces moram
// no seletor do topo.

struct TrilhoNav: View {
  @Bindable var loja: Loja
  @Estado private var portas = false
  @Estado private var notificacoes = false

  var body: some View {
    let c = loja.contagem()
    let minhasPortas = loja.portas.filter { $0.painel != nil }.count
    VStack(spacing: 6) {
      BotaoTrilho(simbolo: "bubble.left.and.bubble.right", dica: "Agentes e terminais deste workspace",
                  ativo: loja.modoLateral == "agentes" && !loja.quadroAberto) { loja.modoLateral = "agentes"; loja.abrirQuadro(false) }
      BotaoTrilho(simbolo: "square.grid.2x2", dica: "Quadro de agentes  ⇧⌘A\(c.esperando > 0 ? " — \(c.esperando) esperando você" : "")",
                  selo: c.esperando, ativo: loja.quadroAberto) { loja.abrirQuadro() }
      BotaoTrilho(simbolo: "clock.arrow.circlepath", dica: "Histórico: agentes fechados, para reabrir com a mesma conversa  ⌥⌘Z",
                  ativo: loja.modoLateral == "historico" && !loja.quadroAberto) {
        loja.modoLateral = loja.modoLateral == "historico" ? "agentes" : "historico"; loja.abrirQuadro(false)
      }
      BotaoTrilho(simbolo: "network", dica: "Portas em uso  ⌥⌘P", selo: minhasPortas, corSelo: Cor.verde, ativo: portas) {
        portas.toggle(); if portas { loja.atualizarPortas() }
      }
      .popover(isPresented: $portas, arrowEdge: .trailing) { ListaPortas(loja: loja, aberto: $portas) }
      BotaoTrilho(simbolo: "bell", dica: "Notificações", selo: loja.naoLidas, ativo: notificacoes) { notificacoes.toggle(); loja.naoLidas = 0 }
        .popover(isPresented: $notificacoes, arrowEdge: .trailing) { ListaNotificacoes(loja: loja, aberto: $notificacoes) }
      Spacer(minLength: 8)
      BotaoTrilho(simbolo: "gearshape", dica: "Ajustes  ⌘,") { (NSApp.delegate as? Delegado)?.abrirAjustes() }
    }
    .padding(.top, 4).padding(.bottom, 12)
    .frame(width: 52)
    .onChange(of: loja.pedirFechados) { _, _ in loja.modoLateral = "historico" }
    .onChange(of: loja.fecharPopovers) { _, _ in portas = false; notificacoes = false }
  }
}

struct BotaoTrilho: View {
  let simbolo: String
  let dica: String
  var selo = 0
  var corSelo: Color = Cor.ambar
  var ativo = false
  let acao: () -> Void
  @Estado private var sobre = false

  var body: some View {
    Button(action: acao) {
      Image(systemName: simbolo)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(ativo ? Cor.texto : (sobre ? Cor.texto2 : Cor.texto3))
        .frame(width: 34, height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ativo ? Cor.vidro2 : (sobre ? Cor.vidro : .clear)))
        .overlay(alignment: .topTrailing) { if selo > 0 { Selo(numero: selo, cor: corSelo).scaleEffect(0.86).offset(x: 3, y: -2) } }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { sobre = $0 }
    .help(dica)
  }
}

// MARK: - Seletor de workspace (dropdown do topo)

struct SeletorWorkspace: View {
  @Bindable var loja: Loja
  var compacta = false
  @Estado private var aberto = false
  @Estado private var sobre = false

  var body: some View {
    if let w = loja.workspaceAtivo {
      let outros = loja.workspaces.filter { $0.id != w.id }.reduce(0) { $0 + loja.contagem($1).esperando }
      Button { aberto.toggle() } label: {
        HStack(spacing: 8) {
          SimboloWorkspace(ws: w, tamanho: 22)
          Text(w.nome).font(F.ui(13.5, .semibold)).foregroundStyle(Cor.texto).lineLimit(1).frame(maxWidth: compacta ? 90 : 150, alignment: .leading)
          if outros > 0 { Circle().fill(Cor.ambar).frame(width: 6, height: 6).help("\(outros) agente\(outros == 1 ? "" : "s") esperando você em outro workspace") }
          Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Cor.texto3)
        }
        .padding(.leading, 5).padding(.trailing, 9).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: R.controle + 1, style: .continuous).fill(aberto ? Cor.vidro2 : (sobre ? Cor.vidro : .clear)))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain).fixedSize()
      .onHover { sobre = $0 }
      .help("Workspace: \(w.nome) — clique para trocar  ·  ⌃1…9 troca direto")
      .popover(isPresented: $aberto, arrowEdge: .bottom) { ListaWorkspaces(loja: loja, aberto: $aberto) }
      .onChange(of: loja.fecharPopovers) { _, _ in aberto = false }
      .onChange(of: loja.pedirWorkspaces) { _, _ in aberto = true }
    }
  }
}

struct ListaWorkspaces: View {
  @Bindable var loja: Loja
  @Binding var aberto: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Workspaces").font(F.ui(12, .semibold)).foregroundStyle(Cor.texto3)
        Spacer()
        Text("\(loja.workspaces.count)").font(F.ui(11)).monospacedDigit().foregroundStyle(Cor.texto4)
      }
      .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
      ScrollView {
        VStack(spacing: 2) {
          ForEach(Array(loja.workspaces.enumerated()), id: \.element.id) { i, w in
            LinhaWorkspace(loja: loja, ws: w, numero: i + 1) { aberto = false; loja.ativarWorkspace(w) }
          }
        }
        .padding(.horizontal, 6)
      }
      .frame(maxHeight: 380)
      Divider().padding(.vertical, 6)
      VStack(spacing: 2) {
        LinhaAcao(simbolo: "plus", titulo: "Novo workspace…", atalho: "⇧⌘G") { aberto = false; loja.novoWorkspacePerguntando() }
        if let w = loja.workspaceAtivo {
          Menu { MenuWorkspace(loja: loja, ws: w) } label: {
            LinhaAcao(simbolo: "slider.horizontal.3", titulo: "Opções de “\(w.nome)”", atalho: nil) {}
          }
          .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        }
      }
      .padding(.horizontal, 6).padding(.bottom, 8)
    }
    .frame(width: 320)
  }
}

private struct LinhaWorkspace: View {
  @Bindable var loja: Loja
  @Bindable var ws: Workspace
  let numero: Int
  let acao: () -> Void
  @Estado private var sobre = false

  var body: some View {
    let ativo = ws.id == loja.workspaceAtivoID
    let c = loja.contagem(ws)
    let n = loja.abas(de: ws).count
    Button(action: acao) {
      HStack(spacing: 10) {
        SimboloWorkspace(ws: ws, tamanho: 30, ativo: ativo || sobre)
        VStack(alignment: .leading, spacing: 2) {
          Text(ws.nome).font(F.ui(13, ativo ? .semibold : .medium)).foregroundStyle(Cor.texto).lineLimit(1)
          Text("\(Loja.encurtar(ws.pasta) == "~" ? "~" : (ws.pasta as NSString).lastPathComponent) · \(n == 0 ? "vazio" : "\(n) aba\(n == 1 ? "" : "s")")")
            .font(F.ui(10.5)).foregroundStyle(Cor.texto3).lineLimit(1)
            .help(Loja.encurtar(ws.pasta))
        }
        Spacer(minLength: 6)
        if c.trabalhando > 0 {
          HStack(spacing: 3) { Circle().fill(Cor.verde).frame(width: 6, height: 6); Text("\(c.trabalhando)") }
            .font(F.ui(10.5, .medium)).monospacedDigit().foregroundStyle(Cor.texto2).help("\(c.trabalhando) trabalhando")
        }
        if c.esperando > 0 { Selo(numero: c.esperando).help("\(c.esperando) esperando você") }
        if numero <= 9 { Text("⌃\(numero)").font(F.ui(10.5)).foregroundStyle(Cor.texto4).frame(width: 22, alignment: .trailing) }
        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Cor.acento).opacity(ativo ? 1 : 0)
      }
      .padding(.horizontal, 8).padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(sobre ? Cor.vidro2 : (ativo ? Cor.vidro : .clear)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { sobre = $0 }
    .contextMenu { MenuWorkspace(loja: loja, ws: ws) }
    .dropDestination(for: String.self) { ids, _ in
      ids.first.map { loja.mover(aba: $0, paraWorkspace: ws.id, antesDe: nil) }; return true
    }
  }
}

private struct LinhaAcao: View {
  let simbolo: String
  let titulo: String
  let atalho: String?
  let acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    Button(action: acao) {
      HStack(spacing: 10) {
        Image(systemName: simbolo).font(.system(size: 12, weight: .medium)).foregroundStyle(Cor.texto2).frame(width: 30)
        Text(titulo).font(F.ui(12.5)).foregroundStyle(Cor.texto).lineLimit(1)
        Spacer()
        if let atalho { Text(atalho).font(F.ui(10.5)).foregroundStyle(Cor.texto4) }
      }
      .padding(.horizontal, 8).frame(height: 32)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(sobre ? Cor.vidro2 : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).onHover { sobre = $0 }
  }
}

// MARK: - Barra lateral

struct BarraLateral: View {
  @Bindable var loja: Loja

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CampoBusca(texto: $loja.filtro, dica: loja.modoLateral == "historico" ? "Buscar no histórico" : "Buscar agente")
      if loja.modoLateral == "historico" { HistoricoLateral(loja: loja) } else { listaAgentes }
    }
    .padding(.leading, 2).padding(.trailing, 4).padding(.bottom, 10)
    .animation(.easeOut(duration: 0.16), value: loja.workspaceAtivoID)
    .animation(.easeOut(duration: 0.14), value: loja.modoLateral)
  }

  @ViewBuilder var listaAgentes: some View {
    if let w = loja.workspaceAtivo {
      let todas = loja.abas(de: w)
      let visiveis = loja.filtro.isEmpty ? todas : filtradas(todas)
      let agentes = visiveis.filter { loja.painelPrincipal($0)?.tipoAgente != nil }
      let terminais = visiveis.filter { loja.painelPrincipal($0)?.tipoAgente == nil }
      let linhasAgentes = loja.filtro.isEmpty ? loja.hierarquia(agentes) : agentes.map { ($0, 0) }
      let historico = loja.filtro.isEmpty ? Array(loja.fechados.filter { $0.workspace == w.id }.prefix(4)) : []
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          TituloSecao(titulo: "Agentes", total: agentes.count) { MenuNovo(loja: loja, ws: w, soAgentes: true) }
          ForEach(linhasAgentes, id: \.0.id) { a, nivel in LinhaAba(loja: loja, aba: a, nivel: nivel) }
          if agentes.isEmpty {
            Text(loja.filtro.isEmpty ? "Nenhum agente aqui. Abra um pelo + ou pela doca." : "Nenhum agente com “\(loja.filtro)”.")
              .font(F.ui(11.5)).foregroundStyle(Cor.texto4).padding(.horizontal, 10).padding(.vertical, 4)
          }
          if !terminais.isEmpty || loja.filtro.isEmpty {
            TituloSecao(titulo: "Terminais", total: terminais.count) { MenuNovo(loja: loja, ws: w, soAgentes: false) }.padding(.top, 10)
            ForEach(terminais) { a in LinhaAba(loja: loja, aba: a) }
          }
          if !historico.isEmpty {
            TituloSecao(titulo: "Histórico", total: nil) {
              Button("ver tudo") { loja.modoLateral = "historico" }.buttonStyle(.plain).font(F.ui(10.5)).foregroundStyle(Cor.texto3)
            }
            .padding(.top, 10)
            ForEach(historico) { f in LinhaFechado(loja: loja, f: f, compacta: true) }
          }
          Color.clear.frame(height: 30)
            .dropDestination(for: String.self) { ids, _ in
              ids.first.map { loja.mover(aba: $0, paraWorkspace: w.id, antesDe: nil) }; return true
            }
        }
      }
      .scrollIndicators(.never)
      .id(w.id)                                              // trocar de workspace troca a lista inteira…
      .transition(.opacity.combined(with: .offset(y: 6)))    // …com uma entrada curta
    }
  }

  func filtradas(_ lista: [Aba]) -> [Aba] {
    let f = loja.filtro.lowercased()
    return lista.filter { a in
      let p = loja.painelPrincipal(a)
      return "\(loja.titulo(a)) \(p?.cwd ?? "") \(p?.persona?.nome ?? "") \(p?.persona?.papel ?? "") \(p?.previa ?? "")".lowercased().contains(f)
    }
  }
}

struct CampoBusca: View {
  @Binding var texto: String
  let dica: String
  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass").font(.system(size: 11.5)).foregroundStyle(Cor.texto3)
      TextField(dica, text: $texto).textFieldStyle(.plain).font(F.ui(12.5))
      if !texto.isEmpty {
        Button { texto = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Cor.texto4) }.buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 10).frame(height: F.m(30))
    .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.vidro))
  }
}

struct TituloSecao<Acessorio: View>: View {
  let titulo: String
  let total: Int?
  @ViewBuilder var acessorio: Acessorio
  var body: some View {
    HStack(spacing: 4) {
      Text(titulo.uppercased()).tracking(0.6)
      if let total, total > 0 { Text("· \(total)").monospacedDigit() }
      Spacer()
      acessorio
    }
    .font(F.ui(10, .semibold)).foregroundStyle(Cor.texto4)
    .padding(.leading, 10).padding(.trailing, 4).frame(height: 24)
  }
}

/// "+" de uma seção: abre um agente (ou terminal) neste workspace.
struct MenuNovo: View {
  let loja: Loja
  let ws: Workspace
  let soAgentes: Bool
  var body: some View {
    Menu {
      if soAgentes {
        ForEach(loja.ferramentas) { f in Button("Novo \(f.nome)   \(f.atalho)") { loja.criarAba(kind: f.id, workspace: ws.id) } }
        Divider()
        Button("Novo agente com opções…   ⌥⌘N") { loja.novoAgentePerguntando(workspace: ws.id) }
      } else {
        Button("Novo terminal   ⌘T") { loja.criarAba(workspace: ws.id) }
      }
    } label: {
      Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Cor.texto3)
        .frame(width: 22, height: 22).contentShape(Rectangle())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    .help(soAgentes ? "Novo agente neste workspace" : "Novo terminal neste workspace")
  }
}

/// Hora curta, como num chat: "23:42" hoje, "ontem", "4 nov" antes disso.
func horaCurta(_ d: Date) -> String {
  let cal = Calendar.current
  if cal.isDateInToday(d) { return d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
  if cal.isDateInYesterday(d) { return "ontem" }
  return d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))
}

/// Uma aba na lista. Agente: mascote com o estado no canto, nome + papel + hora em cima e, embaixo,
/// o que ele está fazendo (ou a última coisa que disse). Terminal: ícone, título e pasta.
struct LinhaAba: View {
  @Bindable var loja: Loja
  @Bindable var aba: Aba
  var nivel = 0
  @Estado private var sobre = false

  var body: some View {
    let ativa = aba.id == loja.abaAtivaID
    let p = loja.painelPrincipal(aba)
    let tipo = p?.tipoAgente
    HStack(spacing: 10) {
      if nivel > 0 {
        Path { c in c.move(to: CGPoint(x: 6, y: 0)); c.addLine(to: CGPoint(x: 6, y: 18)); c.addLine(to: CGPoint(x: 14, y: 18)) }
          .stroke(Cor.linhaForte, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
          .frame(width: 14, height: 36)
          .padding(.leading, CGFloat(nivel - 1) * 14)
      }
      Group {
        if let persona = p?.persona, tipo != nil {
          AvatarPersona(persona: persona, tamanho: nivel > 0 ? 28 : 34, estado: loja.estado(aba), maestro: p.map { loja.ehMaestro($0) } ?? false)
        } else {
          IconePrograma(processo: loja.programa(aba), tamanho: 30).frame(width: 34)
        }
      }
      .overlay(alignment: .bottomLeading) {
        if let c = aba.cor { Circle().fill(Color(hex: c)).frame(width: 8, height: 8).overlay(Circle().stroke(Fundo.cor, lineWidth: 1.5)).offset(x: -1, y: 1) }
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          linhaDeCima(p, tipo)
          Spacer(minLength: 4)
          if sobre {
            Button { loja.fecharAba(aba) } label: {
              Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Cor.texto2).frame(width: 16, height: 16)
                .background(Circle().fill(Cor.vidro2))
            }.buttonStyle(.plain).help("Fechar  ⇧⌘W  (um agente fechado vai para o histórico)")
          } else if let p {
            Text(horaCurta(p.desde)).font(F.ui(10.5)).monospacedDigit().foregroundStyle(aba.atencao ? Cor.ambar : Cor.texto4).fixedSize()
          }
        }
        linhaDeBaixo(p, tipo)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, nivel > 0 ? 5 : 7)
    .background(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).fill(ativa ? Cor.elevado : (sobre ? Cor.vidro : .clear)))
    .contentShape(Rectangle())
    .onHover { sobre = $0 }
    .onTapGesture { loja.ativar(aba) }
    .help(dica(p))
    .draggable(aba.id) {
      HStack { IconePrograma(processo: loja.programa(aba), tamanho: 18); Text(loja.titulo(aba)) }.padding(6)
    }
    .dropDestination(for: String.self) { ids, _ in
      if let id = ids.first, id != aba.id { loja.mover(aba: id, paraWorkspace: aba.workspace, antesDe: aba.id) }
      return true
    }
    .contextMenu { MenuDaAba(loja: loja, aba: aba) }
  }

  @ViewBuilder func linhaDeCima(_ p: Painel?, _ tipo: String?) -> some View {
    let n = aba.arvore.folhas.count
    let filhos = p.map { loja.filhos(de: $0.id).count } ?? 0
    if let persona = p?.persona, tipo != nil {
      Text(persona.nome).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto).lineLimit(1).layoutPriority(1)
      if !persona.papel.isEmpty { EtiquetaLinha(texto: persona.papel) }
    } else {
      Text(loja.titulo(aba)).font(F.ui(13, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
    }
    if n > 1 { EtiquetaLinha(texto: "\(n) painéis") }
    if filhos > 0 {
      HStack(spacing: 2) { Image(systemName: "arrow.triangle.branch").font(.system(size: 8, weight: .bold)); Text("\(filhos)") }
        .font(F.ui(10, .medium)).foregroundStyle(Cor.ambar).padding(.horizontal, 4).frame(height: 16)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Cor.ambar.opacity(0.14)))
        .help("Maestro com \(filhos) subagente\(filhos == 1 ? "" : "s")")
    }
  }

  @ViewBuilder func linhaDeBaixo(_ p: Painel?, _ tipo: String?) -> some View {
    if let p, let tipo, p.persona != nil {
      let titulo = loja.titulo(aba)
      HStack(spacing: 5) {
        IconePrograma(processo: tipo, tamanho: 12)
        if aba.atencao || p.estado == .esperando {
          Text("esperando você").foregroundStyle(Cor.ambar).fixedSize()
          if p.previa.isEmpty { Text(titulo) } else { Text(p.previa) }
        } else if p.estado == .trabalhando {
          Text("trabalhando…").foregroundStyle(Cor.verde).fixedSize()
          Text(titulo)
        } else {
          Text(p.previa.isEmpty ? titulo : p.previa)
        }
      }
      .font(F.ui(11.5)).foregroundStyle(Cor.texto3).lineLimit(1)
    } else {
      let pasta = Loja.encurtar(p?.cwd ?? aba.arvore.folhas.first?.cwd ?? "")
      let titulo = loja.titulo(aba)
      let mesmo = pasta == titulo || (Loja.nomeDaPasta(p?.cwd ?? "") == titulo && pasta == "~")
      HStack(spacing: 5) {
        if p?.estado == .rodando { Circle().fill(Cor.azul).frame(width: 5, height: 5) }
        Text([mesmo ? (p?.ocioso == false ? p?.processo ?? "zsh" : "zsh") : pasta, p?.branch ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
          .truncationMode(.head)
      }
      .font(F.ui(11.5)).foregroundStyle(Cor.texto3).lineLimit(1)
    }
  }

  func dica(_ p: Painel?) -> String {
    guard let p else { return loja.titulo(aba) }
    var partes: [String] = [loja.titulo(aba)]
    if let persona = p.persona, let t = p.tipoAgente { partes.append("\(persona.nome)\(persona.papel.isEmpty ? "" : " (\(persona.papel))") · \(nomeLongoFerramenta(t))") }
    if let t = p.tipoAgente, loja.contas(t).count > 1, let c = loja.conta(aba.conta(t)) { partes.append("conta \(c.nome)") }
    partes.append(Loja.encurtar(p.cwd))
    if !p.branch.isEmpty { partes.append(p.branch) }
    partes.append(p.estado.rotulo.lowercased())
    if !p.portas.isEmpty { partes.append("porta\(p.portas.count == 1 ? "" : "s") \(p.portas.map(String.init).joined(separator: ", "))") }
    return partes.joined(separator: " · ")
  }
}

struct EtiquetaLinha: View {
  let texto: String
  var body: some View {
    Text(texto).font(F.ui(10, .medium)).foregroundStyle(Cor.texto3).lineLimit(1).fixedSize()
      .padding(.horizontal, 5).frame(height: 16)
      .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Cor.vidro2))
  }
}

// MARK: - Histórico

/// Todos os agentes fechados, por dia; um clique reabre na mesma conversa.
struct HistoricoLateral: View {
  @Bindable var loja: Loja

  var body: some View {
    let f = loja.filtro.lowercased()
    let lista = loja.fechados.filter { f.isEmpty || "\($0.titulo) \($0.persona?.nome ?? "") \($0.workspaceNome) \($0.pasta)".lowercased().contains(f) }
    let cal = Calendar.current
    let grupos: [(String, [Fechado])] = [
      ("Hoje", lista.filter { cal.isDateInToday($0.em) }),
      ("Ontem", lista.filter { cal.isDateInYesterday($0.em) }),
      ("Antes", lista.filter { !cal.isDateInToday($0.em) && !cal.isDateInYesterday($0.em) }),
    ].filter { !$0.1.isEmpty }
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        HStack {
          Button { loja.modoLateral = "agentes" } label: {
            HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)); Text("Agentes") }
          }.buttonStyle(.plain).font(F.ui(11.5, .medium)).foregroundStyle(Cor.texto2)
          Spacer()
          if !loja.fechados.isEmpty {
            Button("Esquecer todos") { loja.esquecerFechados() }.buttonStyle(.plain).font(F.ui(10.5)).foregroundStyle(Cor.texto4)
          }
        }
        .padding(.horizontal, 10).frame(height: 26)
        if lista.isEmpty {
          Text(loja.fechados.isEmpty ? "Quando você fecha um agente, ele fica aqui para reabrir com a mesma conversa." : "Nada com “\(loja.filtro)”.")
            .font(F.ui(11.5)).foregroundStyle(Cor.texto4).padding(.horizontal, 10).padding(.top, 4)
        }
        ForEach(grupos, id: \.0) { titulo, itens in
          TituloSecao(titulo: titulo, total: itens.count) { EmptyView() }.padding(.top, 6)
          ForEach(itens) { x in LinhaFechado(loja: loja, f: x, compacta: false) }
        }
      }
    }
    .scrollIndicators(.never)
  }
}

struct LinhaFechado: View {
  let loja: Loja
  let f: Fechado
  var compacta = false
  @Estado private var sobre = false

  var body: some View {
    Button { loja.reabrir(f) } label: {
      HStack(spacing: 10) {
        Group {
          if let p = f.persona { AvatarPersona(persona: p, tamanho: compacta ? 26 : 30, estado: .dormindo) }
          else { IconePrograma(processo: f.tipo, tamanho: compacta ? 24 : 28) }
        }
        .frame(width: 34)
        .opacity(sobre ? 1 : 0.8)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(f.titulo).font(F.ui(12.5, .medium)).foregroundStyle(sobre ? Cor.texto : Cor.texto2).lineLimit(1)
            Spacer(minLength: 4)
            Text(sobre ? "reabrir" : horaCurta(f.em)).font(F.ui(10.5)).foregroundStyle(sobre ? Cor.acento : Cor.texto4).fixedSize()
          }
          Text([f.persona?.nome, compacta ? nil : f.workspaceNome, f.sessao != nil ? "mesma conversa" : "última da pasta"]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            .font(F.ui(11)).foregroundStyle(Cor.texto4).lineLimit(1)
        }
      }
      .padding(.horizontal, 8).padding(.vertical, compacta ? 4 : 6)
      .background(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).fill(sobre ? Cor.vidro : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { sobre = $0 }
    .help(f.sessao != nil ? "Reabre exatamente esta conversa (\(Loja.encurtar(f.pasta)))" : "Reabre em \(Loja.encurtar(f.pasta)), continuando a última conversa de lá")
  }
}
