import SwiftUI

/// Paleta de comandos (⌘P): ações, workspaces, abas e agentes, contas, temas e pastas, com busca difusa.
struct Paleta: View {
  @Bindable var loja: Loja
  @Estado private var termo = ""
  @Estado private var sel = 0
  @FocusState private var focado: Bool

  struct Item: Identifiable {
    let id = UUID()
    let grupo: String
    let rotulo: String
    var detalhe = ""
    var programa: String? = nil
    var simbolo: String? = nil
    var cor: String? = nil
    var atalho = ""
    var marcado = false
    var persona: Persona? = nil
    let rodar: () -> Void
  }

  /// "Pedir a…": com texto digitado, cada agente do workspace vira um destino para ele (como
  /// mandar pelo compose: ocupado, entra na fila). "@lyra texto" escolhe o agente direto.
  var pedidos: [Item] {
    var t = termo.trimmingCharacters(in: .whitespaces)
    guard t.count >= 3 else { return [] }
    var agentes = loja.agentes(workspace: loja.workspaceAtivo?.id).filter { $0.persona != nil }
    if agentes.isEmpty { agentes = loja.agentes().filter { $0.persona != nil } }
    if t.hasPrefix("@"), let espaco = t.firstIndex(of: " ") {
      let nome = t[t.index(after: t.startIndex)..<espaco].lowercased()
      let escolhidos = agentes.filter { ($0.persona?.nome ?? "").lowercased().folding(options: .diacriticInsensitive, locale: nil).hasPrefix(nome) }
      guard !escolhidos.isEmpty else { return [] }
      agentes = escolhidos
      t = String(t[espaco...]).trimmingCharacters(in: .whitespaces)
      guard !t.isEmpty else { return [] }
    } else if t.hasPrefix("@") { return [] }
    let texto = t
    return agentes.prefix(6).map { p in
      let ps = p.persona!
      let ocupado = p.estado == .trabalhando
      return Item(grupo: "Pedir a um agente", rotulo: "Pedir a \(ps.nome): “\(texto)”",
                  detalhe: [ps.papel, ocupado ? "ocupado — vai para a fila" : p.estado.rotulo.lowercased(), loja.titulo(p.aba!)].filter { !$0.isEmpty }.joined(separator: " · "),
                  simbolo: "paperplane", persona: ps) { [weak p] in
        guard let p, let a = p.aba else { return }
        loja.enviarComposto(de: p, texto: texto, anexos: [])
        loja.ativar(a); loja.focar(p)
      }
    }
  }

  var itens: [Item] {
    var it: [Item] = []
    let d = NSApp.delegate as? Delegado
    func acao(_ r: String, _ s: String, _ k: String, _ f: @escaping () -> Void) { it.append(Item(grupo: "Ações", rotulo: r, simbolo: s, atalho: k, rodar: f)) }
    acao("Novo terminal", "plus", "⌘T") { loja.criarAba() }
    for f in loja.ferramentas {
      it.append(Item(grupo: "Ações", rotulo: "Novo \(f.nome)", programa: f.id, atalho: f.atalho) { loja.criarAba(kind: f.id) })
    }
    acao("Quadro de agentes", "square.grid.2x2", "⇧⌘A") { loja.abrirQuadro(true) }
    let esperando = loja.esperandoVoce()
    if !esperando.isEmpty {
      acao("Ir para quem espera você (\(esperando.count))", "hourglass", "⌘J") { loja.irParaProximoEsperando() }
    }
    if let f = loja.fechados.first { acao("Reabrir “\(f.titulo)” (fechado há pouco)", "clock.arrow.circlepath", "⌥⌘Z") { loja.reabrir(f) } }
    if let p = loja.painelAtivo, p.tipoAgente != nil {
      acao("Novo subagente de \(p.persona?.nome ?? "este agente")", "arrow.triangle.branch", "") { loja.novoAgentePerguntando(kind: p.tipoAgente ?? "claude", pai: p.id) }
      acao("Editar o personagem deste agente", "person.crop.circle", "") { loja.editarPersonagem(p) }
      acao(p.conversa ? "Ver como terminal" : "Ver como conversa", p.conversa ? "terminal" : "text.bubble", "⌥⌘C") { p.conversa.toggle() }
    }
    for porta in loja.portas where porta.painel != nil {
      acao("Liberar a porta \(porta.porta) (\(porta.processo))", "xmark.octagon", "") { loja.liberarPerguntando(porta) }
      acao("Abrir localhost:\(porta.porta) no navegador", "safari", "") { if let u = porta.url { MenuTerminal.abrirNoNavegador(u) } }
    }
    acao("Novo agente… (conta, pasta, primeira tarefa)", "plus.circle", "⌥⌘N") { loja.novoAgentePerguntando() }
    acao("Escrever no compose", "square.and.pencil", "⌘E") { loja.painelAtivo?.alternarFocoDoCompose() }
    acao("Mostrar/esconder o compose deste painel", "rectangle.bottomthird.inset.filled", "⇧⌘E") { loja.painelAtivo?.alternarCompose() }
    acao("Novo workspace", "plus.rectangle.on.folder", "⇧⌘G") { loja.novoWorkspacePerguntando() }
    acao("Dividir à direita", "rectangle.split.2x1", "⌘D") { _ = loja.dividir(horizontal: true) }
    acao("Dividir abaixo", "rectangle.split.1x2", "⇧⌘D") { _ = loja.dividir(horizontal: false) }
    acao("Maximizar painel", "arrow.up.left.and.arrow.down.right", "⇧⌘↩") { loja.maximizar() }
    acao("Renomear aba", "pencil", "⇧⌘R") { if let a = loja.abaAtiva { loja.renomear(a) } }
    acao("Reiniciar sessão", "arrow.clockwise", "⌥⌘R") { loja.painelAtivo?.reiniciar() }
    acao("Interromper o que está rodando", "stop.circle", "") { loja.painelAtivo?.interromper() }
    acao("Parar o agente com motivo…", "stop.circle", "") { if let p = loja.painelAtivo { loja.pararComMotivoPerguntando(p) } }
    acao("Perguntar ao time… (o Orion escolhe quem responde)", "person.3", "") { loja.perguntarAoTimePerguntando() }
    acao("Mostrar/esconder barra lateral", "sidebar.left", "⌘B") { loja.ajustes.barraLateral.toggle() }
    acao("Mostrar/esconder barra de agentes", "rectangle.bottomthird.inset.filled", "") { loja.ajustes.barraAgentes.toggle() }
    acao("Atualizar o uso das contas agora", "chart.bar", "") { loja.atualizarUsos(forcar: true) }
    acao("Ajustes", "slider.horizontal.3", "⌘,") { d?.abrirAjustes() }
    acao("Gerenciar contas", "person.2", "⇧⌘,") { d?.abrirAjustes(aba: "contas") }
    acao("Recarregar histórico do shell", "clock.arrow.circlepath", "") { loja.sugestoes.carregarHistorico() }
    acao("Instalar o CLI orion em ~/.local/bin", "terminal", "") { d?.instalarCLI() }

    for (i, w) in loja.workspaces.enumerated() {
      let n = loja.abas(de: w).count
      it.append(Item(grupo: "Workspaces", rotulo: "Ir para \(w.nome)", detalhe: "\(Loja.encurtar(w.pasta)) · \(n) aba\(n == 1 ? "" : "s")",
                     simbolo: w.simbolo, cor: nil, atalho: i < 9 ? "⌃\(i + 1)" : "", marcado: w.id == loja.workspaceAtivoID) { loja.ativarWorkspace(w) })
    }
    if let w = loja.workspaceAtivo {
      it.append(Item(grupo: "Workspaces", rotulo: "Renomear o workspace \(w.nome)", simbolo: "pencil") { loja.renomear(w) })
      it.append(Item(grupo: "Workspaces", rotulo: "Escolher a pasta do workspace \(w.nome)", detalhe: Loja.encurtar(w.pasta), simbolo: "folder") { loja.escolherPasta(w) })
    }
    for a in loja.todasEmOrdem {
      let p = loja.painelPrincipal(a)
      it.append(Item(grupo: "Abas e agentes", rotulo: loja.titulo(a),
                     detalhe: "\(loja.workspace(de: a)?.nome ?? "") · \(Loja.encurtar(p?.cwd ?? "")) · \(loja.estado(a).rotulo.lowercased())",
                     programa: loja.programa(a)) { loja.ativar(a) })
    }
    if let a = loja.abaAtiva {
      for w in loja.workspaces where w.id != a.workspace {
        it.append(Item(grupo: "Mover", rotulo: "Mover esta aba para \(w.nome)", simbolo: "arrow.right.square") { loja.mover(aba: a.id, paraWorkspace: w.id, antesDe: nil) })
      }
    }
    for c in loja.contas {
      let nome = nomeFerramenta(c.tipo)
      it.append(Item(grupo: "Contas", rotulo: "Abrir \(nome) com a conta \(c.nome)", detalhe: c.email, programa: c.tipo) { loja.criarAba(kind: c.tipo, conta: c.id) })
      if loja.contaPadrao(c.tipo)?.id != c.id {
        it.append(Item(grupo: "Contas", rotulo: "Conta padrão do \(nome) → \(c.nome)", detalhe: "vale para os próximos agentes", cor: c.cor) { loja.definirPadrao(c) })
      }
      if let a = loja.abaAtiva, a.conta(c.tipo) != c.id, loja.contas(c.tipo).count > 1 {
        it.append(Item(grupo: "Contas", rotulo: "Trocar esta aba para a conta \(c.nome) (\(nome))", detalhe: "agente rodando reinicia", cor: c.cor) { loja.trocarConta(a, para: c) })
      }
    }
    for (modo, nome) in [("escuro", "Escuro"), ("claro", "Claro"), ("sistema", "Igual ao sistema")] {
      it.append(Item(grupo: "Aparência", rotulo: "Aparência: \(nome)", simbolo: modo == "escuro" ? "moon" : modo == "claro" ? "sun.max" : "circle.lefthalf.filled",
                     marcado: loja.ajustes.aparencia == modo) { loja.ajustes.aparencia = modo })
    }
    it.append(Item(grupo: "Aparência", rotulo: loja.translucido ? "Janela opaca" : "Janela transparente (vidro)", simbolo: "square.on.square.dashed") {
      loja.ajustes.opacidade = loja.translucido ? 1 : 0.6
    })
    for t in Tema.todos {
      it.append(Item(grupo: "Temas", rotulo: "Tema: \(t.nome)", detalhe: t.claro ? "claro" : "escuro", cor: t.acento, marcado: loja.tema.id == t.id) { loja.escolherTema(t) })
    }
    var pastas: [String] = []
    for p in loja.paineis.values where !pastas.contains(p.cwd) { pastas.append(p.cwd) }
    for p in pastas.prefix(20) {
      it.append(Item(grupo: "Pastas", rotulo: "Novo terminal em \(Loja.encurtar(p))", simbolo: "folder") { loja.criarAba(cwd: p) })
    }
    return it
  }

  var filtrados: [Item] {
    let t = termo.trimmingCharacters(in: .whitespaces).lowercased()
    guard !t.isEmpty else { return itens }
    let achados = itens.map { ($0, Paleta.pontuar($0.rotulo.lowercased(), t) + Paleta.pontuar($0.detalhe.lowercased(), t) * 0.5) }
      .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
    // Achou pouca coisa: o texto provavelmente é um pedido — os agentes vêm primeiro.
    return achados.count < 3 || t.hasPrefix("@") ? pedidos + achados : achados + pedidos
  }

  static func pontuar(_ alvo: String, _ termo: String) -> Double {
    if let r = alvo.range(of: termo) { return 100 - Double(alvo.distance(from: alvo.startIndex, to: r.lowerBound)) + (r.lowerBound == alvo.startIndex ? 50 : 0) }
    var pos = alvo.startIndex, pontos = 0.0
    for ch in termo {
      guard let j = alvo[pos...].firstIndex(of: ch) else { return 0 }
      pontos += j == pos ? 3 : 1
      pos = alvo.index(after: j)
    }
    return pontos
  }

  var body: some View {
    let lista = filtrados
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").font(F.ui(15)).foregroundStyle(Cor.texto3)
        TextField("Buscar, ou escreva um pedido para um agente (@nome texto)…", text: $termo)
          .textFieldStyle(.plain).font(F.ui(15)).focused($focado)
          .onSubmit { executar(lista) }
          .onKeyPress(.downArrow) { sel = min(sel + 1, lista.count - 1); return .handled }
          .onKeyPress(.upArrow) { sel = max(sel - 1, 0); return .handled }
          .onKeyPress(.escape) { loja.paletaAberta = false; return .handled }
        Text("esc").font(F.ui(10.5)).foregroundStyle(Cor.texto4)
      }
      .padding(.horizontal, 16).frame(height: 52)
      Divider().opacity(0.5)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lista.enumerated()), id: \.element.id) { i, item in
              if i == 0 || lista[i - 1].grupo != item.grupo {
                Text(item.grupo.uppercased()).font(F.ui(10, .semibold)).kerning(0.6).foregroundStyle(Cor.texto4)
                  .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 3)
              }
              linha(item, selecionado: i == sel).id(i)
                .onTapGesture { sel = i; executar(lista) }
            }
            if lista.isEmpty { Text("Nada encontrado").foregroundStyle(Cor.texto3).frame(maxWidth: .infinity).padding(24) }
          }
          .padding(6)
        }
        .onChange(of: sel) { _, v in proxy.scrollTo(v, anchor: nil) }
      }
      .frame(maxHeight: 380)
    }
    .frame(width: 600)
    .cartaoFlutuante()
    .padding(.top, 90)
    .onAppear { focado = true; sel = 0 }
    .onChange(of: termo) { _, _ in sel = 0 }
  }

  @ViewBuilder func linha(_ item: Item, selecionado: Bool) -> some View {
    HStack(spacing: 11) {
      Group {
        if let ps = item.persona { AvatarPersona(persona: ps, tamanho: 24, fixo: true) }
        else if let p = item.programa { IconePrograma(processo: p, tamanho: 24) }
        else if let c = item.cor { Circle().fill(Color(hex: c)).frame(width: 10, height: 10).frame(width: 20) }
        else { Image(systemName: item.simbolo ?? "circle").font(F.ui(13)).foregroundStyle(Cor.texto2).frame(width: 20) }
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(item.rotulo).font(F.ui(13)).foregroundStyle(Cor.texto).lineLimit(1)
        if !item.detalhe.isEmpty { Text(item.detalhe).font(F.mono(11)).foregroundStyle(Cor.texto3).lineLimit(1) }
      }
      Spacer()
      if item.marcado { Image(systemName: "checkmark").foregroundStyle(Cor.acento) }
      if !item.atalho.isEmpty { Text(item.atalho).font(F.ui(11)).foregroundStyle(Cor.texto3) }
    }
    .padding(.horizontal, 10).frame(minHeight: F.m(36))
    .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(selecionado ? Cor.acento.opacity(0.2) : .clear))
    .contentShape(Rectangle())
  }

  func executar(_ lista: [Item]) {
    guard sel < lista.count else { return }
    let item = lista[sel]
    loja.paletaAberta = false
    DispatchQueue.main.async {
      item.rodar()
      loja.devolverFoco()
    }
  }
}
