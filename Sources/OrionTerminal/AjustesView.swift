import SwiftUI
import AppKit

// Janela de ajustes (⌘,). Pouco texto e controles que mostram o que fazem: cada ajuste é uma
// linha com ícone, nome e o controle; a Aparência tem uma prévia ao vivo. A busca acha um ajuste
// em qualquer seção. Feita com peças leves (sem Form): abrir os ajustes não infla a memória.

/// Um ajuste: o que aparece numa linha e as palavras pelas quais a busca o encontra.
struct ItemAjuste: Identifiable {
  let id: String
  let secao: String
  let grupo: String
  let simbolo: String
  let titulo: String
  var dica = ""
  var palavras = ""
  var largo = false          // o controle ocupa a linha inteira, abaixo do título
  let controle: AnyView

  init<V: View>(_ id: String, _ secao: String, _ grupo: String, _ simbolo: String, _ titulo: String, dica: String = "", palavras: String = "",
                largo: Bool = false, @ViewBuilder _ controle: () -> V) {
    self.id = id; self.secao = secao; self.grupo = grupo; self.simbolo = simbolo; self.titulo = titulo
    self.dica = dica; self.palavras = palavras; self.largo = largo; self.controle = AnyView(controle())
  }
}

struct AjustesView: View {
  @Bindable var loja: Loja
  @Estado var secao: String
  @Estado private var busca = ""

  struct Secao { let id: String; let nome: String; let simbolo: String }
  static let secoes: [Secao] = [
    Secao(id: "aparencia", nome: "Aparência", simbolo: "paintpalette"),
    Secao(id: "interface", nome: "Janela", simbolo: "macwindow"),
    Secao(id: "agentes", nome: "Agentes", simbolo: "person.2.wave.2"),
    Secao(id: "workspaces", nome: "Workspaces", simbolo: "square.stack.3d.up"),
    Secao(id: "contas", nome: "Contas e uso", simbolo: "person.crop.circle"),
    Secao(id: "terminal", nome: "Terminal", simbolo: "terminal"),
    Secao(id: "avisos", nome: "Avisos", simbolo: "bell"),
    Secao(id: "ia", nome: "IA e CLI", simbolo: "sparkles"),
    Secao(id: "atalhos", nome: "Atalhos", simbolo: "keyboard"),
    Secao(id: "sobre", nome: "Sobre e atualizações", simbolo: "arrow.down.circle"),
  ]

  /// Nomes antigos de seção continuam funcionando em `orion ui ajustes <seção>`.
  static func normalizar(_ s: String) -> String {
    switch s {
    case "janela": return "interface"
    case "abas": return "workspaces"
    case "sugestoes": return "terminal"
    case "compose", "personagens": return "agentes"
    case "atualizacoes", "atualizacao", "versao": return "sobre"
    default: return secoes.contains { $0.id == s } ? s : "aparencia"
    }
  }

  var body: some View {
    let atual = AjustesView.normalizar(secao)
    let termo = busca.trimmingCharacters(in: .whitespaces).lowercased()
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Color.clear.frame(height: 30)
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").font(.system(size: 11.5)).foregroundStyle(Cor.texto3)
          TextField("", text: $busca, prompt: Text("Buscar ajuste").foregroundStyle(Cor.texto4)).textFieldStyle(.plain).font(F.ui(12.5))
          if !busca.isEmpty { Button { busca = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Cor.texto3) }.buttonStyle(.plain).help("Limpar a busca") }
        }
        .padding(.horizontal, 9).frame(height: F.m(30))
        .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.vidro))
        .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(Cor.linha))
        .padding(.bottom, 8)
        ForEach(AjustesView.secoes, id: \.id) { s in
          let ativo = atual == s.id && termo.isEmpty
          Button { busca = ""; secao = s.id } label: {
            HStack(spacing: 9) {
              Image(systemName: s.simbolo).font(.system(size: 14, weight: .medium)).frame(width: 20).foregroundStyle(ativo ? Cor.acento : Cor.texto2)
              Text(s.nome).font(F.ui(13, ativo ? .semibold : .regular)).foregroundStyle(ativo ? Cor.texto : Cor.texto2)
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: F.m(34))
            .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(ativo ? Cor.elevado : .clear))
            .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(ativo ? Cor.linhaForte : .clear))
            .contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
        Spacer()
        HStack(spacing: 7) {
          Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
          Text("Orion Terminal \(Shell.versao)").font(F.ui(11)).foregroundStyle(Cor.texto3)
        }
        .padding(10)
      }
      .padding(.horizontal, 10).frame(width: 200)
      .background(Cor.claro ? Color.black.opacity(0.035) : Color.black.opacity(0.22))
      Rectangle().fill(Cor.linha).frame(width: 1)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if !termo.isEmpty {
            let achados = itens().filter { "\($0.titulo) \($0.dica) \($0.palavras) \($0.grupo)".lowercased().contains(termo) }
            Text(achados.isEmpty ? "Nada encontrado para “\(busca)”" : "\(achados.count) ajuste\(achados.count == 1 ? "" : "s")")
              .font(F.ui(19, .semibold)).foregroundStyle(Cor.texto)
            ForEach(AjustesView.secoes, id: \.id) { s in
              let dela = achados.filter { $0.secao == s.id }
              if !dela.isEmpty { GrupoAjustes(titulo: s.nome, itens: dela) }
            }
          } else {
            Text(AjustesView.secoes.first { $0.id == atual }?.nome ?? "").font(F.ui(20, .semibold)).foregroundStyle(Cor.texto)
            switch atual {
            case "aparencia": PreviaJanela(loja: loja); grupos(atual)
            case "workspaces": AjustesWorkspaces(loja: loja); grupos(atual)
            case "contas": grupos(atual); GerenciadorContas(loja: loja)
            case "ia": grupos(atual); BlocoExemplos()
            case "atalhos": ListaAtalhos()
            case "sobre": SobreAtualizacoes(loja: loja)
            default: grupos(atual)
            }
          }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay { CamadaDialogo(loja: loja, emAjustes: true) }
    .background(Cor.claro ? loja.tema.janelaUI : loja.tema.fundoUI)
    .tint(Cor.acento)
    .preferredColorScheme(Cor.claro ? .light : .dark)
    .ignoresSafeArea()
  }

  /// Os grupos de uma seção, na ordem em que os itens foram declarados.
  @ViewBuilder func grupos(_ secao: String) -> some View {
    let dela = itens(so: secao)
    var ordem: [String] = []
    let _ = dela.forEach { if !ordem.contains($0.grupo) { ordem.append($0.grupo) } }
    ForEach(ordem, id: \.self) { g in GrupoAjustes(titulo: g, itens: dela.filter { $0.grupo == g }) }
  }

  // MARK: - Todos os ajustes

  /// `so`: monta só os ajustes daquela seção (a busca monta todos).
  func itens(so: String? = nil) -> [ItemAjuste] {
    let a = $loja.ajustes
    let _ = loja.versaoTemas
    var it: [ItemAjuste] = []
    func quer(_ s: String) -> Bool { so == nil || so == s }

    // Aparência
    if quer("aparencia") {
    it.append(ItemAjuste("modo", "aparencia", "Modo", "circle.lefthalf.filled", "Aparência", palavras: "claro escuro sistema dark light automático") {
      Escolha(valor: a.aparencia, opcoes: [("escuro", "Escuro", "moon.fill"), ("claro", "Claro", "sun.max.fill"), ("sistema", "Automático", "circle.lefthalf.filled")])
    })
    if let id = loja.temaEmEdicao, let t = Tema.personalizados.first(where: { $0.id == id }) {
      it.append(ItemAjuste("editor", "aparencia", "Editar tema", "paintbrush", t.nome, palavras: "cores ansi editor", largo: true) { EditorTema(loja: loja, tema: t) })
    }
    it.append(ItemAjuste("temasEscuros", "aparencia", "Tema", "moon.stars", "Escuros", palavras: "tema cores dracula nord gruvbox", largo: true) {
      GradeTemas(loja: loja, temas: Tema.todos.filter { !$0.claro })
    })
    it.append(ItemAjuste("temasClaros", "aparencia", "Tema", "sun.max", "Claros", palavras: "tema cores latte nuvem papel", largo: true) {
      VStack(alignment: .leading, spacing: 10) {
        GradeTemas(loja: loja, temas: Tema.todos.filter { $0.claro })
        HStack(spacing: 8) {
          BotaoAjuste(titulo: "Criar a partir de “\(loja.tema.nome)”", simbolo: "plus.square.on.square") {
            let n = Tema.duplicar(loja.tema); loja.versaoTemas += 1; loja.escolherTema(n); loja.temaEmEdicao = n.id
          }
          BotaoAjuste(titulo: "Importar…", simbolo: "square.and.arrow.down") { AjustesView.importarTema(loja) }
        }
      }
    })
    it.append(ItemAjuste("transparencia", "aparencia", "Vidro", "square.on.square.dashed", "Transparência", dica: "Quanto dá para ver o que está atrás da janela",
                         palavras: "opacidade vidro transparente fundo") {
      Deslizante(valor: Binding(get: { 1 - loja.ajustes.opacidade }, set: { loja.ajustes.opacidade = 1 - $0 }), faixa: 0...0.9, passo: 0.02) { "\(Int(($0 * 100).rounded()))%" }
        .disabled(loja.tema.opacidade != nil)
    })
    it.append(ItemAjuste("desfoque", "aparencia", "Vidro", "drop", "Desfoque", dica: "0 = nítido; mais = fosco", palavras: "blur fosco vidro") {
      Deslizante(valor: a.desfoqueRaio, faixa: 0...40, passo: 1) { $0 == 0 ? "nítido" : "\(Int($0))" }
        .disabled(!loja.translucido)
    })
    it.append(ItemAjuste("escalaUI", "aparencia", "Interface", "textformat.size", "Tamanho da letra", dica: "Menus, barras e cartões (não o terminal)", palavras: "fonte interface zoom ui") {
      Deslizante(valor: a.escalaUI, faixa: 0.85...1.4, passo: 0.05) { "\(Int(($0 * 100).rounded()))%" }
    })
    it.append(ItemAjuste("tamanhoMascote", "aparencia", "Interface", "face.smiling", "Tamanho dos mascotes", dica: "Agentes na barra lateral, no chat e no quadro", palavras: "pet avatar personagem mascote tamanho") {
      Escolha(valor: Binding(get: { String(format: "%.2f", loja.ajustes.tamanhoMascote) }, set: { loja.ajustes.tamanhoMascote = Double($0) ?? 1.15 }),
              opcoes: [("0.90", "Pequeno", nil), ("1.15", "Médio", nil), ("1.35", "Grande", nil)])
    })
    it.append(ItemAjuste("mascotesAnimados", "aparencia", "Interface", "sparkles", "Mascotes animados",
                         dica: "Piscam, olham em volta e respiram — só com o app na frente", palavras: "animação mascote piscar movimento cpu") {
      Chave(a.mascotesAnimados)
    })
    it.append(ItemAjuste("raio", "aparencia", "Interface", "app", "Cantos", palavras: "arredondamento raio quadrado") {
      Deslizante(valor: a.raio, faixa: 4...22, passo: 1) { "\(Int($0)) px" }
    })
    it.append(ItemAjuste("sombras", "aparencia", "Interface", "square.2.layers.3d", "Sombra nos painéis", palavras: "profundidade sombra") { Chave(a.sombras) })
    it.append(ItemAjuste("fonte", "aparencia", "Letra do terminal", "character.cursor.ibeam", "Fonte", palavras: "fonte mono família") {
      SeletorFonte(loja: loja)
    })
    it.append(ItemAjuste("tamanho", "aparencia", "Letra do terminal", "textformat.size.larger", "Tamanho", palavras: "fonte terminal") {
      Deslizante(valor: a.tamanho, faixa: 9...24, passo: 0.5) { String(format: "%.1f pt", $0).replacingOccurrences(of: ".0", with: "") }
    })
    it.append(ItemAjuste("cursor", "aparencia", "Letra do terminal", "cursorarrow.rays", "Cursor", palavras: "barra bloco sublinhado") {
      Escolha(valor: a.cursor, opcoes: [("barra", "Barra", "poweron"), ("bloco", "Bloco", "square.fill"), ("sublinhado", "Linha", "underline")])
    })
    it.append(ItemAjuste("margem", "aparencia", "Letra do terminal", "rectangle.inset.filled", "Margem interna", palavras: "espaço borda") {
      Deslizante(valor: a.margem, faixa: 0...28, passo: 1) { "\(Int($0)) px" }
    })
    }

    // Janela
    if quer("interface") {
    it.append(ItemAjuste("barraLateral", "interface", "O que aparece", "sidebar.left", "Barra lateral", dica: "⌘B", palavras: "trilho abas workspaces") { Chave(a.barraLateral) })
    it.append(ItemAjuste("barraAgentes", "interface", "O que aparece", "rectangle.bottomthird.inset.filled", "Barra de agentes", dica: "⇧⌘B", palavras: "rodapé embaixo") { Chave(a.barraAgentes) })
    it.append(ItemAjuste("doca", "interface", "O que aparece", "dock.rectangle", "Doca", dica: "Quadro, ferramentas e terminal", palavras: "botões flutuante") { Chave(a.doca) })
    it.append(ItemAjuste("memoria", "interface", "O que aparece", "memorychip", "Memória", dica: "Do app e de cada agente", palavras: "ram") { Chave(a.memoria) })
    it.append(ItemAjuste("portas", "interface", "O que aparece", "network", "Portas em uso", dica: "Servidores que os painéis subiram", palavras: "servidor localhost listen") { Chave(a.portas) })
    it.append(ItemAjuste("larguraLateral", "interface", "Tamanhos", "arrow.left.and.right", "Largura da barra lateral", palavras: "lateral largura") {
      Deslizante(valor: a.larguraLateral, faixa: 190...420, passo: 4) { "\(Int($0)) px" }
    })
    for f in Ferramenta.todas {
      it.append(ItemAjuste("mostrar-\(f.id)", "interface", "Ferramentas à mostra", "app.badge", f.nomeLongo, palavras: "claude codex gemini esconder ferramenta") {
        HStack(spacing: 8) {
          IconePrograma(processo: f.id, tamanho: 20)
          Chave(Binding(get: { !loja.ajustes.ferramentasOcultas.contains(f.id) },
                        set: { v in loja.ajustes.ferramentasOcultas.removeAll { $0 == f.id }; if !v { loja.ajustes.ferramentasOcultas.append(f.id) } }))
        }
      })
    }
    }

    // Agentes
    if quer("agentes") {
    it.append(ItemAjuste("compose", "agentes", "Compose", "square.and.pencil", "Caixa de escrita", dica: "⌘E leva o teclado até ela", palavras: "compose mensagem escrever") {
      Escolha(valor: a.compose, opcoes: [("agentes", "Nos agentes", "person.fill"), ("sempre", "Sempre", "infinity"), ("manual", "Só com ⌘E", "keyboard")])
    })
    it.append(ItemAjuste("clique", "agentes", "Botões do Claude, Codex e Gemini", "cursorarrow.click", "Um clique", dica: "⌥ clique faz o contrário",
                         palavras: "clique botão ferramenta painel novo") {
      Escolha(valor: a.cliqueFerramenta, opcoes: [("painel", "Abre o painel", "rectangle.expand.vertical"), ("novo", "Abre um agente", "plus")])
    })
    it.append(ItemAjuste("retomar", "agentes", "Sessões", "arrow.uturn.backward", "Retomar a conversa", dica: "Ao reabrir o app ou um agente fechado", palavras: "continue resume sessão") { Chave(a.retomarAgentes) })
    it.append(ItemAjuste("hibernar", "agentes", "Memória", "moon.zzz", "Hibernar agente parado após",
                         dica: "Fora da tela, sem servidor nem comando rodando: o processo fecha e volta na mesma conversa ao abrir",
                         palavras: "ram memória dormir suspender resume liberar") {
      Escolha(valor: Binding(get: { String(Int(loja.ajustes.hibernarMinutos)) }, set: { loja.ajustes.hibernarMinutos = Double($0) ?? 30 }),
              opcoes: [("0", "Nunca", nil), ("15", "15 min", nil), ("30", "30 min", nil), ("60", "1 h", nil), ("180", "3 h", nil)])
    })
    it.append(ItemAjuste("restaurar", "agentes", "Sessões", "clock.arrow.circlepath", "Reabrir tudo ao abrir o app", palavras: "restaurar abas workspaces") { Chave(a.restaurar) })
    it.append(ItemAjuste("confirmar", "agentes", "Sessões", "hand.raised", "Confirmar antes de fechar algo rodando", palavras: "fechar confirmação") { Chave(a.confirmarFechar) })
    it.append(ItemAjuste("pastaAtual", "agentes", "Sessões", "folder", "Nova aba na pasta do painel atual", dica: "Desligado: na pasta do workspace", palavras: "pasta cwd nova aba") { Chave(a.novaAbaNaPastaAtual) })
    it.append(ItemAjuste("cmdClaude", "agentes", "Comandos", "terminal", "Claude", palavras: "comando binário") { CampoAjuste(texto: a.comandoClaude, dica: "claude") })
    it.append(ItemAjuste("cmdCodex", "agentes", "Comandos", "terminal", "Codex", palavras: "comando binário") { CampoAjuste(texto: a.comandoCodex, dica: "codex") })
    it.append(ItemAjuste("cmdGemini", "agentes", "Comandos", "terminal", "Gemini", palavras: "comando binário") { CampoAjuste(texto: a.comandoGemini, dica: "gemini") })
    }

    // Contas e uso
    if quer("contas") {
    it.append(ItemAjuste("usoClaude", "contas", "Uso", "chart.bar", "Uso do Claude (5 h e 7 dias)", dica: "Lê o login do Chaveiro e consulta só a página de uso",
                         palavras: "limite uso chaveiro anthropic") {
      Escolha(valor: a.usoClaude, opcoes: [("ligado", "Mostrar", "eye"), ("perguntar", "Perguntar", "questionmark"), ("desligado", "Não", "eye.slash")])
    })
    it.append(ItemAjuste("usoIntervalo", "contas", "Uso", "timer", "Atualizar a cada", palavras: "intervalo minutos") {
      HStack(spacing: 8) {
        Escolha(valor: Binding(get: { String(Int(loja.ajustes.usoIntervalo)) }, set: { loja.ajustes.usoIntervalo = Double($0) ?? 5 }),
                opcoes: [("2", "2 min", nil), ("5", "5 min", nil), ("10", "10 min", nil), ("30", "30 min", nil)])
        BotaoAjuste(titulo: "Agora", simbolo: "arrow.clockwise") { loja.atualizarUsos(forcar: true) }
      }
    })
    }

    // Terminal
    if quer("terminal") {
    it.append(ItemAjuste("shell", "terminal", "Shell", "chevron.right.square", "Shell", palavras: "zsh bash fish") { CampoAjuste(texto: a.shell, dica: Shell.padrao) })
    it.append(ItemAjuste("rolagem", "terminal", "Shell", "arrow.up.and.down", "Linhas guardadas", dica: "Menos linhas = menos memória", palavras: "rolagem scrollback histórico") {
      Escolha(valor: Binding(get: { String(loja.ajustes.rolagem) }, set: { loja.ajustes.rolagem = Int($0) ?? 5000 }),
              opcoes: [("1000", "1 mil", nil), ("5000", "5 mil", nil), ("10000", "10 mil", nil), ("50000", "50 mil", nil)])
    })
    it.append(ItemAjuste("copiarAoSelecionar", "terminal", "Teclado", "doc.on.doc", "Copiar ao selecionar", dica: "Selecionar com o mouse já copia (como no iTerm)", palavras: "copiar selecao clipboard area de transferencia") { Chave(a.copiarAoSelecionar) })
    it.append(ItemAjuste("optionMeta", "terminal", "Teclado", "option", "Option como Meta", dica: "⌥B / ⌥F andam por palavras", palavras: "alt meta") { Chave(a.optionMeta) })
    it.append(ItemAjuste("gpu", "terminal", "Desenho", "cpu", "Desenhar pela placa de vídeo", dica: "Mais fluido com muita saída", palavras: "gpu metal renderização") { Chave(a.gpu) })
    it.append(ItemAjuste("sugestoes", "terminal", "Autocomplete", "text.badge.plus", "Sugestões embaixo do que digito", dica: "⌃Espaço abre", palavras: "autocomplete completar") { Chave(a.sugestoes) })
    it.append(ItemAjuste("sugestoesAuto", "terminal", "Autocomplete", "bolt", "Mostrar enquanto digito", palavras: "autocomplete automático") { Chave(a.sugestoesAuto).disabled(!loja.ajustes.sugestoes) })
    }

    // Avisos
    if quer("avisos") {
    it.append(ItemAjuste("avisarAgentes", "avisos", "Notificar quando", "person.wave.2", "Um agente parou e espera você", palavras: "notificação claude codex") { Chave(a.avisarAgentes) })
    it.append(ItemAjuste("avisarComandos", "avisos", "Notificar quando", "checkmark.circle", "Um comando demorado terminou", palavras: "notificação comando") { Chave(a.avisarComandos) })
    it.append(ItemAjuste("comandoLongo", "avisos", "Notificar quando", "hourglass", "Demorado é a partir de", palavras: "segundos tempo") {
      Deslizante(valor: a.comandoLongo, faixa: 5...120, passo: 5) { "\(Int($0)) s" }.disabled(!loja.ajustes.avisarComandos)
    })
    }

    // IA e CLI
    if quer("ia") {
    it.append(ItemAjuste("cli", "ia", "Comando orion", "terminal", "Instalar em ~/.local/bin", dica: "Para usar `orion` em qualquer terminal", palavras: "cli instalar comando") {
      BotaoAjuste(titulo: "Instalar", simbolo: "arrow.down.circle") { (NSApp.delegate as? Delegado)?.instalarCLI() }
    })
    it.append(ItemAjuste("guia", "ia", "Comando orion", "doc.on.clipboard", "Instruções para o CLAUDE.md / AGENTS.md", dica: "Ensina o agente a ser maestro e a usar o orion",
                         palavras: "guia instruções maestro subagente") {
      BotaoAjuste(titulo: "Copiar", simbolo: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(GuiaIA.texto, forType: .string) }
    })
    }

    return it
  }

  static func importarTema(_ loja: Loja) {
    let p = NSOpenPanel()
    p.allowedContentTypes = [.json]
    p.message = "Escolha um tema exportado pelo Orion Terminal (.json)."
    guard p.runModal() == .OK, let u = p.url else { return }
    if let t = Tema.importar(u) { loja.versaoTemas += 1; loja.escolherTema(t) }
    else { loja.avisar("Não consegui ler o tema", "O arquivo não parece um tema do Orion Terminal.", simbolo: "exclamationmark.triangle.fill") }
  }
}

// MARK: - Peças

/// Um grupo de ajustes: título pequeno e um cartão com as linhas.
struct GrupoAjustes: View {
  let titulo: String
  let itens: [ItemAjuste]
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(titulo.uppercased()).font(F.ui(10.5, .semibold)).kerning(0.5).foregroundStyle(Cor.texto3).padding(.leading, 4)
      VStack(spacing: 0) {
        ForEach(Array(itens.enumerated()), id: \.element.id) { i, item in
          if i > 0 { Rectangle().fill(Cor.linha).frame(height: 1).padding(.leading, 44) }
          LinhaAjuste(item: item)
        }
      }
      .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(Cor.elevado))
      .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linha))
    }
  }
}

struct LinhaAjuste: View {
  let item: ItemAjuste
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 11) {
        Image(systemName: item.simbolo).font(.system(size: 13, weight: .medium)).foregroundStyle(Cor.acento)
          .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Cor.acento.opacity(0.13)))
        VStack(alignment: .leading, spacing: 1) {
          Text(item.titulo).font(F.ui(13)).foregroundStyle(Cor.texto).lineLimit(1)
          if !item.dica.isEmpty { Text(item.dica).font(F.ui(11)).foregroundStyle(Cor.texto3).lineLimit(1) }
        }
        Spacer(minLength: 10)
        if !item.largo { item.controle }
      }
      if item.largo { item.controle }
    }
    .padding(.horizontal, 12).padding(.vertical, 9)
    .frame(minHeight: F.m(44))
  }
}

/// Fonte do terminal: o nome da atual; a lista das fontes mono só é levantada ao clicar (percorrer
/// todas as fontes instaladas custa memória que não volta — não vale fazer só por abrir os ajustes).
struct SeletorFonte: View {
  @Bindable var loja: Loja
  @Estado private var aberto = false
  @Estado private var fontes: [String] = []
  var body: some View {
    Button { aberto.toggle() } label: {
      HStack(spacing: 6) {
        Text(loja.ajustes.fonte).font(F.ui(12, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Cor.texto3)
      }
      .padding(.horizontal, 10).frame(height: F.m(26))
      .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(Cor.vidro2))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).help("Escolher a fonte do terminal")
    .popover(isPresented: $aberto, arrowEdge: .bottom) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          if fontes.isEmpty { Text("Procurando fontes mono…").font(F.ui(12)).foregroundStyle(Cor.texto3).padding(10) }
          ForEach(fontes, id: \.self) { f in
            Button { loja.ajustes.fonte = f; aberto = false } label: {
              HStack {
                Text(f).font(.custom(f, size: 13)).foregroundStyle(Cor.texto).lineLimit(1)
                Spacer()
                if f == loja.ajustes.fonte { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Cor.acento) }
              }
              .padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        }
        .padding(6)
      }
      .frame(width: 300, height: 320)
      .onAppear {
        guard fontes.isEmpty else { return }
        DispatchQueue.global().async { let f = Armazem.fontesMono(); DispatchQueue.main.async { fontes = Array(Set(f + [loja.ajustes.fonte])).sorted() } }
      }
    }
  }
}

/// Interruptor.
struct Chave: View {
  @Binding var ligado: Bool
  init(_ b: Binding<Bool>) { _ligado = b }
  var body: some View { Toggle("", isOn: $ligado).toggleStyle(.switch).labelsHidden().controlSize(.small) }
}

/// Escolha entre poucas opções, todas à vista (com ícone quando ajuda).
struct Escolha: View {
  @Binding var valor: String
  let opcoes: [(String, String, String?)]
  var body: some View {
    HStack(spacing: 2) {
      ForEach(opcoes, id: \.0) { id, nome, simbolo in
        let ativo = valor == id
        Button { valor = id } label: {
          HStack(spacing: 5) {
            if let simbolo { Image(systemName: simbolo).font(.system(size: 10.5, weight: .semibold)) }
            Text(nome).font(F.ui(12, ativo ? .semibold : .regular)).lineLimit(1)
          }
          .foregroundStyle(ativo ? Cor.sobreAcento : Cor.texto2)
          .padding(.horizontal, 10).frame(height: F.m(26))
          .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(ativo ? Cor.acento : .clear))
          .contentShape(Rectangle())
        }.buttonStyle(.plain)
      }
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: R.pequeno + 3, style: .continuous).fill(Cor.vidro2))
    .fixedSize()
  }
}

/// Controle deslizante com o valor ao lado.
struct Deslizante: View {
  @Binding var valor: Double
  let faixa: ClosedRange<Double>
  var passo: Double = 1
  let formato: (Double) -> String
  var body: some View {
    HStack(spacing: 8) {
      Slider(value: $valor, in: faixa, step: passo).controlSize(.small).frame(width: 190)
      Text(formato(valor)).font(F.ui(11.5)).monospacedDigit().foregroundStyle(Cor.texto2).frame(width: 54, alignment: .trailing)
    }
  }
}

struct CampoAjuste: View {
  @Binding var texto: String
  var dica = ""
  var body: some View {
    TextField("", text: $texto, prompt: Text(dica).foregroundStyle(Cor.texto4)).textFieldStyle(.plain).font(F.mono(12))
      .padding(.horizontal, 8).frame(width: 240, height: F.m(26))
      .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(Cor.vidro2))
  }
}

struct BotaoAjuste: View {
  let titulo: String
  var simbolo: String? = nil
  var destrutivo = false
  let acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    Button(action: acao) {
      HStack(spacing: 5) {
        if let simbolo { Image(systemName: simbolo).font(.system(size: 10.5, weight: .semibold)) }
        Text(titulo).font(F.ui(12, .medium)).lineLimit(1)
      }
      .foregroundStyle(destrutivo ? Cor.vermelho : Cor.texto)
      .padding(.horizontal, 10).frame(height: F.m(26))
      .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(sobre ? Cor.linhaForte : Cor.vidro2))
      .contentShape(Rectangle())
    }.buttonStyle(.plain).onHover { sobre = $0 }
  }
}

/// Prévia ao vivo: uma janelinha sobre um "fundo de tela", com o tema, a transparência, o desfoque,
/// os cantos e o tamanho da letra do jeito que estão agora.
struct PreviaJanela: View {
  @Bindable var loja: Loja
  var body: some View {
    let t = loja.tema
    let o = loja.opacidade
    let raio = CGFloat(loja.ajustes.raio)
    ZStack {
      // O que estaria atrás da janela (para a transparência e o desfoque aparecerem).
      ZStack {
        LinearGradient(colors: [Color(hex: "#2b5cff"), Color(hex: "#ff7a59"), Color(hex: "#ffd166")], startPoint: .topLeading, endPoint: .bottomTrailing)
        HStack(spacing: 14) { ForEach(0..<9) { i in RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(i % 2 == 0 ? 0.55 : 0.2)).frame(width: 26) } }.rotationEffect(.degrees(18)).scaleEffect(1.5)
        Text("o que está atrás").font(.system(size: 22, weight: .heavy)).foregroundStyle(.black.opacity(0.55)).offset(x: 60, y: 18)
      }
      .blur(radius: loja.translucido ? loja.ajustes.desfoqueRaio * 0.35 : 0)
      .clipped()
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(Persona.elenco.prefix(3).enumerated()), id: \.offset) { i, p in
            HStack(spacing: 6) {
              AvatarPersona(persona: p, tamanho: 20)
              VStack(alignment: .leading, spacing: 0) {
                Text(["Revisar landing", "API de leads", "Testes"][i]).font(F.ui(10.5, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
                Text(p.nome).font(F.ui(9)).foregroundStyle(Cor.texto3)
              }
            }
          }
          Spacer(minLength: 0)
        }
        .frame(width: 104, alignment: .leading)
        VStack(alignment: .leading, spacing: 3) {
          (Text("~/projeto ").foregroundColor(Color(hex: t.ansi[4])) + Text("❯ ").foregroundColor(Color(hex: t.ansi[2])) + Text("npm run dev").foregroundColor(Color(hex: t.texto)))
          (Text("✓ ").foregroundColor(Color(hex: t.ansi[2])) + Text("pronto em 412 ms").foregroundColor(Color(hex: t.texto)))
          (Text("➜ ").foregroundColor(Color(hex: t.ansi[6])) + Text("http://localhost:3000").foregroundColor(Color(hex: t.ansi[4])))
          Spacer(minLength: 0)
        }
        .font(.system(size: max(9, loja.ajustes.tamanho * 0.85), design: .monospaced))
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: raio * 0.8, style: .continuous).fill(t.fundoUI.opacity(o >= 0.995 ? 1 : max(0.10, o * 0.55))))
        .overlay(RoundedRectangle(cornerRadius: raio * 0.8, style: .continuous).strokeBorder(Cor.linhaForte))
        .shadow(color: loja.ajustes.sombras ? .black.opacity(t.claro ? 0.15 : 0.4) : .clear, radius: 6, y: 2)
      }
      .padding(10)
      .background(RoundedRectangle(cornerRadius: raio, style: .continuous).fill(t.janelaUI.opacity(o)))
      .overlay(RoundedRectangle(cornerRadius: raio, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
      .padding(.horizontal, 46).padding(.vertical, 16)
    }
    .frame(height: 150)
    .clipShape(RoundedRectangle(cornerRadius: R.cartao, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linha))
  }
}

/// Lista de workspaces: nome, pasta, cor, símbolo e ordem.
struct AjustesWorkspaces: View {
  @Bindable var loja: Loja
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("SEUS WORKSPACES").font(F.ui(10.5, .semibold)).kerning(0.5).foregroundStyle(Cor.texto3).padding(.leading, 4)
      VStack(spacing: 0) {
        ForEach(Array(loja.workspaces.enumerated()), id: \.element.id) { i, w in
          if i > 0 { Rectangle().fill(Cor.linha).frame(height: 1).padding(.leading, 52) }
          LinhaAjusteWorkspace(loja: loja, ws: w, numero: i + 1)
        }
      }
      .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(Cor.elevado))
      .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linha))
      BotaoAjuste(titulo: "Novo workspace", simbolo: "plus") { loja.novoWorkspacePerguntando() }.padding(.top, 4)
    }
  }
}

struct LinhaAjusteWorkspace: View {
  @Bindable var loja: Loja
  @Bindable var ws: Workspace
  let numero: Int

  var body: some View {
    let n = loja.abas(de: ws).count
    HStack(spacing: 10) {
      Menu {
        Section("Cor") {
          ForEach(Cor.paletaGrupos, id: \.self) { c in Button { ws.cor = c; loja.salvarDepois() } label: { Label(nomeCor(c), systemImage: ws.cor == c ? "checkmark" : "circle.fill") } }
        }
        Section("Símbolo") {
          ForEach(Workspace.simbolos, id: \.self) { s in Button { ws.simbolo = s; loja.salvarDepois() } label: { Label(s, systemImage: s) } }
        }
      } label: { SimboloWorkspace(ws: ws, tamanho: 30) }
      .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Trocar a cor e o símbolo")
      VStack(alignment: .leading, spacing: 2) {
        TextField("", text: $ws.nome, prompt: Text("Nome")).labelsHidden().textFieldStyle(.plain).font(F.ui(13, .semibold))
          .onChange(of: ws.nome) { _, _ in loja.salvarDepois() }
        Text("\(Loja.encurtar(ws.pasta)) · \(n) aba\(n == 1 ? "" : "s")\(numero <= 9 ? " · ⌃\(numero)" : "")")
          .font(F.ui(11)).foregroundStyle(Cor.texto3).lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: 6)
      BotaoMini("folder", "Trocar a pasta do workspace") { loja.escolherPasta(ws) }
      BotaoMini("arrow.up", "Mover para cima") { loja.moverWorkspace(ws, -1) }.disabled(numero == 1).opacity(numero == 1 ? 0.3 : 1)
      BotaoMini("arrow.down", "Mover para baixo") { loja.moverWorkspace(ws, 1) }.disabled(numero == loja.workspaces.count).opacity(numero == loja.workspaces.count ? 0.3 : 1)
      BotaoMini("trash", "Fechar o workspace e as abas dele") { loja.fecharWorkspace(ws) }
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
  }
}

/// Contas de cada ferramenta: um cartão por conta, com uso e ações.
struct GerenciadorContas: View {
  @Bindable var loja: Loja
  var body: some View {
    ForEach(Ferramenta.todas) { f in
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          IconePrograma(processo: f.id, tamanho: 16)
          Text(f.nomeLongo.uppercased()).font(F.ui(10.5, .semibold)).kerning(0.5).foregroundStyle(Cor.texto3)
        }.padding(.leading, 4)
        VStack(spacing: 0) {
          ForEach(Array(loja.contas(f.id).enumerated()), id: \.element.id) { i, c in
            if i > 0 { Rectangle().fill(Cor.linha).frame(height: 1).padding(.leading, 52) }
            CartaoConta(loja: loja, conta: c)
          }
        }
        .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(Cor.elevado))
        .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linha))
        BotaoAjuste(titulo: "Adicionar conta do \(f.nome)", simbolo: "plus") { loja.novaContaPerguntando(f.id) }.padding(.top, 2)
          .help("Cria um perfil separado (\(f.variavel)) e abre uma aba nele para o login")
      }
    }
  }
}

struct CartaoConta: View {
  @Bindable var loja: Loja
  let conta: Conta

  var body: some View {
    let padrao = loja.contaPadrao(conta.tipo)?.id == conta.id
    let uso = loja.usos[conta.id]
    HStack(alignment: .center, spacing: 10) {
      Text(String(conta.nome.prefix(1)).uppercased()).font(F.ui(13, .bold)).foregroundStyle(.white)
        .frame(width: 30, height: 30).background(Circle().fill(Color(hex: conta.cor)))
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(conta.nome).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
          if padrao { Text("padrão").font(F.ui(10, .semibold)).foregroundStyle(Cor.acento).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Cor.acento.opacity(0.15))) }
        }
        Text(conta.logado ? [conta.email, conta.plano.contains("_") ? "" : conta.plano].filter { !$0.isEmpty }.joined(separator: " · ") : "sem login — abra e entre")
          .font(F.ui(11)).foregroundStyle(conta.logado ? Cor.texto3 : Cor.amarelo).lineLimit(1).truncationMode(.middle)
        if let u = uso, loja.podeLerUso(conta), u.h5 != nil || u.d7 != nil {
          HStack(spacing: 10) {
            if let h = u.h5 { MiniUso(nome: "5h", pct: h.pctAtual) }
            if let d = u.d7 { MiniUso(nome: "7d", pct: d.pctAtual) }
          }
        }
      }
      Spacer(minLength: 6)
      BotaoAjuste(titulo: "Abrir") { loja.criarAba(kind: conta.tipo, conta: conta.id); (NSApp.delegate as? Delegado)?.janelaAjustes?.close() }
        .help("Abre um \(nomeFerramenta(conta.tipo)) com esta conta")
      if !padrao { BotaoMini("star", "Tornar a conta padrão dos próximos agentes") { loja.definirPadrao(conta) } }
      Menu {
        Button("Renomear…") {
          loja.perguntar("Renomear a conta", valor: conta.nome, ok: "Renomear", dica: "Nome da conta") { n in
            Contas.atualizar(id: conta.id, campos: ["nome": n]); loja.carregarContas()
          }
        }
        Menu("Cor") { ForEach(Cor.paletaGrupos, id: \.self) { c in Button(nomeCor(c)) { Contas.atualizar(id: conta.id, campos: ["cor": c]); loja.carregarContas() } } }
        if let d = conta.dir { Button("Mostrar pasta no Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: d) } }
        Button("Atualizar o uso agora") { loja.lerUso(conta.id, forcar: true) }.disabled(!loja.podeLerUso(conta))
        Divider()
        Button("Remover conta", role: .destructive) {
          loja.confirmar("Remover a conta “\(conta.nome)”?", "A pasta vai para a Lixeira (dá para recuperar).", "Remover", destrutivo: true) {
            Contas.remover(id: conta.id)
            if loja.ajustes.contaPadrao(conta.tipo) == conta.id { loja.ajustes.definirContaPadrao(conta.tipo, conta.tipo + "-padrao") }
            loja.carregarContas()
          }
        }.disabled(conta.padraoDoSistema)
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Cor.texto3).frame(width: 27, height: 24).contentShape(Rectangle())
      }
      .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Renomear, cor, pasta, remover")
    }
    .padding(.horizontal, 12).padding(.vertical, 9)
  }
}

struct BlocoExemplos: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("EXEMPLOS").font(F.ui(10.5, .semibold)).kerning(0.5).foregroundStyle(Cor.texto3).padding(.leading, 4)
      Text(GuiaIA.exemplos).font(F.mono(11)).foregroundStyle(Cor.texto2).textSelection(.enabled).lineSpacing(2)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(Cor.elevado))
        .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linha))
    }
  }
}

struct ListaAtalhos: View {
  static let grupos: [(String, [(String, String)])] = [
    ("Workspaces e agentes", [
      ("Workspace 1–9", "⌃1 … ⌃9"), ("Workspace seguinte / anterior", "⌃⌘↓ / ⌃⌘↑"), ("Novo workspace", "⇧⌘G"),
      ("Quadro de agentes", "⇧⌘A"), ("No quadro: ir / mensagem / revisar / concluído / renomear", "↩ / M / R / C / N"),
      ("Novo Claude / Codex / Gemini", "⇧⌘T / ⇧⌘X / ⌥⌘G"), ("Novo agente com opções", "⌥⌘N"), ("Reabrir agente fechado", "⌥⌘Z"),
      ("Interromper o agente", "⌘."), ("Atualizar o uso das contas", "⌥⌘U"),
    ]),
    ("Compose e conversa", [
      ("Escrever no compose / voltar ao terminal", "⌘E"), ("Mostrar ou esconder o compose", "⇧⌘E"), ("Ver como conversa / terminal", "⌥⌘C"),
      ("Enviar / nova linha", "↩ / ⇧↩"), ("Mencionar terminal, pasta ou arquivo", "@"),
      ("Na lista do @: anexar contexto / mandar para ele / entrar na pasta", "↩ / ⌥↩ / ⇥"),
      ("Anexar imagem", "⌘V, arrastar para o painel, ou o clipe"), ("Histórico de mensagens", "↑ / ↓"),
    ]),
    ("Abas e painéis", [
      ("Novo terminal", "⌘T"), ("Aba 1–9", "⌘1 … ⌘9"), ("Aba seguinte / anterior", "⇧⌘] / ⇧⌘["), ("Voltar / avançar", "⌥⌘[ / ⌥⌘]"),
      ("Dividir à direita / abaixo", "⌘D / ⇧⌘D"), ("Painel vizinho", "⌥⌘← → ↑ ↓"), ("Maximizar painel", "⇧⌘↩"),
      ("Renomear aba", "⇧⌘R"), ("Fechar painel / aba", "⌘W / ⇧⌘W"),
    ]),
    ("Janela e texto", [
      ("Paleta de comandos", "⌘P"), ("Barra lateral / barra de agentes", "⌘B / ⇧⌘B"), ("Portas em uso", "⌥⌘P"), ("Ajustes", "⌘,"),
      ("Buscar no terminal", "⌘F"), ("Limpar", "⌘K"), ("Letra maior / menor / normal", "⌘+ / ⌘− / ⌘0"),
      ("Abrir caminho ou link do terminal", "⌘-clique"), ("Menu do caminho", "clique direito"),
    ]),
  ]
  var body: some View {
    ForEach(ListaAtalhos.grupos, id: \.0) { g in
      VStack(alignment: .leading, spacing: 6) {
        Text(g.0.uppercased()).font(F.ui(10.5, .semibold)).kerning(0.5).foregroundStyle(Cor.texto3).padding(.leading, 4)
        VStack(spacing: 0) {
          ForEach(Array(g.1.enumerated()), id: \.offset) { i, l in
            if i > 0 { Rectangle().fill(Cor.linha).frame(height: 1).padding(.leading, 12) }
            HStack {
              Text(l.0).font(F.ui(12.5)).foregroundStyle(Cor.texto)
              Spacer(minLength: 10)
              Text(l.1).font(F.ui(12)).foregroundStyle(Cor.texto2).padding(.horizontal, 7).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Cor.vidro2))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
          }
        }
        .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(Cor.elevado))
        .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linha))
      }
    }
  }
}

enum GuiaIA {
  static let exemplos = """
  # Caixa de entrada: mande e encerre o turno — a resposta chega sozinha
  orion equipe                           # quem é quem neste workspace (papel, setor, descrição, estado)
  orion mandar @vega "revise o PR #12 e liste os problemas" --anexo tela.png
  orion responder m-ab12cd "Status: pronto | Resultado: 3 problemas | Evidência: src/app.ts:40"
  orion caixa                            # o que está na fila, entregue, respondido

  # Maestro: dispare subagentes, espere e recolha o resultado
  F1=$(orion agente --claude --pai $ORION_PAINEL --papel Dev --mensagem "implemente o formulário de leads")
  F2=$(orion agente --codex  --pai $ORION_PAINEL --papel Testes --mensagem "escreva os testes da API")
  orion filhos                           # quem são, o que fazem, em que estado estão
  orion esperar --filhos --tempo 1800    # espera todos pararem
  orion resultado $F1                    # o que o subagente respondeu por último
  orion enviar $F2 "faltou o caso de erro 500" --enter

  # Agentes e terminais
  orion agentes                          # todos: personagem, estado, tarefa, conta, memória
  orion agente --gemini --workspace "Cliente X" --pasta ~/proj --mensagem "resuma o README"
  orion enviar <painel> "compare com isto" --mencionar <outro> --anexo tela.png --enter
  orion contexto <painel>                # tela recente / último comando, em bloco estruturado
  orion marcar <painel> revisar          # quadro: revisar | concluido | nada
  orion rodar "npm test" --esperar       # roda num painel auxiliar; devolve saída + código
  orion fechados · orion reabrir 1       # agentes fechados há pouco, com a mesma conversa
  orion portas · orion liberar 3000      # servidores em escuta; encerra quem ocupa a porta
  orion uso · orion memoria · orion notificar "deploy terminou"
  """

  static let texto = """
  ## Terminal (Orion Terminal)

  Rodando dentro do Orion Terminal, `$ORION_PAINEL` é o id do seu próprio painel e o comando `orion` controla o app. O app é organizado em **workspaces** (um por projeto/cliente, com pasta própria); cada workspace tem abas, e cada aba tem um ou mais painéis (terminais ou agentes). Cada agente é um **personagem** (nome, papel, ferramenta: Claude Code, Codex ou Gemini CLI) e pode ser mencionado pelo nome (`@rigel`).

  ### Caixa de entrada (falar com outros agentes)
  Para pedir algo a outro agente, use a caixa — nunca digite direto no terminal dele nem fique esperando:
  1. `orion equipe` mostra os colegas do workspace: `@apelido`, personagem, papel, setor, descrição e estado. Escolha pelo papel e pela descrição, e prefira quem está no seu setor; fora do seu papel, passe adiante em vez de recusar.
  2. `orion mandar @apelido "pedido completo e autocontido" [--anexo ARQ]` põe a mensagem na caixa dele e devolve um id (`m-…`) na hora. Ela entra no terminal dele só quando ele estiver livre. Ele não vê a sua conversa: escreva o objetivo, o contexto, o que já foi tentado e como é o resultado pronto.
  3. **Encerre o seu turno.** A resposta chega sozinha na sua conversa como `[Resposta de @apelido à mensagem m-…]`. Se ele parar sem responder, chega um aviso com o caminho da última resposta dele.
  4. Ao receber `[Mensagem de @alguém · id m-…]`, faça o pedido e responda com `orion responder m-… "Status: … | Resultado: … | Evidência: …"` — depois encerre o turno.
  5. `orion caixa` lista as suas mensagens (na fila, entregue, respondida); `orion cancelar m-…` tira da fila. `--sem-resposta` em `mandar` é para avisos que não pedem resposta.
  6. Pediu para vários colegas? As respostas voltam **juntas**, numa entrega só, quando todos responderem (ou em 15 min). Não responda só "ok"/"obrigado": confirmações curtas ficam registradas mas não acordam ninguém. A mesma mensagem repetida para o mesmo colega em menos de 1 h não é enviada de novo.
  7. Colega hibernado (dormindo para liberar memória) recebe normalmente: a mensagem o acorda na mesma conversa.
  8. Não sabe quem do time deve pegar? `orion mandar @time "pedido" [--setor S]`: o Orion escolhe pelo papel, pela tarefa e por quem está livre. Recebeu `[Mensagem … para o time — o Orion escolheu você · id m-…]` e não é com você (ou não tem nada a acrescentar)? Rode só `orion passar m-… "motivo"` e encerre o turno: a mensagem vai para o próximo colega.
  9. Chegou `[Interrompido por … ] Motivo: …`? Você foi parado de propósito: leve o motivo em conta antes de retomar qualquer coisa.
  Você continua dono do que delegou: confira a resposta antes de passar ao usuário.

  ### Você como maestro (coordenar subagentes)
  Quando a tarefa se divide em partes independentes, dispare subagentes em vez de fazer tudo sozinho:
  1. `orion agente --claude|--codex|--gemini --pai $ORION_PAINEL [--papel "Dev"] [--nome "Vega"] [--pasta P] --mensagem "tarefa completa e autocontida"` cria um subagente seu (ele aparece dentro de você na barra lateral e no quadro), já trabalhando, sem tirar o usuário do que ele está vendo. O comando devolve o id do painel dele. Escreva a tarefa com tudo o que ele precisa: ele não vê a sua conversa.
  2. `orion filhos [--json]` lista os seus subagentes: id, personagem, papel, estado (`trabalhando`, `esperando`, `pronto`, `saiu`), tarefa.
  3. `orion esperar ID [--tempo S]` espera um deles parar; `orion esperar --filhos [--tempo S]` espera todos.
  4. `orion resultado ID [--linhas N]` devolve o que ele escreveu desde a última mensagem que recebeu (num bloco `<contexto-orion …>`). Leia, confira e só então responda ao usuário.
  5. `orion enviar ID "ajuste…" --enter` manda uma correção; `orion interromper ID [--motivo "por quê"]` para (com motivo, ele lê o porquê antes de seguir); `orion fechar ID` encerra quando não precisar mais (ele fica em "fechados há pouco").
  Com `--retorno` no passo 1, você nem precisa esperar: quando o subagente parar, o resultado chega sozinho na sua conversa como uma mensagem `[Subagente @nome terminou …]` com o caminho de um arquivo — leia o arquivo.
  Boas práticas: no máximo 3–4 subagentes ao mesmo tempo; pastas ou arquivos diferentes para cada um (não ponha dois para editar o mesmo arquivo); marque `orion marcar ID revisar` no que o usuário precisa conferir. Abriu um pull request? O cartão vai sozinho para Revisar quando o link do PR aparece na tela.

  ### Agentes e mensagens
  - `orion workspaces [--json]`, `orion workspace novo "Nome" --pasta P`, `orion workspace focar NOME|N`.
  - `orion agentes [--json] [--workspace W]` lista todos os agentes: id, personagem, papel, pai, estado, há quantos segundos, conta, pasta, tarefa, marca do quadro, memória.
  - `orion agente --claude|--codex|--gemini [--workspace W] [--pasta P] [--conta ID] [--nome N] [--papel P] [--mensagem "tarefa"] [--fundo]` abre um agente (sem `--pai`, ele é independente). O nome que aparece vem da tarefa.
  - `orion enviar ID "texto" --enter` manda uma mensagem. `--mencionar OUTRO` leva junto o contexto do painel OUTRO; `--anexo ARQUIVO` leva imagem ou arquivo (imagem vai como caminho, que é como Claude Code e Codex leem imagem).
  - `orion contexto ID`, `orion ler ID [--linhas N]`, `orion interromper ID`, `orion reiniciar ID`, `orion compor ID "rascunho"` (deixa escrito para o usuário enviar).
  - `orion marcar ID revisar|concluido|nada`, `orion personagem ID [--nome N] [--papel P] [--descricao "o que faz"]`.
  - `orion setor [ID] "Nome"` põe um agente num setor (grupo dentro do workspace); `--setor "Nome"` em `orion agente` já cria nele. Subagentes nascem no setor do maestro.
  - `orion hibernar ID` libera a memória de um agente parado (o processo fecha; volta na mesma conversa ao receber mensagem ou com `orion acordar ID`).
  - `orion fechados`, `orion reabrir [N|ID]` — agentes fechados há pouco voltam com a mesma conversa.
  - `orion contas`, `orion uso [--json]`, `orion conta ID CONTA`, `orion memoria`.

  ### Terminais e servidores
  - `orion abas --json`, `orion nova --shell [--workspace W] [--pasta P] [--comando C]`, `orion dividir --abaixo --comando "npm run dev"`.
  - `orion rodar [--painel ID] "comando" --esperar [--tempo S]` roda e devolve a saída e o código de saída. Sem `--painel`, usa um painel auxiliar abaixo do seu — use para servidores e comandos longos.
  - `orion portas [--todas] [--json]` mostra os servidores em escuta (porta, processo, painel). `orion liberar PORTA` encerra o processo que ocupa a porta — use só em servidores que você mesmo subiu, ou quando o usuário pedir.
  - `orion notificar "texto"` avisa o usuário.

  Dica: ao citar um arquivo ou uma pasta, escreva o caminho numa linha só — no Orion Terminal ele abre com ⌘-clique.

  Regras: não envie comandos destrutivos nem interrompa/feche painéis que você não abriu. Subagentes já nascem em segundo plano; para agentes sem `--pai`, prefira `--fundo`.
  """
}
