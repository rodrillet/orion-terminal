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
  @Estado private var caixa = false

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
      BotaoTrilho(simbolo: "tray", dica: "Caixa de entrada dos agentes: mensagens na fila, entregues e respondidas",
                  selo: loja.caixa.filter { $0.estado == .naFila }.count, corSelo: Cor.acento, ativo: caixa) { caixa.toggle() }
        .popover(isPresented: $caixa, arrowEdge: .trailing) { ListaCaixa(loja: loja) }
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
    .onChange(of: loja.fecharPopovers) { _, _ in portas = false; notificacoes = false; caixa = false }
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
  @AppStorage("lateral.agentesRecolhidos") private var agentesRecolhidos = false
  @AppStorage("lateral.terminaisRecolhidos") private var terminaisRecolhidos = false
  @AppStorage("lateral.historicoRecolhido") private var historicoRecolhido = false
  @AppStorage("lateral.historicoItens") private var historicoItens = 4
  @AppStorage("lateral.setoresRecolhidos") private var setoresRecolhidos = ""

  /// Linhas (já em hierarquia) agrupadas pelo setor do agente de cima de cada árvore; os
  /// subagentes ficam com o maestro. "Sem setor" vem por último, só se tiver alguém.
  func gruposPorSetor(_ linhas: [(Aba, Int)], _ w: Workspace) -> [(nome: String, linhas: [(Aba, Int)])] {
    var por: [String: [(Aba, Int)]] = [:]
    var raiz = ""
    for (a, nivel) in linhas {
      if nivel == 0 { raiz = a.setor.flatMap { w.setores.contains($0) ? $0 : nil } ?? "" }
      por[raiz, default: []].append((a, nivel))
    }
    var out = w.setores.map { (nome: $0, linhas: por[$0] ?? []) }
    if let sem = por[""], !sem.isEmpty { out.append((nome: "", linhas: sem)) }
    return out
  }

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
      let doWs = loja.filtro.isEmpty ? loja.fechados.filter { $0.workspace == w.id } : []
      let historico = Array(doWs.prefix(historicoItens))
      // Com filtro, nada fica recolhido (senão a busca esconderia o que achou).
      let recolherAgentes = agentesRecolhidos && loja.filtro.isEmpty
      let recolherTerminais = terminaisRecolhidos && loja.filtro.isEmpty
      let esperando = loja.esperandoVoce(w)
      if !esperando.isEmpty && loja.filtro.isEmpty { AvisoEsperando(loja: loja, lista: esperando) }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          TituloSecao(titulo: "Agentes", total: agentes.count, recolhido: $agentesRecolhidos) { MenuNovo(loja: loja, ws: w, soAgentes: true) }
          if !recolherAgentes {
            if w.setores.isEmpty || !loja.filtro.isEmpty {
              ForEach(linhasAgentes, id: \.0.id) { a, nivel in LinhaAba(loja: loja, aba: a, nivel: nivel) }
            } else {
              ForEach(gruposPorSetor(linhasAgentes, w), id: \.nome) { g in
                SecaoSetor(loja: loja, ws: w, nome: g.nome, linhas: g.linhas, recolhidos: $setoresRecolhidos)
              }
            }
            if agentes.isEmpty {
              Text(loja.filtro.isEmpty ? "Nenhum agente aqui. Abra um pelo + ou pela doca." : "Nenhum agente com “\(loja.filtro)”.")
                .font(F.ui(11.5)).foregroundStyle(Cor.texto4).padding(.horizontal, 10).padding(.vertical, 4)
            }
          }
          if !terminais.isEmpty || loja.filtro.isEmpty {
            TituloSecao(titulo: "Terminais", total: terminais.count, recolhido: $terminaisRecolhidos) { MenuNovo(loja: loja, ws: w, soAgentes: false) }.padding(.top, 10)
            if !recolherTerminais { ForEach(terminais) { a in LinhaAba(loja: loja, aba: a) } }
          }
          if !doWs.isEmpty {
            TituloSecao(titulo: "Histórico", total: doWs.count, recolhido: $historicoRecolhido) {
              Menu {
                Button("Ver tudo") { loja.modoLateral = "historico" }
                Divider()
                Picker("Mostrar aqui", selection: $historicoItens) {
                  ForEach([2, 4, 8, 15], id: \.self) { n in Text("\(n) itens").tag(n) }
                }
                Divider()
                Button("Limpar histórico deste workspace…", role: .destructive) { loja.esquecerFechadosPerguntando(workspace: w.id) }
              } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)).foregroundStyle(Cor.texto3)
                  .frame(width: 22, height: 22).contentShape(Rectangle())
              }
              .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
              .help("Opções do histórico")
            }
            .padding(.top, 10)
            if !historicoRecolhido {
              ForEach(historico) { f in LinhaFechado(loja: loja, f: f, compacta: true) }
              if doWs.count > historico.count {
                Button("ver mais \(doWs.count - historico.count)") { loja.modoLateral = "historico" }
                  .buttonStyle(.plain).font(F.ui(11)).foregroundStyle(Cor.texto3).padding(.leading, 52).padding(.vertical, 2)
              }
            }
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

/// Um setor na lista de agentes: título com contagem (e quantos trabalham/esperam), recolhível.
/// Recolhido, continua mostrando quem trabalha ou espera você. Soltar um agente no título o
/// move para o setor.
struct SecaoSetor: View {
  let loja: Loja
  let ws: Workspace
  let nome: String
  let linhas: [(Aba, Int)]
  @Binding var recolhidos: String
  @Estado private var sobre = false
  @Estado private var alvo = false

  private var chave: String { ws.id + "/" + nome }
  private var recolhido: Bool { recolhidos.split(separator: "\n").contains { String($0) == chave } }

  var body: some View {
    let ativos = linhas.filter { a, _ in
      let p = loja.painelPrincipal(a)
      return p?.estado == .trabalhando || p?.estado == .esperando || p?.permissao != nil || a.atencao
    }
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
          .rotationEffect(.degrees(recolhido ? 0 : 90)).foregroundStyle(Cor.texto4).frame(width: 10)
        Image(systemName: nome.isEmpty ? "tray" : "rectangle.3.group").font(.system(size: 10, weight: .semibold)).foregroundStyle(Cor.texto3)
        Text(nome.isEmpty ? "Sem setor" : nome).font(F.ui(11.5, .semibold)).foregroundStyle(Cor.texto2).lineLimit(1)
        Text("\(linhas.count)").font(F.ui(10.5)).monospacedDigit().foregroundStyle(Cor.texto4)
        if recolhido && !ativos.isEmpty { ChipRotulo(simbolo: "ellipsis", texto: "\(ativos.count) ativo\(ativos.count == 1 ? "" : "s")", cor: Cor.texto3, compacto: true) }
        Spacer(minLength: 4)
        if !nome.isEmpty && sobre {
          Menu {
            Button("Perguntar ao setor…") { loja.perguntarAoTimePerguntando(workspace: ws.id, setor: nome) }
            Button("Renomear setor…") { loja.renomearSetorPerguntando(ws, nome) }
            Button("Apagar setor (os agentes ficam sem setor)", role: .destructive) { loja.apagarSetor(ws, nome) }
          } label: {
            Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)).foregroundStyle(Cor.texto3)
              .frame(width: 20, height: 20).contentShape(Rectangle())
          }
          .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
      }
      .padding(.leading, 4).padding(.trailing, 4).frame(height: 26)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(alvo ? Cor.acento.opacity(0.16) : (sobre ? Cor.vidro : .clear)))
      .contentShape(Rectangle())
      .onHover { sobre = $0 }
      .onTapGesture { alternar() }
      .help(nome.isEmpty ? "Agentes sem setor" : "Setor \(nome) — clique recolhe; arraste um agente para cá para mover")
      .dropDestination(for: String.self) { ids, _ in
        guard let id = ids.first, let a = loja.aba(id) else { return false }
        loja.definirSetor(a, nome.isEmpty ? nil : nome); return true
      } isTargeted: { alvo = $0 }
      .contextMenu {
        if !nome.isEmpty {
          Button("Perguntar ao setor…") { loja.perguntarAoTimePerguntando(workspace: ws.id, setor: nome) }
          Button("Renomear setor…") { loja.renomearSetorPerguntando(ws, nome) }
          Button("Apagar setor", role: .destructive) { loja.apagarSetor(ws, nome) }
        }
        Button("Novo setor…") { loja.novoSetorPerguntando(workspace: ws.id) }
      }
      if linhas.isEmpty && !recolhido {
        Text("Arraste um agente para cá.").font(F.ui(11)).foregroundStyle(Cor.texto4).padding(.leading, 26).padding(.vertical, 2)
      }
      ForEach(recolhido ? ativos : linhas, id: \.0.id) { a, nivel in LinhaAba(loja: loja, aba: a, nivel: nivel) }
    }
    .padding(.top, 4)
  }

  private func alternar() {
    var lista = recolhidos.split(separator: "\n").map(String.init)
    if recolhido { lista.removeAll { $0 == chave } } else { lista.append(chave) }
    withAnimation(.easeOut(duration: 0.15)) { recolhidos = lista.joined(separator: "\n") }
  }
}

/// Aviso no alto da lista: quantos agentes deste workspace esperam você, quem são (mascotes) e o
/// botão que vai para o próximo (⌘J percorre a fila, em qualquer workspace).
struct AvisoEsperando: View {
  let loja: Loja
  let lista: [Painel]
  @Estado private var sobre = false

  var body: some View {
    let permissoes = lista.filter { $0.permissao != nil }.count
    Button { loja.irParaProximoEsperando() } label: {
      HStack(spacing: 8) {
        Image(systemName: permissoes > 0 ? "hand.raised.fill" : "hourglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Cor.ambar)
          .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Cor.ambar.opacity(0.16)))
        VStack(alignment: .leading, spacing: 1) {
          Text(lista.count == 1 ? "\(lista[0].persona?.nome ?? "1 agente") espera você" : "\(lista.count) esperam você")
            .font(F.ui(12, .semibold)).foregroundStyle(Cor.texto).lineLimit(1)
          Text(permissoes > 0 ? "\(permissoes) pede\(permissoes == 1 ? "" : "m") permissão" : "ir para o próximo")
            .font(F.ui(10.5)).foregroundStyle(Cor.texto3).lineLimit(1)
        }
        Spacer(minLength: 4)
        Text("⌘J").font(F.ui(10.5, .semibold)).foregroundStyle(Cor.texto3)
          .padding(.horizontal, 5).frame(height: 18)
          .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Cor.vidro2))
      }
      .padding(.horizontal, 8).padding(.vertical, 7)
      .background(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).fill(sobre ? Cor.vidro2 : Cor.vidro))
      .overlay(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).strokeBorder(Cor.linha))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { sobre = $0 }
    .help("Ir para o próximo agente que espera você  ⌘J")
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
  /// Com um binding, clicar no título recolhe/abre a seção (a seta aparece ao passar o mouse).
  var recolhido: Binding<Bool>? = nil
  @ViewBuilder var acessorio: Acessorio
  @Estado private var sobre = false

  var body: some View {
    HStack(spacing: 4) {
      HStack(spacing: 4) {
        if let r = recolhido {
          Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            .rotationEffect(.degrees(r.wrappedValue ? 0 : 90))
            .opacity(sobre || r.wrappedValue ? 1 : 0)
            .frame(width: 8)
        }
        Text(titulo.uppercased()).tracking(0.6)
        if let total, total > 0 { Text("· \(total)").monospacedDigit() }
      }
      .contentShape(Rectangle())
      .onTapGesture { if let r = recolhido { withAnimation(.easeOut(duration: 0.15)) { r.wrappedValue.toggle() } } }
      .help(recolhido.map { $0.wrappedValue ? "Mostrar \(titulo.lowercased())" : "Recolher \(titulo.lowercased())" } ?? "")
      Spacer()
      acessorio
    }
    .font(F.ui(10, .semibold)).foregroundStyle(sobre ? Cor.texto3 : Cor.texto4)
    .padding(.leading, recolhido == nil ? 10 : 0).padding(.trailing, 4).frame(height: 24)
    .onHover { sobre = $0 }
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
        Button("Novo setor…") { loja.novoSetorPerguntando(workspace: ws.id) }
        Divider()
        Button("Perguntar ao time…") { loja.perguntarAoTimePerguntando(workspace: ws.id) }
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
          AvatarPersona(persona: persona, tamanho: nivel > 0 ? 26 : 32, estado: loja.estado(aba), maestro: p.map { loja.ehMaestro($0) } ?? false)
        } else {
          IconePrograma(processo: loja.programa(aba), tamanho: 30).frame(width: Mascote.lado(nivel > 0 ? 28 : 34))
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
    if let p, loja.naFila(para: p.id) > 0 {
      let f = loja.naFila(para: p.id)
      HStack(spacing: 2) { Image(systemName: "envelope.fill").font(.system(size: 8, weight: .bold)); Text("\(f)") }
        .font(F.ui(10, .medium)).foregroundStyle(Cor.acento).padding(.horizontal, 4).frame(height: 16)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Cor.acento.opacity(0.14)))
        .help("\(f) mensage\(f == 1 ? "m" : "ns") na caixa — entra\(f == 1 ? "" : "m") quando ele parar")
    }
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
        if p.hibernado {
          ChipRotulo(simbolo: "moon.zzz.fill", texto: "hibernando", cor: Cor.texto3, compacto: true)
            .help("Hibernando para liberar memória — volta na mesma conversa quando você abrir ou mandar mensagem")
          Text(p.previa.isEmpty ? titulo : p.previa)
        } else if let perm = p.permissao {
          ChipRotulo(simbolo: "hand.raised.fill", texto: "permissão", cor: Cor.ambar, compacto: true)
          Text(perm.detalhe.split(separator: "\n").first.map(String.init) ?? perm.pergunta)
        } else if aba.atencao || p.estado == .esperando {
          ChipRotulo(simbolo: "hourglass", texto: "esperando", cor: Cor.ambar, compacto: true)
            .help("Esperando você")
          if p.previa.isEmpty { Text(titulo) } else { Text(p.previa) }
        } else if p.estado == .trabalhando {
          ChipRotulo(simbolo: "ellipsis", texto: "trabalhando", cor: Cor.verde, compacto: true)
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
            Button { loja.esquecerFechadosPerguntando() } label: {
              HStack(spacing: 4) { Image(systemName: "trash").font(.system(size: 9.5)); Text("Limpar tudo") }
            }
            .buttonStyle(.plain).font(F.ui(10.5)).foregroundStyle(Cor.texto3).help("Apagar todo o histórico")
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
    HStack(spacing: 10) {
      Group {
        if let p = f.persona { AvatarPersona(persona: p, tamanho: compacta ? 24 : 28, estado: .dormindo, animado: false) }
        else { IconePrograma(processo: f.tipo, tamanho: compacta ? 24 : 28) }
      }
      .frame(width: Mascote.lado(32))
      .opacity(sobre ? 1 : 0.8)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(f.titulo).font(F.ui(12.5, .medium)).foregroundStyle(sobre ? Cor.texto : Cor.texto2).lineLimit(1)
          Spacer(minLength: 4)
          if sobre {
            Button { loja.esquecer(f) } label: {
              Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Cor.texto2).frame(width: 16, height: 16)
                .background(Circle().fill(Cor.vidro2))
            }.buttonStyle(.plain).help("Tirar do histórico")
          } else {
            Text(horaCurta(f.em)).font(F.ui(10.5)).foregroundStyle(Cor.texto4).fixedSize()
          }
        }
        Text([f.persona?.nome, compacta ? nil : f.workspaceNome, f.sessao != nil ? "mesma conversa" : "última da pasta"]
          .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
          .font(F.ui(11)).foregroundStyle(Cor.texto4).lineLimit(1)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, compacta ? 4 : 6)
    .background(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).fill(sobre ? Cor.vidro : .clear))
    .contentShape(Rectangle())
    .onHover { sobre = $0 }
    .onTapGesture { loja.reabrir(f) }
    .help(f.sessao != nil ? "Clique para reabrir exatamente esta conversa (\(Loja.encurtar(f.pasta)))" : "Clique para reabrir em \(Loja.encurtar(f.pasta)), continuando a última conversa de lá")
    .contextMenu { MenuFechado(loja: loja, f: f) }
  }
}

/// Menu de contexto de um agente do histórico.
struct MenuFechado: View {
  let loja: Loja
  let f: Fechado
  var body: some View {
    Button("Reabrir") { loja.reabrir(f) }
    Button("Reabrir em segundo plano") { loja.reabrir(f, ativar: false) }
    Divider()
    Button("Mostrar a pasta no Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: f.pasta) }
    Button("Novo terminal nesta pasta") { loja.criarAba(cwd: f.pasta) }
    Button("Copiar caminho") { MenuTerminal.copiar(f.pasta) }
    if let s = f.sessao {
      Button("Copiar comando para retomar") {
        let fer = Ferramenta.de(f.tipo)
        let base = loja.comandoDoTipo(f.tipo) ?? f.tipo
        MenuTerminal.copiar("cd \(Compose.entreAspas(f.pasta)) && \(fer?.retomar(base, sessao: s) ?? base)")
      }
    }
    if let t = f.tarefa, !t.isEmpty { Button("Copiar a tarefa") { MenuTerminal.copiar(t) } }
    Divider()
    Button("Tirar do histórico", role: .destructive) { loja.esquecer(f) }
    Button("Limpar todo o histórico…", role: .destructive) { loja.esquecerFechadosPerguntando() }
  }
}

// MARK: - Caixa de entrada

/// Mensagens entre agentes: o que está na fila, o que foi entregue e o que voltou.
struct ListaCaixa: View {
  @Bindable var loja: Loja
  @Estado private var filtro = "todas"

  var body: some View {
    let lista = loja.caixa.reversed().filter { m in
      switch filtro {
      case "fila": return m.estado == .naFila
      case "aguardando": return m.estado == .entregue && m.esperaResposta
      default: return true
      }
    }
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Caixa de entrada").font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
        Spacer()
        if loja.caixa.contains(where: { $0.estado != .naFila && $0.estado != .entregue }) {
          Button("Limpar concluídas") { loja.limparCaixa() }.buttonStyle(.plain).font(F.ui(11)).foregroundStyle(Cor.texto3)
        }
      }
      .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
      Picker("", selection: $filtro) {
        Text("Todas").tag("todas"); Text("Na fila").tag("fila"); Text("Aguardando resposta").tag("aguardando")
      }
      .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.bottom, 8)
      Divider()
      if lista.isEmpty {
        Text(loja.caixa.isEmpty
             ? "Quando um agente manda trabalho para outro (orion mandar @nome \"…\"), a mensagem espera aqui até ele ficar livre, e a resposta volta sozinha."
             : "Nada neste filtro.")
          .font(F.ui(12)).foregroundStyle(Cor.texto3).padding(16).frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ScrollView {
          LazyVStack(spacing: 1) { ForEach(Array(lista.prefix(80))) { m in LinhaMensagem(loja: loja, m: m) } }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 420)
      }
    }
    .frame(width: 400)
  }
}

private struct LinhaMensagem: View {
  let loja: Loja
  let m: Mensagem
  @Estado private var sobre = false

  var body: some View {
    let destino = loja.painelExistente(m.para)
    HStack(alignment: .top, spacing: 10) {
      Group {
        if let ps = destino?.persona { AvatarPersona(persona: ps, tamanho: 28, estado: destino?.estado) }
        else { Image(systemName: "tray.full").font(.system(size: 13)).foregroundStyle(Cor.texto3).frame(width: 28, height: 28) }
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 5) {
          Text("\(m.deNome) → \(m.paraNome)").font(F.ui(12, .semibold)).foregroundStyle(Cor.texto).lineLimit(1)
          if m.respostaA != nil { EtiquetaLinha(texto: "resposta") }
          Spacer(minLength: 4)
          Text(horaCurta(m.criada)).font(F.ui(10.5)).foregroundStyle(Cor.texto4)
        }
        Text(m.texto.replacingOccurrences(of: "\n", with: " ")).font(F.ui(11.5)).foregroundStyle(Cor.texto2).lineLimit(2)
        HStack(spacing: 6) {
          Circle().fill(cor).frame(width: 6, height: 6)
          Text(m.rotuloEstado + (m.motivo.map { " — \($0)" } ?? "")).font(F.ui(10.5)).foregroundStyle(Cor.texto3)
          if !m.anexos.isEmpty {
            Image(systemName: "paperclip").font(.system(size: 9)); Text("\(m.anexos.count)").font(F.ui(10.5))
          }
          Spacer(minLength: 0)
          Text(m.id).font(F.mono(10)).foregroundStyle(Cor.texto4)
        }
        .foregroundStyle(Cor.texto3)
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(sobre ? Cor.vidro : SwiftUI.Color.clear)
    .contentShape(Rectangle())
    .onHover { sobre = $0 }
    .onTapGesture { if let p = destino, let a = p.aba { loja.ativar(a) } }
    .help(m.texto)
    .contextMenu {
      Button("Ir para \(m.paraNome)") { if let p = destino, let a = p.aba { loja.ativar(a) } }
      Button("Copiar texto") { loja.copiar(m.texto) }
      Button("Copiar id") { loja.copiar(m.id) }
      if let r = m.resposta { Button("Copiar a resposta") { loja.copiar(r) } }
      if m.estado == .naFila {
        Divider()
        Button("Entregar agora (mesmo ocupado)") { loja.entregarAgora(m.id) }
        Button("Cancelar", role: .destructive) { _ = loja.cancelarMensagem(m.id) }
      }
    }
  }

  private var cor: SwiftUI.Color {
    switch m.estado {
    case .naFila: return Cor.ambar
    case .entregue: return Cor.azul
    case .respondida: return Cor.verde
    case .semResposta, .passada: return Cor.texto3
    case .cancelada: return Cor.vermelho
    }
  }
}
