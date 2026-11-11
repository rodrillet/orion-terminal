import SwiftUI
import AppKit

/// Quadro de agentes (⇧⌘A): todos os agentes de todos os workspaces, em colunas —
/// esperando você · trabalhando · revisar · parados · concluído. As três do estado se arrumam
/// sozinhas; "revisar" e "concluído" são marcas suas (arraste o cartão, ou R / C). Em janela
/// estreita as colunas viram uma lista só.
struct Quadro: View {
  @Bindable var loja: Loja

  struct Coluna { let indice: Int; let titulo: String; let simbolo: String; let vazio: String }
  static let colunas: [Coluna] = [
    Coluna(indice: 0, titulo: "Esperando você", simbolo: "hand.raised.fill", vazio: "Ninguém esperando."),
    Coluna(indice: 1, titulo: "Trabalhando", simbolo: "bolt.fill", vazio: "Nada rodando agora."),
    Coluna(indice: 2, titulo: "Revisar", simbolo: "eye.fill", vazio: "Arraste para cá o que você quer conferir depois."),
    Coluna(indice: 3, titulo: "Parados", simbolo: "moon.fill", vazio: "Nenhum agente parado."),
    Coluna(indice: 4, titulo: "Concluído", simbolo: "checkmark.circle.fill", vazio: "Arraste para cá o que já está resolvido."),
  ]
  static func cor(_ i: Int) -> Color { [Cor.ambar, Cor.verde, Cor.azul, Cor.texto3, Cor.lilas][i] }

  var body: some View {
    let lista = loja.agentesDoQuadro()
    VStack(spacing: 0) {
      CabecalhoQuadro(loja: loja, lista: lista)
      Rectangle().fill(Cor.linha).frame(height: 1)
      GeometryReader { g in
        // Cabem as cinco colunas? Senão, uma lista só: seções empilhadas, cartões lado a lado.
        let estreito = g.size.width < 5 * 196 + 64
        if lista.isEmpty && loja.agentes(tudo: loja.quadroTudo).isEmpty {
          QuadroVazio(loja: loja)
        } else if estreito {
          ScrollView {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(Quadro.colunas, id: \.indice) { c in
                let dela = lista.filter { Loja.colunaDoQuadro($0) == c.indice }
                if !dela.isEmpty || c.indice != 1 {
                  ColunaQuadro(loja: loja, coluna: c, paineis: dela, rolar: false)
                }
              }
            }
            .padding(12)
          }
          .scrollIndicators(.never)
        } else {
          HStack(alignment: .top, spacing: 10) {
            ForEach(Quadro.colunas, id: \.indice) { c in
              ColunaQuadro(loja: loja, coluna: c, paineis: lista.filter { Loja.colunaDoQuadro($0) == c.indice }, rolar: true)
            }
          }
          .padding(12)
        }
      }
      Rectangle().fill(Cor.linha).frame(height: 1)
      ViewThatFits(in: .horizontal) {
        rodape(completo: true)
        rodape(completo: false)
      }
      .font(F.ui(11)).foregroundStyle(Cor.texto4)
      .padding(.horizontal, 14).frame(height: 30)
    }
    .frame(maxWidth: 1280, maxHeight: 760)
    .cartaoFlutuante(raio: R.cartao + 4)
    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 24)
    .onTapGesture { }     // clique dentro não fecha
  }

  func rodape(completo: Bool) -> some View {
    HStack(spacing: 14) {
      Text("↑ ↓ selecionar").fixedSize(); Text("↩ ir").fixedSize(); Text("M mensagem").fixedSize()
      if completo { Text("R revisar").fixedSize(); Text("C concluído").fixedSize(); Text("N renomear").fixedSize() }
      Text("esc fecha").fixedSize()
      Spacer(minLength: 0)
      if completo { Text("arraste um cartão para Revisar ou Concluído · duplo clique no título renomeia").fixedSize() }
    }
  }
}

struct CabecalhoQuadro: View {
  @Bindable var loja: Loja
  let lista: [Painel]
  @FocusState private var buscando: Bool

  var body: some View {
    let alvo = loja.quadroFiltro.flatMap { loja.workspace($0) } ?? loja.workspaceAtivo
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "square.grid.2x2").font(.system(size: 16, weight: .semibold)).foregroundStyle(Cor.acento)
        Text("Agentes").font(F.ui(17, .semibold)).foregroundStyle(Cor.texto)
        ViewThatFits(in: .horizontal) {
          Text(resumo(longo: true)).lineLimit(1).fixedSize()
          Text(resumo(longo: false)).lineLimit(1).fixedSize()
          EmptyView()
        }
        .font(F.ui(11.5)).monospacedDigit().foregroundStyle(Cor.texto3)
        Spacer(minLength: 8)
        if let alvo {
          HStack(spacing: 4) {
            ForEach(loja.ferramentas) { f in
              BotaoNovo(programa: f.id, rotulo: nil, dica: "Novo \(f.nome) no workspace \(alvo.nome)") { novo(f.id, alvo) }.frame(width: 40)
            }
          }
          BotaoMini("plus.circle", "Novo agente… (conta, pasta, título e primeira tarefa)") { loja.novoAgentePerguntando(workspace: alvo.id) }
        }
        BotaoMini("xmark", "Fechar  esc") { loja.abrirQuadro(false) }
      }
      HStack(spacing: 8) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 5) {
            FiltroQuadro(rotulo: "Todos", cor: nil, simbolo: nil, ativo: loja.quadroFiltro == nil) { loja.quadroFiltro = nil }
            ForEach(loja.workspaces) { w in
              FiltroQuadro(rotulo: w.nome, cor: w.cor, simbolo: w.simbolo, ativo: loja.quadroFiltro == w.id) { loja.quadroFiltro = loja.quadroFiltro == w.id ? nil : w.id }
            }
            Rectangle().fill(Cor.linha).frame(width: 1, height: 16).padding(.horizontal, 3)
            ForEach(loja.ferramentas) { f in
              FiltroQuadro(rotulo: f.nome, cor: nil, simbolo: nil, programa: f.id, ativo: loja.quadroFerramenta == f.id) { loja.quadroFerramenta = loja.quadroFerramenta == f.id ? nil : f.id }
            }
            FiltroQuadro(rotulo: "Terminais", cor: nil, simbolo: nil, programa: "shell", ativo: loja.quadroTudo) { loja.quadroTudo.toggle() }
          }
        }
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").font(.system(size: 11.5)).foregroundStyle(Cor.texto3)
          TextField("", text: $loja.quadroBusca, prompt: Text("Buscar tarefa, pasta…").foregroundStyle(Cor.texto4))
            .textFieldStyle(.plain).font(F.ui(12)).focused($buscando)
          if !loja.quadroBusca.isEmpty {
            Button { loja.quadroBusca = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Cor.texto3) }.buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 9).frame(width: 190, height: F.m(26))
        .background(Capsule().fill(Cor.vidro))
        .overlay(Capsule().strokeBorder(buscando ? Cor.acento.opacity(0.6) : Cor.linha))
      }
    }
    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
  }

  func resumo(longo: Bool) -> String {
    let e = lista.filter { $0.estado == .esperando }.count
    let t = lista.filter { $0.estado == .trabalhando }.count
    var s = "\(lista.count) no total · \(t) trabalhando · \(e) esperando você"
    if longo && loja.ajustes.memoria && loja.memoriaPaineis > 0 { s += " · \(Memoria.texto(lista.reduce(0) { $0 + $1.memoria })) de memória" }
    return s
  }

  func novo(_ tipo: String, _ w: Workspace) {
    loja.abrirQuadro(false)
    loja.criarAba(kind: tipo, cwd: w.pasta, workspace: w.id)
  }
}

struct FiltroQuadro: View {
  let rotulo: String
  let cor: String?
  let simbolo: String?
  var programa: String? = nil
  var dica: String? = nil
  let ativo: Bool
  let acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    Button(action: acao) {
      HStack(spacing: 5) {
        if let programa { IconePrograma(processo: programa, tamanho: 15) }
        if let simbolo { Image(systemName: simbolo).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(cor.map { Color(hex: $0) } ?? (ativo ? Cor.acento : Cor.texto3)) }
        Text(rotulo).font(F.ui(12, ativo ? .semibold : .regular)).lineLimit(1)
      }
      .foregroundStyle(ativo ? Cor.texto : (sobre ? Cor.texto2 : Cor.texto3))
      .padding(.horizontal, 10).frame(height: F.m(26))
      .background(Capsule().fill(ativo ? Cor.vidro2 : (sobre ? Cor.vidro : .clear)))
      .overlay(Capsule().strokeBorder(ativo ? Cor.acento.opacity(0.45) : Cor.linha))
      .contentShape(Capsule())
      .fixedSize()
    }
    .buttonStyle(.plain).onHover { sobre = $0 }
    .help(dica ?? (ativo ? "Filtro ligado: \(rotulo) — clique para tirar" : "Mostrar só: \(rotulo)"))
  }
}

struct QuadroVazio: View {
  @Bindable var loja: Loja
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "square.grid.2x2").font(.system(size: 32, weight: .light)).foregroundStyle(Cor.texto4)
      Text("Nenhum agente aqui ainda").font(F.ui(15, .semibold)).foregroundStyle(Cor.texto)
      Text("Abra um Claude ou um Codex num workspace: ele aparece neste quadro com o estado,\na conta, a pasta e as ações para acompanhar vários em paralelo.")
        .font(F.ui(12.5)).foregroundStyle(Cor.texto3).multilineTextAlignment(.center)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct ColunaQuadro: View {
  @Bindable var loja: Loja
  let coluna: Quadro.Coluna
  let paineis: [Painel]
  let rolar: Bool
  @Estado private var alvo = false

  var body: some View {
    let cor = Quadro.cor(coluna.indice)
    let aceita = coluna.indice != 1
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: coluna.simbolo).font(.system(size: 11)).foregroundStyle(cor)
        Text(coluna.titulo).font(F.ui(12, .semibold)).foregroundStyle(cor)
        Text("\(paineis.count)").font(F.ui(11)).monospacedDigit().foregroundStyle(Cor.texto4)
          .padding(.horizontal, 6).frame(height: 17).background(Capsule().fill(Cor.vidro))
        Spacer()
      }
      .padding(.horizontal, 4)
      if rolar {
        ScrollView { cartoes.padding(.bottom, 4) }.scrollIndicators(.never)
      } else {
        cartoes
      }
    }
    .padding(6)
    .frame(maxWidth: .infinity, maxHeight: rolar ? .infinity : nil, alignment: .top)
    .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(alvo && aceita ? cor.opacity(0.10) : Cor.vidro.opacity(0.6)))
    .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(alvo && aceita ? cor.opacity(0.6) : Color.clear, lineWidth: 1.5))
    .dropDestination(for: String.self) { ids, _ in
      guard aceita, let id = ids.first else { return false }
      loja.soltarNoQuadro(id, coluna: coluna.indice)
      return true
    } isTargeted: { alvo = $0 }
    .animation(.easeOut(duration: 0.1), value: alvo)
  }

  var cartoes: some View {
    // Em coluna: um cartão por linha. Em lista (janela estreita): quantos couberem lado a lado.
    LazyVGrid(columns: rolar ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 250), spacing: 7, alignment: .top)], spacing: 7) {
      ForEach(paineis, id: \.id) { p in CartaoAgente(loja: loja, painel: p) }
      if paineis.isEmpty {
        Text(coluna.vazio).font(F.ui(11.5)).foregroundStyle(Cor.texto4)
          .frame(maxWidth: .infinity, alignment: .leading).padding(10)
          .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(Cor.linha, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
      }
    }
  }
}

struct CartaoAgente: View {
  @Bindable var loja: Loja
  @Bindable var painel: Painel
  @Estado private var sobre = false
  @Estado private var nome = ""
  @FocusState private var editando: Bool

  var body: some View {
    let sel = loja.quadroSel == painel.id
    let aba = painel.aba
    let ws = aba.flatMap { loja.workspace(de: $0) }
    let tipo = painel.tipoAgente
    let renomeando = loja.quadroRenomeando == painel.id
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        IconeDoCartao(loja: loja, painel: painel)
        VStack(alignment: .leading, spacing: 4) {
          if renomeando {
            TextField("", text: $nome, prompt: Text("Nome (vazio = automático)").foregroundStyle(Cor.texto4))
              .textFieldStyle(.plain).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto).focused($editando)
              .padding(.horizontal, 6).padding(.vertical, 3)
              .background(RoundedRectangle(cornerRadius: R.pequeno, style: .continuous).fill(Cor.vidro2))
              .overlay(RoundedRectangle(cornerRadius: R.pequeno, style: .continuous).strokeBorder(Cor.acento.opacity(0.6)))
              .onSubmit { renomear() }
              .onAppear { nome = aba?.titulo ?? painel.titulo; DispatchQueue.main.async { editando = true } }
              .onChange(of: editando) { _, f in if !f && loja.quadroRenomeando == painel.id { renomear() } }
          } else {
            Text(aba.flatMap { $0.titulo } ?? painel.titulo).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
              .lineLimit(2).fixedSize(horizontal: false, vertical: true)
              .contentShape(Rectangle())
              .onTapGesture(count: 2) { loja.quadroSel = painel.id; loja.quadroRenomeando = painel.id }
              .help("Duplo clique para renomear")
          }
          if let persona = painel.persona, tipo != nil {
            HStack(spacing: 4) {
              Text(persona.nome).foregroundStyle(Color(hex: persona.cor)).brightness(Cor.claro ? -0.3 : 0).fontWeight(.medium).lineLimit(1)
              if !persona.papel.isEmpty { Text("· \(persona.papel)").foregroundStyle(Cor.texto3).lineLimit(1) }
              if let pai = painel.pai.flatMap({ loja.acharPainel($0) }) {
                Text("↳ \(pai.persona?.nome ?? "maestro")").foregroundStyle(Cor.ambar).lineLimit(1)
                  .help("Subagente de \(pai.persona?.nome ?? pai.titulo) — clique para selecionar o maestro")
                  .onTapGesture { loja.quadroSel = pai.id }
              }
            }
            .font(F.ui(11))
          }
          HStack(spacing: 5) {
            if let ws {
              Image(systemName: ws.simbolo).font(.system(size: 9.5)).foregroundStyle(Color(hex: ws.cor))
              Text(ws.nome).foregroundStyle(Color(hex: ws.cor)).brightness(Cor.claro ? -0.25 : 0).lineLimit(1)
              Text("·").foregroundStyle(Cor.texto4)
            }
            Text(Loja.encurtar(painel.cwd)).font(F.mono(10.5)).lineLimit(1).truncationMode(.head)
          }
          .font(F.ui(11)).foregroundStyle(Cor.texto3)
          ViewThatFits(in: .horizontal) {
            linhaEstado(tempo: true, branch: true)
            linhaEstado(tempo: true, branch: false)
            linhaEstado(tempo: false, branch: false)
          }
          .font(F.ui(11))
          HStack(spacing: 6) {
            if let tipo, let aba, let c = loja.conta(aba.conta(tipo)) {
              Circle().fill(Color(hex: c.cor)).frame(width: 7, height: 7)
              Text(c.nome).foregroundStyle(Cor.texto2).lineLimit(1)
              if let r = loja.usoVisivel(c.id)?.resumo { Text("\(r.rotulo) \(Int(r.pct.rounded()))%").foregroundStyle(r.pct >= 60 ? Cor.uso(r.pct) : Cor.texto3).lineLimit(1).layoutPriority(1) }
            }
            Spacer(minLength: 2)
            if loja.ajustes.memoria && painel.memoria > 0 {
              HStack(spacing: 3) { Image(systemName: "memorychip").font(.system(size: 9)); Text(Memoria.texto(painel.memoria)).lineLimit(1) }
                .foregroundStyle(Cor.texto4).layoutPriority(1)
                .help("Memória deste agente e do que ele abriu (\(painel.processos) processos)")
            }
          }
          .font(F.ui(11)).monospacedDigit()
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 4) {
        Pilula(rotulo: "Ir", simbolo: "arrow.up.forward.app", ativo: false, dica: "Ir até este agente  ↩") { loja.abrirQuadro(false); loja.focar(painel) }
        ViewThatFits(in: .horizontal) {
          acaoPrincipal(comRotulo: true)
          acaoPrincipal(comRotulo: false)
        }
        Pilula(rotulo: nil, simbolo: "stop.circle", ativo: false, dica: "Interromper o que ele está fazendo",
               desligado: !(painel.vivo && !painel.ocioso)) { painel.interromper() }
        Menu {
          Button { loja.marcar(painel, painel.marca == "revisar" ? nil : "revisar") } label: { Label(painel.marca == "revisar" ? "Tirar de Revisar" : "Marcar para revisar", systemImage: "eye") }
          Button { loja.marcar(painel, painel.marca == "concluido" ? nil : "concluido") } label: { Label(painel.marca == "concluido" ? "Tirar de Concluído" : "Marcar como concluído", systemImage: "checkmark.circle") }
          Divider()
          Button { loja.quadroRenomeando = painel.id } label: { Label("Renomear", systemImage: "pencil") }
          if tipo != nil {
            Button { loja.editarPersonagem(painel) } label: { Label("Personagem…", systemImage: "person.crop.circle") }
            Button { loja.novoAgentePerguntando(kind: tipo ?? "claude", workspace: aba?.workspace, pai: painel.id) } label: { Label("Novo subagente…", systemImage: "arrow.triangle.branch") }
          }
          Button { loja.reiniciarAgente(painel) } label: { Label("Reiniciar a sessão", systemImage: "arrow.clockwise") }.disabled(!painel.iniciado)
          if let tipo, let aba, loja.contas(tipo).count > 1 {
            Menu("Conta desta aba") {
              ForEach(loja.contas(tipo)) { c in
                Button { loja.trocarConta(aba, para: c) } label: { if aba.conta(tipo) == c.id { Label(c.nome, systemImage: "checkmark") } else { Text(c.nome) } }
              }
            }
          }
          if let aba, loja.workspaces.count > 1 {
            Menu("Mover para o workspace") {
              ForEach(loja.workspaces.filter { $0.id != aba.workspace }) { w in Button(w.nome) { loja.mover(aba: aba.id, paraWorkspace: w.id, antesDe: nil) } }
            }
          }
          Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(painel.id, forType: .string) } label: { Label("Copiar ID (para o CLI orion)", systemImage: "doc.on.doc") }
          Divider()
          Button(role: .destructive) { loja.fecharPainel(painel) } label: { Label("Fechar", systemImage: "xmark") }
        } label: {
          Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Cor.texto2)
            .frame(width: 28, height: F.m(24)).background(Capsule().fill(Cor.vidro)).overlay(Capsule().strokeBorder(Cor.linha))
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Marcar, renomear, reiniciar, conta, fechar")
        Spacer(minLength: 0)
        if let m = painel.marca {
          Image(systemName: m == "revisar" ? "eye.fill" : "checkmark.circle.fill").font(.system(size: 11))
            .foregroundStyle(m == "revisar" ? Cor.azul : Cor.lilas).help(m == "revisar" ? "Marcado para revisar" : "Marcado como concluído")
        }
      }
      let filhos = loja.filhos(de: painel.id)
      if !filhos.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(filhos.count) subagente\(filhos.count == 1 ? "" : "s")").font(F.ui(10, .semibold)).foregroundStyle(Cor.ambar)
          ForEach(filhos, id: \.id) { f in
            HStack(spacing: 6) {
              if let p = f.persona { AvatarPersona(persona: p, tamanho: 20, estado: f.estado) } else { IconePrograma(processo: f.programa, tamanho: 18) }
              Text(f.persona?.nome ?? "agente").font(F.ui(11, .medium)).foregroundStyle(Cor.texto).lineLimit(1).fixedSize()
              Text(f.aba.flatMap { $0.titulo } ?? f.titulo).font(F.ui(11)).foregroundStyle(Cor.texto3).lineLimit(1)
              Spacer(minLength: 2)
              Circle().fill(f.estado.cor).frame(width: 6, height: 6)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { loja.abrirQuadro(false); loja.focar(f) }
            .onTapGesture { loja.quadroSel = f.id }
            .help("\(f.persona?.nome ?? "") — \(f.estado.rotulo.lowercased()). Clique seleciona; duplo clique vai até ele.")
          }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: R.pequeno + 2, style: .continuous).fill(Cor.ambar.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: R.pequeno + 2, style: .continuous).strokeBorder(Cor.ambar.opacity(0.22)))
      }
      if loja.quadroMensagem == painel.id {
        ComposeView(painel: painel, embutido: true)
      }
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).fill(sel ? Cor.acento.opacity(Cor.claro ? 0.09 : 0.12) : (sobre ? Cor.vidro2 : Cor.elevado)))
    .overlay(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).strokeBorder(sel ? Cor.acento.opacity(0.6) : Cor.linhaForte))
    .contentShape(Rectangle())
    .onHover { sobre = $0 }
    .onTapGesture(count: 2) { loja.abrirQuadro(false); loja.focar(painel) }
    .onTapGesture { loja.quadroSel = painel.id }
    .draggable(painel.id) {
      HStack(spacing: 6) { IconePrograma(processo: painel.tipoAgente ?? painel.programa, tamanho: 18); Text(aba.flatMap { $0.titulo } ?? painel.titulo).font(F.ui(12, .medium)) }
        .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
    }
  }

  func linhaEstado(tempo: Bool, branch: Bool) -> some View {
    HStack(spacing: 6) {
      Circle().fill(painel.estado.cor).frame(width: 7, height: 7)
      Text(painel.estado.rotulo).foregroundStyle(painel.estado == .dormindo || painel.estado == .pronto ? Cor.texto3 : painel.estado.cor).lineLimit(1)
        .fixedSize(horizontal: tempo, vertical: false)
      if tempo && painel.estado != .dormindo { Ha(desde: painel.desde, prefixo: "há ").foregroundStyle(Cor.texto3) }
      Spacer(minLength: 2)
      if branch && !painel.branch.isEmpty {
        HStack(spacing: 2) { Image(systemName: "arrow.triangle.branch").font(.system(size: 9)); Text(painel.branch).lineLimit(1).fixedSize() }.foregroundStyle(Cor.lilas)
      }
    }
  }

  @ViewBuilder func acaoPrincipal(comRotulo: Bool) -> some View {
    if painel.estado == .dormindo {
      Pilula(rotulo: comRotulo ? "Acordar" : nil, simbolo: "play.fill", ativo: false, dica: "Acordar: abrir a sessão em segundo plano (retoma a última conversa), sem sair do quadro") { painel.acordar() }
    } else {
      Pilula(rotulo: comRotulo ? "Mensagem" : nil, simbolo: "text.bubble", ativo: loja.quadroMensagem == painel.id,
             dica: painel.vivo ? "Mensagem: escrever para ele sem sair do quadro (com @ e anexos)  M" : "A sessão terminou — reinicie para falar com o agente",
             desligado: !painel.vivo) { loja.quadroSel = painel.id; loja.quadroMensagem = loja.quadroMensagem == painel.id ? nil : painel.id }
    }
  }

  func renomear() {
    let n = nome.trimmingCharacters(in: .whitespaces)
    painel.aba?.titulo = n.isEmpty ? nil : n
    loja.quadroRenomeando = nil
    loja.salvarDepois()
  }
}

struct IconeDoCartao: View {
  let loja: Loja
  @Bindable var painel: Painel
  var body: some View {
    if let tipo = painel.tipoAgente {
      Group {
        if let persona = painel.persona {
          AvatarPersona(persona: persona, tamanho: 40, ferramenta: tipo, estado: painel.estado, maestro: loja.ehMaestro(painel))
        } else {
          AnelUso(loja: loja, tipo: tipo, conta: painel.aba?.conta(tipo), tamanho: 40, espessura: 2.2) { IconePrograma(processo: tipo, tamanho: 27) }
        }
      }
      .modifier(AncoraUso(loja: loja, tipo: tipo))
    } else {
      IconePrograma(processo: painel.programa, tamanho: 30).frame(width: 40, height: 40)
    }
  }
}
