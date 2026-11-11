import SwiftUI
import AppKit

// Cabeçalho de cada painel: ícone grande do programa, título em cima; embaixo "pasta · branch",
// a conta (um clique troca) e, à direita, o estado, a memória e o zoom. Fonte do sistema; mono
// só no caminho e nos números.

struct CabecalhoPainel: View {
  @Bindable var painel: Painel
  @Estado private var sobre = false
  @Estado private var largura: CGFloat = 600

  var body: some View {
    let loja = painel.loja
    let ativo = painel.aba?.painelAtivo == painel.id
    // Painel estreito (divisões, janela pequena): some primeiro o que é acessório.
    let largo = largura >= 440, medio = largura >= 300
    HStack(alignment: .center, spacing: medio ? 10 : 7) {
      Group {
        if let persona = painel.persona, let t = painel.tipoAgente {
          AvatarPersona(persona: persona, tamanho: F.m(medio ? 30 : 24), ferramenta: t, maestro: loja.ehMaestro(painel))
            .onTapGesture(count: 2) { loja.editarPersonagem(painel) }
            .help("\(persona.nome)\(persona.papel.isEmpty ? "" : " · \(persona.papel)") — \(nomeLongoFerramenta(t)). Duplo clique edita o personagem.")
        } else {
          IconePrograma(processo: painel.programa, tamanho: F.m(medio ? 26 : 22))
        }
      }
      .modifier(AncoraSeAgente(painel: painel))
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          HStack(spacing: 6) {
            if let persona = painel.persona, painel.tipoAgente != nil, medio {
              Text(persona.nome).font(F.ui(13.5, .semibold)).foregroundStyle(Color(hex: persona.cor)).brightness(Cor.claro ? -0.3 : 0).lineLimit(1).fixedSize()
            }
            Text(tituloDoCabecalho).font(F.ui(13.5, painel.persona != nil && medio ? .regular : .semibold)).foregroundStyle(Cor.texto).lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          if largo { ContaDoPainel(painel: painel) }
          HStack(spacing: 1) {
            if painel.vivo && !painel.ocioso && medio {
              BotaoMini("stop.circle", "Interromper o que está rodando  ⌘.") { painel.interromper() }
            }
            if medio {
              if painel.tipoAgente != nil {
                BotaoMini(painel.conversa ? "terminal" : "bubble.left.and.bubble.right", painel.conversa ? "Voltar ao terminal  ⌥⌘C" : "Ver como conversa (as mensagens do compose e as respostas)  ⌥⌘C") { painel.conversa.toggle() }
              }
              BotaoMini(painel.composeVisivel ? "square.and.pencil.circle.fill" : "square.and.pencil", "Escrever no compose  ⌘E   ·   mostrar/esconder  ⇧⌘E") { painel.alternarCompose() }
            }
            if largo {
              BotaoMini("rectangle.split.2x1", "Dividir à direita  ⌘D") { loja.focar(painel); _ = loja.dividir(horizontal: true) }
              BotaoMini("rectangle.split.1x2", "Dividir abaixo  ⇧⌘D") { loja.focar(painel); _ = loja.dividir(horizontal: false) }
            }
            if (painel.aba?.arvore.folhas.count ?? 1) > 1 {
              BotaoMini(painel.aba?.maximizado == painel.id ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", "Maximizar  ⇧⌘↩") { loja.focar(painel); loja.maximizar() }
            }
            BotaoMini("xmark", "Fechar painel  ⌘W") { loja.fecharPainel(painel) }
          }
          .opacity(sobre || ativo ? 1 : 0)
        }
        HStack(spacing: 7) {
          LocalDoPainel(painel: painel, comBranch: medio)
          Spacer(minLength: 4)
          if medio { ForEach(painel.portas.prefix(largo ? 3 : 1), id: \.self) { porta in ChipPorta(porta: porta) } }
          Status(painel: painel, comTempo: medio)
          if largo && loja.ajustes.memoria && painel.memoria > 30 * 1_048_576 {
            Text(Memoria.texto(painel.memoria)).monospacedDigit().foregroundStyle(Cor.texto3).fixedSize()
              .help("Memória deste painel: o shell e tudo o que ele abriu (\(painel.processos) processo\(painel.processos == 1 ? "" : "s"))")
          }
          if largo {
            HStack(spacing: 2) {
              BotaoZoom("minus") { painel.mudarZoom(-1) }
              Button { painel.mudarZoom(0) } label: {
                Text(painel.zoom == 0 ? "100%" : String(format: "%+.0f", painel.zoom)).monospacedDigit().foregroundStyle(Cor.texto3).frame(minWidth: 30)
              }.buttonStyle(.plain).help("Tamanho da letra deste painel (clique volta ao normal)")
              BotaoZoom("plus") { painel.mudarZoom(1) }
            }
            .fixedSize()
            .opacity(sobre || ativo ? 1 : 0.0)
          }
        }
        .font(F.ui(11.5))
      }
    }
    .padding(.leading, medio ? 12 : 8).padding(.trailing, medio ? 10 : 6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .clipped()
    .background(Cor.vidro.opacity(ativo ? 0.9 : 0.4))
    .overlay(alignment: .bottom) { Rectangle().fill(Cor.linha).frame(height: 1) }
    .contentShape(Rectangle())
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largura = $0 }
    .onHover { sobre = $0 }
    .onTapGesture(count: 2) { loja.focar(painel); loja.maximizar() }
    .onTapGesture { loja.focar(painel) }
    .contextMenu { if let a = painel.aba { MenuDaAba(loja: loja, aba: a) } }
    .preferredColorScheme(Cor.claro ? .light : .dark)
  }
}

extension CabecalhoPainel {
  /// Numa aba de um painel só, vale o nome que você deu à aba; com divisões, cada painel mostra o seu.
  var tituloDoCabecalho: String {
    if let a = painel.aba, let t = a.titulo, !t.isEmpty, a.arvore.folhas.count == 1 { return t }
    return painel.titulo
  }
}

/// "pasta · branch ±n" e, quando o título é a tarefa do agente, o caminho completo.
struct LocalDoPainel: View {
  @Bindable var painel: Painel
  var comBranch = true
  var body: some View {
    let nomePasta = Loja.nomeDaPasta(painel.cwd)
    let caminho = Loja.encurtar(painel.cwd)
    let tituloEhPasta = painel.titulo == nomePasta
    Text(tituloEhPasta ? (caminho == painel.titulo ? (painel.ocioso ? "zsh" : painel.processo) : caminho) : nomePasta)
      .font(F.mono(11)).foregroundStyle(Cor.texto2).lineLimit(1).truncationMode(.head)
      .help(caminho)
    if !painel.branch.isEmpty && comBranch {
      HStack(spacing: 3) {
        Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
        Text(painel.branch).lineLimit(1)
        if painel.alterados > 0 { Text("±\(painel.alterados)").monospacedDigit().foregroundStyle(Cor.amarelo).fixedSize().help("\(painel.alterados) arquivo(s) alterado(s)") }
      }
      .foregroundStyle(Cor.lilas)
    }
  }
}

/// Ícone do painel vira âncora do cartão de uso quando o painel é um agente.
struct AncoraSeAgente: ViewModifier {
  @Bindable var painel: Painel
  func body(content: Content) -> some View {
    if let tipo = painel.tipoAgente {
      content.modifier(AncoraUso(loja: painel.loja, tipo: tipo, nome: "painel-\(painel.id)"))
    } else {
      content
    }
  }
}

/// Conta desta aba (só em painéis de agente): um botão com a conta e o uso; clique abre o
/// seletor visual de contas.
struct ContaDoPainel: View {
  @Bindable var painel: Painel
  var body: some View {
    let loja = painel.loja
    if let aba = painel.aba, let tipo = painel.tipoAgente {
      let contas = loja.contas(tipo)
      let atual = loja.conta(aba.conta(tipo))
      let resumo = atual.flatMap { loja.usoVisivel($0.id)?.resumo }
      if contas.count > 1 || resumo != nil {
        SeletorConta(loja: loja, tipo: tipo, atual: atual?.id, titulo: "Conta desta aba", dica: "Conta desta aba: \(atual?.nome ?? "") — clique para trocar") { c in
          loja.trocarConta(aba, para: c)
        } rotulo: {
          HStack(spacing: 5) {
            if contas.count > 1, let atual { Circle().fill(Color(hex: atual.cor)).frame(width: 7, height: 7); Text(atual.nome).foregroundStyle(Cor.texto2).lineLimit(1) }
            if let r = resumo { Text("\(r.rotulo) \(Int(r.pct.rounded()))%").monospacedDigit().foregroundStyle(r.pct >= 60 ? Cor.uso(r.pct) : Cor.texto3).fixedSize() }
            if contas.count > 1 { Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(Cor.texto4) }
          }
          .font(F.ui(11))
          .padding(.horizontal, 7).frame(height: F.m(22))
          .background(RoundedRectangle(cornerRadius: R.pequeno, style: .continuous).fill(Cor.vidro))
        }
      }
    }
  }
}

/// Seletor de conta: um popover com as contas da ferramenta, cada uma com cor, e-mail e as barras
/// de uso — no lugar do menu de texto.
struct SeletorConta<Rotulo: View>: View {
  let loja: Loja
  let tipo: String
  let atual: String?
  var titulo = "Conta"
  var dica = "Trocar de conta"
  let aoEscolher: (Conta) -> Void
  @ViewBuilder var rotulo: Rotulo
  @Estado private var aberto = false

  var body: some View {
    Button { aberto.toggle() } label: { rotulo.contentShape(Rectangle()) }
      .buttonStyle(.plain)
      .help(dica)
      .popover(isPresented: $aberto, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 7) {
            IconePrograma(processo: tipo, tamanho: 18)
            Text(titulo).font(F.ui(12.5, .semibold)).foregroundStyle(Cor.texto)
            Spacer()
          }
          .padding(.bottom, 2)
          ForEach(loja.contas(tipo)) { c in
            LinhaSeletorConta(loja: loja, conta: c, ativa: c.id == atual) { aberto = false; aoEscolher(c) }
          }
          Button { aberto = false; (NSApp.delegate as? Delegado)?.abrirAjustes(aba: "contas") } label: {
            Label("Gerenciar contas…", systemImage: "person.2").font(F.ui(11.5)).foregroundStyle(Cor.texto3)
          }.buttonStyle(.plain).padding(.top, 4)
        }
        .padding(12).frame(width: 300)
      }
  }
}

struct LinhaSeletorConta: View {
  let loja: Loja
  let conta: Conta
  let ativa: Bool
  let acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    let uso = loja.usoVisivel(conta.id)
    Button(action: acao) {
      HStack(spacing: 10) {
        Text(String(conta.nome.prefix(1)).uppercased()).font(F.ui(13, .bold)).foregroundStyle(.white)
          .frame(width: 30, height: 30).background(Circle().fill(Color(hex: conta.cor)))
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 5) {
            Text(conta.nome).font(F.ui(12.5, .semibold)).foregroundStyle(Cor.texto).lineLimit(1)
            if loja.contaPadrao(conta.tipo)?.id == conta.id { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Cor.acento).help("Conta padrão dos próximos agentes") }
          }
          Text(conta.logado ? (conta.email.isEmpty ? "conectada" : conta.email) : "sem login").font(F.ui(10.5))
            .foregroundStyle(conta.logado ? Cor.texto3 : Cor.amarelo).lineLimit(1).truncationMode(.middle)
          if let u = uso, u.h5 != nil || u.d7 != nil {
            HStack(spacing: 8) {
              if let h = u.h5 { MiniUso(nome: "5h", pct: h.pctAtual) }
              if let d = u.d7 { MiniUso(nome: "7d", pct: d.pctAtual) }
            }
          }
        }
        Spacer(minLength: 4)
        Image(systemName: ativa ? "checkmark.circle.fill" : "circle").font(.system(size: 15)).foregroundStyle(ativa ? Cor.acento : Cor.texto4)
      }
      .padding(8)
      .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(ativa ? Cor.acento.opacity(0.10) : (sobre ? Cor.vidro2 : Cor.vidro)))
      .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(ativa ? Cor.acento.opacity(0.5) : Cor.linha))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).onHover { sobre = $0 }
    .help(ativa ? "Conta em uso" : "Usar a conta \(conta.nome)\(conta.email.isEmpty ? "" : " (\(conta.email))")")
  }
}

struct MiniUso: View {
  let nome: String
  let pct: Double
  var body: some View {
    HStack(spacing: 4) {
      Text(nome).foregroundStyle(Cor.texto4)
      Capsule().fill(Cor.vidro2).frame(width: 44, height: 4)
        .overlay(alignment: .leading) { Capsule().fill(Cor.uso(pct)).frame(width: max(pct > 0 ? 3 : 0, 44 * min(1, pct / 100)), height: 4) }
      Text("\(Int(pct.rounded()))%").monospacedDigit().foregroundStyle(pct >= 60 ? Cor.uso(pct) : Cor.texto3)
    }
    .font(F.ui(10))
  }
}

/// Porta de um servidor que este painel subiu: clique abre no navegador.
struct ChipPorta: View {
  let porta: Int
  var body: some View {
    Button { if let u = URL(string: "http://localhost:\(porta)") { MenuTerminal.abrirNoNavegador(u) } } label: {
      Text(":\(String(porta))").font(F.mono(10.5, .medium)).foregroundStyle(Cor.verde)
        .padding(.horizontal, 5).frame(height: F.m(18))
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Cor.verde.opacity(0.13)))
    }
    .buttonStyle(.plain).fixedSize()
    .help("Este painel tem um servidor na porta \(porta) — clique abre http://localhost:\(porta)")
  }
}

struct Status: View {
  @Bindable var painel: Painel
  var comTempo = true
  var body: some View {
    let e = painel.estado
    let texto: String = {
      switch e {
      case .dormindo: return "Não iniciado"
      case .saiu: return "Saiu · \(painel.codigoSaida ?? 0)"
      case .rodando: return painel.processo.isEmpty ? "Rodando" : painel.processo
      default: return e.rotulo
      }
    }()
    HStack(spacing: 5) {
      Circle().fill(e.cor).frame(width: 7, height: 7).shadow(color: e.cor, radius: e == .trabalhando ? 3 : 0)
      Text(texto).foregroundStyle(e == .dormindo ? Cor.texto3 : e.cor).lineLimit(1)
      if comTempo && (e == .trabalhando || e == .esperando || e == .rodando) {
        Ha(desde: painel.desde, prefixo: "há ").foregroundStyle(Cor.texto4)
      }
    }
    .fixedSize()
  }
}

struct BotaoMini: View {
  let simbolo: String, dica: String, acao: () -> Void
  @Estado private var sobre = false
  init(_ s: String, _ d: String, acao: @escaping () -> Void) { simbolo = s; dica = d; self.acao = acao }
  var body: some View {
    Button(action: acao) {
      Image(systemName: simbolo).font(.system(size: 13, weight: .medium)).foregroundStyle(sobre ? Cor.texto : Cor.texto3)
        .frame(width: 27, height: 24).background(RoundedRectangle(cornerRadius: R.pequeno, style: .continuous).fill(sobre ? Cor.vidro2 : .clear))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).onHover { sobre = $0 }.help(dica)
  }
}

struct BotaoZoom: View {
  let simbolo: String, acao: () -> Void
  init(_ s: String, acao: @escaping () -> Void) { simbolo = s; self.acao = acao }
  var dica: String { simbolo == "minus" ? "Letra menor neste painel  ⌘−" : "Letra maior neste painel  ⌘+" }
  var body: some View {
    Button(action: acao) {
      Image(systemName: simbolo).font(.system(size: 9, weight: .bold)).foregroundStyle(Cor.texto2)
        .frame(width: 20, height: 18).background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Cor.vidro2))
    }.buttonStyle(.plain).help(dica)
  }
}
