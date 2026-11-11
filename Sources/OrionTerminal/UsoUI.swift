import SwiftUI
import AppKit

// Botões do Claude e do Codex (doca, barra do topo, cabeçalho do painel, quadro de agentes).
//   passar o mouse → resumo: uso de cada conta e quantos agentes rodam;
//   clique         → painel da ferramenta: contas, uso de 5 h / 7 dias, os agentes dela e o
//                    botão "Novo Claude / Codex" com a conta escolhida;
//   ⌥-clique ou duplo clique → abre um agente direto (ou o contrário, conforme o ajuste).
// Nada aqui toca a rede nem o Chaveiro: só lê o cache.

/// Anel em volta de um ícone: uso de 5 h da conta padrão da ferramenta.
struct AnelUso<Conteudo: View>: View {
  let loja: Loja
  let tipo: String
  var conta: String? = nil
  var tamanho: CGFloat = 40
  var espessura: CGFloat = 2.2
  @ViewBuilder var conteudo: Conteudo

  var body: some View {
    let c = conta.flatMap { loja.conta($0) } ?? loja.contaPadrao(tipo)
    let pct = c.flatMap { loja.usoVisivel($0.id)?.resumo?.pct }
    ZStack {
      Circle().stroke(Cor.linhaForte, lineWidth: espessura)
      if let pct {
        Circle().trim(from: 0, to: max(0.012, min(1, pct / 100)))
          .stroke(Cor.uso(pct), style: StrokeStyle(lineWidth: espessura, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      conteudo
    }
    .frame(width: tamanho, height: tamanho)
  }
}

extension Cor {
  static func uso(_ pct: Double) -> Color { pct >= 85 ? Cor.vermelho : pct >= 60 ? Cor.amarelo : Cor.verde }
}

/// Marca um elemento como âncora do cartão da ferramenta: entrar com o mouse abre o resumo,
/// sair fecha. Com `clique`, o elemento também responde ao clique (painel / novo agente).
struct AncoraUso: ViewModifier {
  let loja: Loja
  let tipo: String
  var nome = ""
  var clique = false
  @Estado private var quadro: CGRect = .zero

  // `.global` já é a janela (origem em cima à esquerda), mesmo dentro do cabeçalho de um painel,
  // que é outra NSHostingView — as mesmas coordenadas da camada onde o cartão é desenhado.
  func body(content: Content) -> some View {
    let base = content
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { novo in
        quadro = novo
        if !nome.isEmpty { loja.ancoras[nome] = novo }
      }
      .onHover { dentro in
        if dentro { loja.entrouUso(tipo, ancora: quadro) } else { loja.saiuUso() }
      }
    if clique {
      base
        .onTapGesture {
          // Sem esperar o tempo do duplo clique: o primeiro abre o painel; se vier o segundo, vira "novo".
          if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { loja.fecharUso(); loja.criarAba(kind: tipo) }
          else { loja.cliqueNaFerramenta(tipo, ancora: quadro, alternativo: NSEvent.modifierFlags.contains(.option)) }
        }
        .help(loja.ajustes.cliqueFerramenta == "novo"
              ? "Clique: novo \(nomeFerramenta(tipo))   ·   ⌥ clique: contas, uso e agentes"
              : "Clique: contas, uso e agentes   ·   ⌥ clique ou duplo clique: novo \(nomeFerramenta(tipo))")
    } else {
      base
    }
  }
}

/// Barra do topo: uma cápsula por ferramenta, com o anel de uso, a conta padrão e o percentual.
struct ChipFerramenta: View {
  @Bindable var loja: Loja
  let tipo: String
  var compacto = false          // janela estreita: só o ícone com o anel
  @Estado private var sobre = false

  var body: some View {
    let contas = loja.contas(tipo)
    let padrao = loja.contaPadrao(tipo)
    let pct = padrao.flatMap { loja.usoVisivel($0.id)?.resumo?.pct }
    let aberto = loja.usoHover?.tipo == tipo && loja.usoHover?.expandido == true
    HStack(spacing: 6) {
      AnelUso(loja: loja, tipo: tipo, tamanho: 26, espessura: 1.8) { IconePrograma(processo: tipo, tamanho: 18) }
      if !compacto {
        if contas.count > 1, let padrao {
          HStack(spacing: 5) {
            Circle().fill(Color(hex: padrao.cor)).frame(width: 7, height: 7)
            Text(padrao.nome).font(F.ui(12, .medium)).foregroundStyle(Cor.texto).lineLimit(1).frame(maxWidth: 90)
          }.fixedSize()
        }
        if let pct {
          Text("\(Int(pct.rounded()))%").font(F.ui(11.5, .medium)).monospacedDigit().foregroundStyle(pct >= 60 ? Cor.uso(pct) : Cor.texto2).fixedSize()
        }
        if contas.count > 1 || pct != nil {
          Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Cor.texto4)
        }
      }
    }
    .padding(.leading, 4).padding(.trailing, !compacto && (pct != nil || contas.count > 1) ? 9 : 4).frame(height: 34)
    .background(RoundedRectangle(cornerRadius: R.controle + 2, style: .continuous).fill(aberto ? Cor.vidro2 : (sobre ? Cor.vidro : .clear)))
    .contentShape(Rectangle())
    .onHover { sobre = $0 }
    .modifier(AncoraUso(loja: loja, tipo: tipo, nome: "topo-\(tipo)", clique: true))
  }
}

struct SegmentoConta: View {
  let conta: Conta
  let ativo: Bool
  let dica: String
  var pequeno = false
  let acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    Button(action: acao) {
      HStack(spacing: 4) {
        Circle().fill(Color(hex: conta.cor)).frame(width: 6, height: 6).opacity(ativo ? 1 : 0.55)
        Text(conta.nome).font(F.ui(pequeno ? 11 : 12, ativo ? .semibold : .regular)).lineLimit(1)
      }
      .foregroundStyle(ativo ? Cor.texto : (sobre ? Cor.texto2 : Cor.texto3))
      .padding(.horizontal, pequeno ? 6 : 8).frame(height: F.m(pequeno ? 18 : 24))
      .background(RoundedRectangle(cornerRadius: pequeno ? 5 : 7, style: .continuous).fill(ativo ? Cor.vidro2 : (sobre ? Cor.vidro : .clear)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).onHover { sobre = $0 }.help(dica)
  }
}

/// Camada por cima da janela onde o cartão aparece, colado ao elemento que o abriu.
struct CamadaUso: View {
  @Bindable var loja: Loja

  var body: some View {
    GeometryReader { g in
      if let h = loja.usoHover {
        let largura: CGFloat = min(h.expandido ? 400 : 300, g.size.width - 16)
        let x = min(max(8, h.ancora.midX - largura / 2), max(8, g.size.width - largura - 8))
        let acima = h.ancora.midY > g.size.height / 2
        let espaco = (acima ? h.ancora.minY : g.size.height - h.ancora.maxY) - 16
        ZStack(alignment: .topLeading) {
          // Painel aberto por clique: clicar fora fecha.
          if h.expandido { Color.black.opacity(0.001).onTapGesture { loja.fecharUso() } }
          Group {
            if h.expandido { PainelFerramenta(loja: loja, tipo: h.tipo, alturaMaxima: max(220, espaco)) }
            else { ResumoFerramenta(loja: loja, tipo: h.tipo) }
          }
          .frame(width: largura)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: acima ? .bottomLeading : .topLeading)
          .offset(x: x, y: acima ? -(g.size.height - h.ancora.minY + 8) : h.ancora.maxY + 8)
        }
        .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.12), value: loja.usoHover?.tipo)
    .animation(.easeOut(duration: 0.12), value: loja.usoHover?.expandido)
  }
}

/// Hover: o essencial em poucas linhas.
struct ResumoFerramenta: View {
  @Bindable var loja: Loja
  let tipo: String

  var body: some View {
    let contas = loja.contas(tipo)
    let agentes = loja.agentes().filter { $0.tipoAgente == tipo }
    let trabalhando = agentes.filter { $0.estado == .trabalhando }.count
    let esperando = agentes.filter { $0.estado == .esperando }.count
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        IconePrograma(processo: tipo, tamanho: 22)
        Text(nomeLongoFerramenta(tipo)).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
        Spacer()
        Text(agentes.isEmpty ? "nenhum agente" : "\(agentes.count) agente\(agentes.count == 1 ? "" : "s")").font(F.ui(11)).foregroundStyle(Cor.texto3)
      }
      if !agentes.isEmpty {
        HStack(spacing: 10) {
          if esperando > 0 { HStack(spacing: 4) { Circle().fill(Cor.ambar).frame(width: 6, height: 6); Text("\(esperando) esperando você") }.foregroundStyle(Cor.ambar) }
          if trabalhando > 0 { HStack(spacing: 4) { Circle().fill(Cor.verde).frame(width: 6, height: 6); Text("\(trabalhando) trabalhando") }.foregroundStyle(Cor.verde) }
          if esperando + trabalhando == 0 { Text("todos parados").foregroundStyle(Cor.texto3) }
        }
        .font(F.ui(11.5))
      }
      VStack(spacing: 5) {
        ForEach(contas) { c in
          let u = loja.usoVisivel(c.id)
          HStack(spacing: 6) {
            Circle().fill(Color(hex: c.cor)).frame(width: 7, height: 7)
            Text(c.nome).font(F.ui(12, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
            if loja.contaPadrao(tipo)?.id == c.id && contas.count > 1 { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Cor.acento) }
            Spacer(minLength: 6)
            if !c.logado { Text("sem login").foregroundStyle(Cor.amarelo) }
            else if let u, u.h5 != nil || u.d7 != nil {
              if let h = u.h5 { Text("5h \(Int(h.pctAtual.rounded()))%").foregroundStyle(h.pctAtual >= 60 ? Cor.uso(h.pctAtual) : Cor.texto2) }
              if let d = u.d7 { Text("7d \(Int(d.pctAtual.rounded()))%").foregroundStyle(d.pctAtual >= 60 ? Cor.uso(d.pctAtual) : Cor.texto3) }
            } else { Text(loja.podeLerUso(c) ? "sem dados" : "uso desligado").foregroundStyle(Cor.texto4) }
          }
          .font(F.ui(11.5)).monospacedDigit()
        }
      }
      Text(loja.ajustes.cliqueFerramenta == "novo" ? "clique abre um agente · ⌥ clique expande" : "clique expande · ⌥ clique ou duplo clique abre um agente")
        .font(F.ui(10.5)).foregroundStyle(Cor.texto4)
    }
    .padding(12)
    .cartaoFlutuante()
    .onHover { dentro in if dentro { loja.ficouNoUso() } else { loja.saiuUso() } }
  }
}

/// Clique: painel completo da ferramenta.
struct PainelFerramenta: View {
  @Bindable var loja: Loja
  let tipo: String
  var alturaMaxima: CGFloat = 520
  @Estado private var contaNova = ""

  var body: some View {
    let contas = loja.contas(tipo)
    let lendo = contas.contains { loja.usoCarregando.contains($0.id) }
    let ultima = contas.compactMap { loja.usos[$0.id]?.em }.max()
    let agentes = loja.agentes().filter { $0.tipoAgente == tipo }.sorted { Loja.colunaDoQuadro($0) < Loja.colunaDoQuadro($1) }
    let nome = nomeFerramenta(tipo)
    let escolhida = loja.conta(contaNova).flatMap { $0.tipo == tipo ? $0 : nil } ?? loja.contaPadrao(tipo)
    let ws = loja.workspaceAtivo
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 9) {
        IconePrograma(processo: tipo, tamanho: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text(nomeLongoFerramenta(tipo)).font(F.ui(14, .semibold)).foregroundStyle(Cor.texto)
          Group {
            if lendo { Text("lendo o uso…") }
            else if let ultima { TimelineView(.periodic(from: .now, by: 20)) { _ in Text(Loja.duracao(desde: ultima) == "agora" ? "uso atualizado agora" : "uso atualizado há \(Loja.duracao(desde: ultima))") } }
            else { Text("\(contas.count) conta\(contas.count == 1 ? "" : "s")") }
          }
          .font(F.ui(11)).foregroundStyle(Cor.texto3)
        }
        Spacer()
        BotaoMini("arrow.clockwise", "Atualizar o uso agora  ⌥⌘U") { for c in contas where c.logado { loja.lerUso(c.id, forcar: true) } }
        BotaoMini("gearshape", "Gerenciar contas…") { loja.fecharUso(); (NSApp.delegate as? Delegado)?.abrirAjustes(aba: "contas") }
        BotaoMini("xmark", "Fechar  esc") { loja.fecharUso() }
      }
      .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if tipo == "claude" && loja.ajustes.usoClaude == "perguntar" { AvisoChaveiro(loja: loja) }
          Rotulo("CONTAS")
          VStack(spacing: 7) { ForEach(contas) { c in LinhaContaUso(loja: loja, conta: c, escolhida: escolhida?.id == c.id) { contaNova = c.id } } }
          Rotulo(agentes.isEmpty ? "AGENTES" : "AGENTES · \(agentes.count)")
          if agentes.isEmpty {
            Text("Nenhum \(nome) aberto.").font(F.ui(12)).foregroundStyle(Cor.texto3)
          } else {
            VStack(spacing: 2) { ForEach(agentes, id: \.id) { p in LinhaAgenteDaFerramenta(loja: loja, painel: p) } }
          }
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
      }
      .scrollIndicators(.never)
      .frame(maxHeight: max(120, alturaMaxima - 150))
      .fixedSize(horizontal: false, vertical: true)
      Rectangle().fill(Cor.linha).frame(height: 1)
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 5) {
            if let c = escolhida { Circle().fill(Color(hex: c.cor)).frame(width: 7, height: 7); Text(c.nome).font(F.ui(12, .medium)).foregroundStyle(Cor.texto).lineLimit(1) }
          }
          Text(ws.map { "em \($0.nome)" } ?? "").font(F.ui(10.5)).foregroundStyle(Cor.texto3).lineLimit(1)
        }
        Spacer(minLength: 4)
        Button { loja.fecharUso(); loja.novoAgentePerguntando(kind: tipo, conta: escolhida?.id) } label: {
          Text("Opções…").font(F.ui(12, .medium)).foregroundStyle(Cor.texto2)
            .padding(.horizontal, 10).frame(height: F.m(32))
            .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.vidro2))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help("Escolher workspace, pasta, título e a primeira tarefa")
        Button { loja.fecharUso(); loja.criarAba(kind: tipo, conta: escolhida?.id) } label: {
          HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
            Text("Novo \(nome)").font(F.ui(13, .semibold))
          }
          .foregroundStyle(Cor.sobreAcento)
          .padding(.horizontal, 13).frame(height: F.m(32))
          .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.acento))
          .contentShape(Rectangle())
        }.buttonStyle(.plain).help("Abre um \(nome) no workspace atual com a conta \(escolhida?.nome ?? "")")
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
    }
    .cartaoFlutuante()
    .onTapGesture { }
  }
}

/// Um agente na lista do painel da ferramenta: estado, tarefa, onde, memória. Clique vai até ele.
struct LinhaAgenteDaFerramenta: View {
  let loja: Loja
  @Bindable var painel: Painel
  @Estado private var sobre = false
  var body: some View {
    let ws = painel.aba.flatMap { loja.workspace(de: $0) }
    Button { loja.fecharUso(); loja.abrirQuadro(false); loja.focar(painel) } label: {
      HStack(spacing: 8) {
        if let persona = painel.persona { AvatarPersona(persona: persona, tamanho: 24, estado: painel.estado) } else { Circle().fill(painel.estado.cor).frame(width: 7, height: 7) }
        VStack(alignment: .leading, spacing: 1) {
          Text(painel.aba.flatMap { $0.titulo } ?? painel.titulo).font(F.ui(12.5, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
          Text("\(painel.persona.map { $0.nome + " · " } ?? "")\(ws?.nome ?? "") · \(Loja.encurtar(painel.cwd))").font(F.ui(10.5)).foregroundStyle(Cor.texto3).lineLimit(1).truncationMode(.middle)
        }
        Spacer(minLength: 6)
        VStack(alignment: .trailing, spacing: 1) {
          Text(painel.estado.rotulo).font(F.ui(11)).foregroundStyle(painel.estado == .dormindo || painel.estado == .pronto ? Cor.texto3 : painel.estado.cor)
          if painel.memoria > 0 { Text(Memoria.texto(painel.memoria)).font(F.ui(10.5)).monospacedDigit().foregroundStyle(Cor.texto4) }
        }
      }
      .padding(.horizontal, 8).padding(.vertical, 5)
      .background(RoundedRectangle(cornerRadius: R.pequeno + 1, style: .continuous).fill(sobre ? Cor.vidro2 : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).onHover { sobre = $0 }.help("Ir até este agente")
  }
}

/// Primeira vez: explica de onde vem o uso do Claude antes de tocar no Chaveiro.
struct AvisoChaveiro: View {
  @Bindable var loja: Loja
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Mostrar o uso de 5 h e 7 dias do Claude?").font(F.ui(12, .semibold)).foregroundStyle(Cor.texto)
      Text("O Orion lê o login que o Claude Code guarda no Chaveiro do macOS e consulta só a página de uso da Anthropic, a cada \(Int(loja.ajustes.usoIntervalo)) min. O macOS pode pedir permissão uma vez — escolha “Sempre Permitir”.")
        .font(F.ui(11)).foregroundStyle(Cor.texto2).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 6) {
        Pilula(rotulo: "Mostrar uso", simbolo: "chart.bar.fill", ativo: true, dica: "Liga a leitura do uso do Claude") { loja.ajustes.usoClaude = "ligado" }
        Pilula(rotulo: "Agora não", simbolo: nil, ativo: false, dica: "Não lê o Chaveiro. Dá para ligar depois em Ajustes → Contas") { loja.ajustes.usoClaude = "desligado" }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Cor.ambar.opacity(0.09)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Cor.ambar.opacity(0.28)))
  }
}

struct LinhaContaUso: View {
  @Bindable var loja: Loja
  let conta: Conta
  var escolhida = false           // é a conta do botão "Novo …"
  var aoEscolher: (() -> Void)? = nil

  var body: some View {
    let padrao = loja.contaPadrao(conta.tipo)?.id == conta.id
    let aba = loja.abaAtiva
    let naAba = aba?.conta(conta.tipo) == conta.id
    let uso = loja.usos[conta.id]
    let mostraUso = loja.podeLerUso(conta)
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .center, spacing: 6) {
        Circle().fill(Color(hex: conta.cor)).frame(width: 9, height: 9)
        Text(conta.nome).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto).lineLimit(1)
        if escolhida && loja.contas(conta.tipo).count > 1 { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Cor.acento).help("Conta do próximo agente aberto por este painel") }
        Spacer(minLength: 4)
        Pilula(rotulo: "Padrão", simbolo: padrao ? "star.fill" : "star", ativo: padrao,
               dica: padrao ? "É a conta dos próximos agentes do \(nomeFerramenta(conta.tipo))" : "Usar esta conta nos próximos agentes do \(nomeFerramenta(conta.tipo))") { loja.definirPadrao(conta) }
        if let aba, loja.painelPrincipal(aba)?.tipoAgente == conta.tipo {
          Pilula(rotulo: "Nesta aba", simbolo: naAba ? "checkmark" : "arrow.left.arrow.right", ativo: naAba,
                 dica: naAba ? "A aba aberta já usa esta conta" : "Trocar a aba aberta para esta conta (um agente rodando reinicia, com confirmação)") { loja.fecharUso(); loja.trocarConta(aba, para: conta) }
        }
      }
      if conta.logado {
        if !detalhe.isEmpty { Text(detalhe).font(F.ui(11)).foregroundStyle(Cor.texto3).lineLimit(1).truncationMode(.middle) }
      } else {
        Text("sem login — abra um agente nesta conta e entre").font(F.ui(11)).foregroundStyle(Cor.amarelo)
      }
      if mostraUso && conta.logado {
        if let u = uso, u.h5 != nil || u.d7 != nil {
          if let h = u.h5 { BarraUsoFina(nome: "5 h", janela: h) }
          if let d = u.d7 { BarraUsoFina(nome: "7 d", janela: d) }
          if let e = u.erro { Text(e).font(F.ui(10.5)).foregroundStyle(Cor.amarelo).lineLimit(2) }
        } else if loja.usoCarregando.contains(conta.id) {
          Text("lendo o uso…").font(F.ui(10.5)).foregroundStyle(Cor.texto4)
        } else {
          Text(uso?.erro ?? "sem dados de uso ainda").font(F.ui(10.5)).foregroundStyle(uso?.erro != nil ? Cor.amarelo : Cor.texto4).lineLimit(2)
        }
      }
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: R.controle + 1, style: .continuous).fill(Cor.elevado))
    .overlay(RoundedRectangle(cornerRadius: R.controle + 1, style: .continuous).strokeBorder(escolhida ? Cor.acento.opacity(0.5) : Cor.linha))
    .contentShape(Rectangle())
    .onTapGesture { aoEscolher?() }
  }

  var detalhe: String {
    let plano = conta.plano.contains("_") ? "" : conta.plano
    return [conta.email, plano].filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

/// Botão pequeno em cápsula (ações do cartão de uso e do quadro).
struct Pilula: View {
  let rotulo: String?
  let simbolo: String?
  let ativo: Bool
  let dica: String
  var desligado = false
  let acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    Button(action: acao) {
      HStack(spacing: 4) {
        if let simbolo { Image(systemName: simbolo).font(.system(size: 10.5, weight: .semibold)) }
        if let rotulo { Text(rotulo).font(F.ui(11.5, .medium)).lineLimit(1) }
      }
      .foregroundStyle(ativo ? Cor.acento : (sobre ? Cor.texto : Cor.texto2))
      .brightness(ativo && Cor.claro ? -0.12 : 0)
      .padding(.horizontal, rotulo == nil ? 7 : 9).frame(height: F.m(24))
      .background(Capsule().fill(ativo ? Cor.acento.opacity(0.16) : (sobre ? Cor.vidro2 : Cor.vidro)))
      .overlay(Capsule().strokeBorder(ativo ? Cor.acento.opacity(0.45) : Cor.linha))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain).onHover { sobre = $0 }.help(dica)
    .disabled(desligado).opacity(desligado ? 0.35 : 1)
    .fixedSize()
  }
}

struct BarraUsoFina: View {
  let nome: String
  let janela: Uso.Janela
  var body: some View {
    let pct = janela.pctAtual
    HStack(spacing: 8) {
      Text(nome).frame(width: 28, alignment: .leading).foregroundStyle(Cor.texto3)
      GeometryReader { g in
        ZStack(alignment: .leading) {
          Capsule().fill(Cor.vidro2)
          Capsule().fill(Cor.uso(pct)).frame(width: max(pct > 0 ? 4 : 0, g.size.width * min(1, pct / 100)))
        }
      }
      .frame(height: 5)
      Text("\(Int(pct.rounded()))%").fontWeight(.semibold).foregroundStyle(pct >= 60 ? Cor.uso(pct) : Cor.texto).frame(width: 38, alignment: .trailing)
      Text(BarraUsoFina.zera(janela)).foregroundStyle(Cor.texto3).frame(width: 92, alignment: .leading).lineLimit(1)
    }
    .font(F.ui(11)).monospacedDigit()
  }

  /// "zera 16:40" (hoje) ou "zera qui 09:00".
  static func zera(_ j: Uso.Janela) -> String {
    guard let r = j.reinicia else { return "" }
    if j.zerou { return "já zerou" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = Calendar.current.isDateInToday(r) ? "HH:mm" : "EEE HH:mm"
    return "zera " + f.string(from: r).replacingOccurrences(of: ".", with: "")
  }
}
