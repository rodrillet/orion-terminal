import SwiftUI
import AppKit
import SwiftTerm
import Observation

// Vista de conversa: o mesmo agente, lido como um chat. À direita, o que você mandou pelo
// compose; à esquerda, o que o agente escreveu depois de cada mensagem — tirado do texto do
// próprio terminal (que continua sendo a verdade: é só outra forma de olhar para ele).
// Leve por construção: só existe com a vista aberta e só relê o terminal quando chega saída nova.

enum Conversa {
  /// Uma mensagem mandada pelo compose e a linha do terminal em que ela entrou.
  struct Enviada: Equatable {
    let texto: String
    let em: Date
    let linha: Int
    var anexos: [String] = []      // caminhos de imagens e arquivos que foram junto
    var de: String? = nil          // veio da caixa de entrada: quem mandou ("@vega")
  }

  struct Balao: Identifiable, Equatable {
    let id: Int
    let meu: Bool
    let texto: String
    let em: Date?
    var anexos: [String] = []
    var de: String? = nil
    var ferramentas: [String] = []   // ferramentas usadas antes desta resposta (só do arquivo de sessão)
    var markdown = false             // texto original do agente (do arquivo de sessão), não da tela
  }

  /// Linhas que são moldura do programa (caixas, réguas, dicas de atalho), não resposta.
  private static let moldura = CharacterSet(charactersIn: "╭╮╰╯│─━┃┌┐└┘├┤┬┴┼═║╔╗╚╝▔▁ >❯›")

  static func limpar(_ linhas: [String], eco: String?) -> String {
    let ecoCurto = eco.map { String($0.prefix(40)) }
    var saida: [String] = []
    for bruta in linhas {
      var l = bruta.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
      if l.unicodeScalars.allSatisfy({ moldura.contains($0) }) { if saida.last != "" { saida.append("") }; continue }
      // Conteúdo dentro de uma caixa: tira as bordas laterais.
      if l.hasPrefix("│"), l.hasSuffix("│"), l.count > 2 { l = String(l.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces) }
      let semPrompt = l.drop { "> ❯›".contains($0) }.trimmingCharacters(in: .whitespaces)
      if let e = ecoCurto, !e.isEmpty, semPrompt.hasPrefix(e) || (semPrompt.count > 12 && e.hasPrefix(semPrompt)) { continue }   // o eco do que você digitou
      if l.contains("? for shortcuts") || l.contains("esc to interrupt") || l.contains("bypass permissions") { continue }
      // Marcadores do Claude Code ("⏺ resposta", "⎿ detalhe") não ajudam a ler no chat.
      if l.hasPrefix("⏺ ") { l = String(l.dropFirst(2)) }
      saida.append(l)
    }
    while saida.first == "" { saida.removeFirst() }
    while saida.last == "" { saida.removeLast() }
    return saida.joined(separator: "\n")
  }

  /// Tira do texto lido da tela as chamadas de ferramenta ("Read(src/a.tsx)" seguida de
  /// "⎿ Read 182 lines") e devolve as duas coisas: o texto que se lê e a lista de passos.
  static func separarFerramentas(_ texto: String) -> (String, [String]) {
    var linhas: [String] = []
    var passos: [String] = []
    let chamada = try? NSRegularExpression(pattern: #"^([A-Z][A-Za-z]+(?:\.[a-z_]+)?)\((.*)\)\s*$"#)
    for l in texto.components(separatedBy: "\n") {
      let t = l.trimmingCharacters(in: .whitespaces)
      let r = NSRange(t.startIndex..., in: t)
      if let m = chamada?.firstMatch(in: t, range: r), let n = Range(m.range(at: 1), in: t), let a = Range(m.range(at: 2), in: t) {
        passos.append("\(t[n]) · \(t[a])"); continue
      }
      if !passos.isEmpty, t.hasPrefix("⎿") || t.hasPrefix("└") {
        let det = t.drop { "⎿└ ".contains($0) }.trimmingCharacters(in: .whitespaces)
        if !det.isEmpty { passos[passos.count - 1] += " — " + det }
        continue
      }
      linhas.append(l)
    }
    // Linhas em branco que sobraram juntas viram uma só.
    var limpo: [String] = []
    for l in linhas where !(l.trimmingCharacters(in: .whitespaces).isEmpty && limpo.last?.trimmingCharacters(in: .whitespaces).isEmpty != false) { limpo.append(l) }
    while limpo.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { limpo.removeLast() }
    return (limpo.joined(separator: "\n"), passos)
  }

  /// Texto da tela que precisa de fonte de largura fixa (tabelas, colunas alinhadas, árvores).
  static func pareceTabular(_ texto: String) -> Bool {
    texto.contains("   ") && texto.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).contains("   ") }.count >= 2
      || texto.unicodeScalars.contains { (0x2500...0x257F).contains($0.value) }
  }
}

extension Painel {
  /// Linha (absoluta, no buffer do terminal) em que o cursor está agora.
  func linhaDoCursor() -> Int {
    view?.terminalContentSnapshot(region: .history(maximumScrollbackRows: 0))?.cursorRow ?? 0
  }

  /// Monta os balões: antes da primeira mensagem, o que já estava na tela; depois, pergunta e resposta.
  /// `ultimas`: só a tela e as últimas N linhas do histórico (a prévia da barra lateral não precisa
  /// fotografar as 5.000 linhas a cada vez que um agente para).
  func baloes(ultimas: Int? = nil) -> [Conversa.Balao] {
    let regiao: TerminalContentRegion = ultimas.map { .history(maximumScrollbackRows: $0) } ?? .all
    guard let v = view, let snap = v.terminalContentSnapshot(region: regiao) else { return [] }
    var linhas: [(Int, String)] = []
    for r in snap.rows {
      let t = r.text.replacingOccurrences(of: "\u{0}", with: " ")
      if r.isWrapped, !linhas.isEmpty { linhas[linhas.count - 1].1 += t } else { linhas.append((r.absoluteRow, t)) }
    }
    var out: [Conversa.Balao] = []
    var n = 0
    let fimTela = (linhas.last?.0 ?? 0) + 1
    func agente(de: Int, ate: Int, eco: String?) {
      var trecho = linhas.filter { $0.0 >= de && $0.0 < ate }.map(\.1)
      // Com um pedido de permissão na tela, a pergunta já aparece como cartão com botões:
      // corta a caixa dela do último trecho para não mostrar a mesma coisa duas vezes.
      if ate == fimTela, let perm = permissao,
         let i = trecho.lastIndex(where: { $0.contains(perm.pergunta.prefix(30)) }) {
        let inicioCaixa = trecho[max(0, i - 30)..<i].lastIndex { l in
          let t = l.trimmingCharacters(in: .whitespaces)
          return t.hasPrefix("╭") || t.hasPrefix("┌") || (t.count > 10 && t.allSatisfy { "─━".contains($0) })
        }
        trecho = Array(trecho[..<(inicioCaixa ?? i)])
      }
      let (texto, passos) = Conversa.separarFerramentas(Conversa.limpar(trecho, eco: eco))
      if !texto.isEmpty || !passos.isEmpty { out.append(Conversa.Balao(id: n, meu: false, texto: texto, em: nil, ferramentas: passos)); n += 1 }
    }
    let fim = (linhas.last?.0 ?? 0) + 1
    let inicio = max(linhas.first?.0 ?? 0, inicioConversa ?? 0)       // "Limpar conversa" esconde o que veio antes
    let primeira = enviadas.first?.linha ?? fim
    // O que veio antes da primeira mensagem (no máximo as últimas 60 linhas).
    agente(de: max(inicio, primeira - 60), ate: primeira, eco: nil)
    for (i, m) in enviadas.enumerated() {
      out.append(Conversa.Balao(id: n, meu: true, texto: m.texto, em: m.em, anexos: m.anexos, de: m.de)); n += 1
      agente(de: m.linha, ate: i + 1 < enviadas.count ? enviadas[i + 1].linha : fim, eco: m.texto)
    }
    return out
  }

  /// Começa a conversa do zero: o que já está no terminal some da vista (o terminal não muda).
  func limparConversa() {
    enviadas = []
    inicioConversa = linhaDoCursor() + 1
    inicioConversaEm = Date()
    caixa?.recarregarConversa()
  }

  /// A conversa inteira como texto (para copiar).
  func conversaComoTexto() -> String {
    let nome = persona?.nome ?? nomeLongoFerramenta(tipoAgente ?? "shell")
    return baloesConversa().filter { !$0.texto.isEmpty }.map { b in
      let quem = b.meu ? "Você" : nome
      let anexos = b.anexos.isEmpty ? "" : "\n[anexos: " + b.anexos.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ") + "]"
      return "**\(quem):**\n\(b.texto)\(anexos)"
    }.joined(separator: "\n\n")
  }
}

/// Estado da vista (um por painel com a conversa aberta).
@MainActor @Observable
final class EstadoConversa {
  var baloes: [Conversa.Balao] = []
  @ObservationIgnored var ultimaLeitura = Date.distantPast
  @ObservationIgnored var relogio: Timer?

  func comecar(_ p: Painel) {
    atualizar(p, forcar: true)
    relogio?.invalidate()
    let t = Timer(timeInterval: 0.8, repeats: true) { [weak self, weak p] _ in
      MainActor.assumeIsolated { if let p { self?.atualizar(p) } }
    }
    t.tolerance = 0.3
    RunLoop.main.add(t, forMode: .common)
    relogio = t
  }

  func parar() { relogio?.invalidate(); relogio = nil }

  /// Só relê o terminal se chegou saída depois da última leitura.
  func atualizar(_ p: Painel, forcar: Bool = false) {
    let saida = p.leitor.ultimaSaida
    guard forcar || saida > ultimaLeitura else { return }
    ultimaLeitura = Date()
    let novos = p.baloesConversa()
    if novos != baloes { baloes = novos }
  }
}

struct ConversaView: View {
  @Bindable var painel: Painel
  @Bindable var estado: EstadoConversa

  var body: some View {
    VStack(spacing: 0) {
      cabecalho
      Divider().opacity(0.6)
      lista
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .preferredColorScheme(Cor.claro ? .light : .dark)
  }

  // MARK: Cabeçalho

  /// Barra fina do chat: o estado e as ações (nome e avatar já estão no cabeçalho do painel).
  private var cabecalho: some View {
    let loja = painel.loja
    return HStack(spacing: 8) {
      ChipEstado(painel: painel)
      if painel.estado != .trabalhando && painel.estado != .esperando, let t = painel.tarefa, !t.isEmpty {
        Text(t).font(F.ui(11)).foregroundStyle(Cor.texto3).lineLimit(1)
      }
      if painel.leitorSessao.url != nil {
        Label("lido da sessão", systemImage: "doc.text").labelStyle(.titleAndIcon)
          .font(F.ui(10.5)).foregroundStyle(Cor.texto4)
          .help("As mensagens vêm do arquivo da conversa do agente (texto original, com Markdown)")
      }
      Spacer(minLength: 6)
      BotaoMini("doc.on.doc", "Copiar a conversa inteira (Markdown)") { loja.copiar(painel.conversaComoTexto(), aviso: "Conversa copiada") }
      BotaoMini("trash", "Limpar a conversa (o terminal continua igual)") {
        loja.confirmar("Limpar esta conversa?", "As mensagens somem desta vista. O terminal e a sessão do agente não mudam.", "Limpar conversa",
                       destrutivo: true, simbolo: "trash") { [weak painel] in painel?.limparConversa() }
      }
      BotaoMini("terminal", "Voltar ao terminal  ⌥⌘C") { painel.conversa = false }
    }
    .padding(.leading, 12).padding(.trailing, 10).frame(height: 32)
  }

  // MARK: Balões

  private var lista: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if estado.baloes.isEmpty { vazio }
          ForEach(Array(estado.baloes.enumerated()), id: \.element.id) { i, b in
            let dia = b.em != nil && mudouODia(i)
            if dia, let em = b.em { SeparadorDia(data: em).padding(.vertical, 8) }
            BalaoView(painel: painel, balao: b, inicioGrupo: dia || inicioGrupo(i))
              .padding(.top, i > 0 && (dia || inicioGrupo(i)) ? 10 : 0)
              .id(b.id)
          }
          if let perm = painel.permissao {
            HStack(alignment: .top, spacing: 10) {
              if let persona = painel.persona { AvatarPersona(persona: persona, tamanho: 28, estado: .esperando, fixo: true).frame(width: 30) }
              CartaoPermissao(painel: painel, permissao: perm).frame(maxWidth: 560, alignment: .leading)
              Spacer(minLength: 24)
            }
            .padding(.horizontal, 8).padding(.top, 12)
            .id(-2)
          } else if painel.estado == .trabalhando { digitando.padding(.top, 12) }
          SwiftUI.Color.clear.frame(height: 4).id(-1)
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
      }
      .onChange(of: estado.baloes.count) { _, _ in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(-1, anchor: .bottom) } }
      .onChange(of: painel.permissao) { _, _ in
        estado.atualizar(painel, forcar: true)     // corta (ou devolve) a pergunta do último trecho
        // Depois do cartão entrar no layout (senão rola até antes dele).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(-1, anchor: .bottom) } }
      }
      .onChange(of: estado.baloes.last?.texto.count) { _, _ in proxy.scrollTo(-1, anchor: .bottom) }
      .onAppear { proxy.scrollTo(-1, anchor: .bottom); DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { proxy.scrollTo(-1, anchor: .bottom) } }
    }
  }

  /// Mensagens seguidas do mesmo autor, a menos de 5 minutos, ficam no mesmo grupo (um avatar só).
  private func inicioGrupo(_ i: Int) -> Bool {
    guard i > 0 else { return true }
    let a = estado.baloes[i - 1], b = estado.baloes[i]
    if a.meu != b.meu || a.de != b.de { return true }
    if let ea = a.em, let eb = b.em, eb.timeIntervalSince(ea) > 300 { return true }
    return false
  }

  private func mudouODia(_ i: Int) -> Bool {
    guard let em = estado.baloes[i].em else { return false }
    let anteriores = estado.baloes[..<i].compactMap(\.em)
    guard let ultima = anteriores.last else { return true }
    return !Calendar.current.isDate(ultima, inSameDayAs: em)
  }

  private var vazio: some View {
    VStack(spacing: 10) {
      if let persona = painel.persona { AvatarPersona(persona: persona, tamanho: 54) }
      Text("Comece a conversa").font(F.ui(14, .semibold)).foregroundStyle(Cor.texto)
      Text("Escreva no campo abaixo. Arraste imagens e arquivos para cá, ou cole com ⌘V — eles aparecem com prévia antes de enviar.")
        .font(F.ui(12)).foregroundStyle(Cor.texto3).multilineTextAlignment(.center).frame(maxWidth: 320)
    }
    .frame(maxWidth: .infinity).padding(.top, 50)
  }

  private var digitando: some View {
    HStack(spacing: 10) {
      if let persona = painel.persona { AvatarPersona(persona: persona, tamanho: 28, estado: .trabalhando, fixo: true).frame(width: 30) }
      HStack(spacing: 4) { ForEach(0..<3) { i in Circle().fill(Cor.texto3).frame(width: 5, height: 5).opacity(1 - Double(i) * 0.25) } }
      Text("\(painel.persona?.nome ?? "O agente") está trabalhando…").font(F.ui(12)).foregroundStyle(Cor.texto3)
    }
    .padding(.horizontal, 8)
  }

  static let hora: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
}

private struct SeparadorDia: View {
  let data: Date
  var body: some View {
    HStack(spacing: 8) {
      Rectangle().fill(Cor.linha).frame(height: 1)
      Text(Calendar.current.isDateInToday(data) ? "Hoje" : Calendar.current.isDateInYesterday(data) ? "Ontem"
           : data.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "pt_BR"))))
        .font(F.ui(10.5, .medium)).foregroundStyle(Cor.texto4).fixedSize()
      Rectangle().fill(Cor.linha).frame(height: 1)
    }
    .padding(.vertical, 2)
  }
}

/// Uma mensagem, no layout de chat de equipe: avatar e nome na primeira de um grupo, texto na
/// largura da coluna (sem balão), passos das ferramentas recolhidos por último e ações ao passar
/// o mouse. Quem é agente se vê pelo mascote; você aparece como "Você".
private struct BalaoView: View {
  let painel: Painel
  let balao: Conversa.Balao
  var inicioGrupo = true
  @Estado private var sobre = false

  var body: some View {
    let b = balao
    let meu = b.meu && b.de == nil          // mensagem da caixa de entrada: vem de outro agente
    HStack(alignment: .top, spacing: 10) {
      Group {
        if !inicioGrupo { SwiftUI.Color.clear.frame(width: 30, height: 1) }
        else if meu { AvatarVoce(tamanho: 28) }
        else if b.de != nil {
          Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Cor.texto2)
            .frame(width: 28, height: 28).background(Circle().fill(Cor.vidro2))
        }
        else if let persona = painel.persona { AvatarPersona(persona: persona, tamanho: 28, maestro: painel.loja.ehMaestro(painel), fixo: true) }
        else { IconePrograma(processo: painel.tipoAgente ?? painel.programa, tamanho: 26) }
      }
      .frame(width: 30)
      VStack(alignment: .leading, spacing: 6) {
        if inicioGrupo { cabecalho(meu: meu) }
        if !b.anexos.isEmpty { GradeAnexos(caminhos: b.anexos, aDireita: false) }
        if !b.texto.isEmpty && b.markdown {
          TextoMarkdown(texto: b.texto, loja: painel.loja)
        } else if !b.texto.isEmpty {
          Text(b.texto)
            .font(!meu && Conversa.pareceTabular(b.texto) ? F.mono(12) : F.ui(13.5))
            .foregroundStyle(Cor.texto)
            .textSelection(.enabled)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !b.ferramentas.isEmpty { FerramentasUsadas(lista: b.ferramentas) }
      }
      .frame(maxWidth: 760, alignment: .leading)
      Spacer(minLength: 24)
    }
    .padding(.horizontal, 8).padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sobre ? Cor.vidro : SwiftUI.Color.clear))
    .overlay(alignment: .topTrailing) {
      if sobre && !b.texto.isEmpty { acoes.offset(x: -8, y: -10) }
    }
    .contentShape(Rectangle())
    .onHover { sobre = $0 }
    .contextMenu {
      Button("Copiar") { painel.loja.copiar(b.texto) }
      Button("Copiar como bloco de código") { painel.loja.copiar("```\n\(b.texto)\n```") }
      Button("Citar no compose") { citar() }
      if meu { Button("Escrever de novo no compose") { painel.inserirNoCompose(b.texto); painel.focarCompose() } }
    }
  }

  @ViewBuilder private func cabecalho(meu: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      if meu {
        Text("Você").font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
      } else if let de = balao.de {
        Text(de).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
        EtiquetaLinha(texto: "caixa de entrada")
      } else if let persona = painel.persona {
        Text(persona.nome).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
        if !persona.papel.isEmpty { Text(persona.papel).font(F.ui(11.5)).foregroundStyle(Cor.texto3) }
      } else {
        Text(nomeLongoFerramenta(painel.tipoAgente ?? "shell")).font(F.ui(13, .semibold)).foregroundStyle(Cor.texto)
      }
      if let em = balao.em { Text(ConversaView.hora.string(from: em)).font(F.ui(11)).monospacedDigit().foregroundStyle(Cor.texto4) }
    }
  }

  private var acoes: some View {
    HStack(spacing: 0) {
      BotaoMini("doc.on.doc", "Copiar") { painel.loja.copiar(balao.texto) }
      BotaoMini("quote.bubble", "Citar no compose") { citar() }
      if balao.meu { BotaoMini("arrow.uturn.backward", "Escrever de novo no compose") { painel.inserirNoCompose(balao.texto); painel.focarCompose() } }
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.regularMaterial))
    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Cor.linhaForte))
    .shadow(color: Cor.sombra.opacity(0.5), radius: 6, y: 2)
  }

  private func citar() {
    let trecho = balao.texto.split(separator: "\n", omittingEmptySubsequences: false).prefix(12).map { "> " + $0 }.joined(separator: "\n")
    painel.inserirNoCompose(trecho + "\n\n")
    painel.focarCompose()
  }
}

/// Você, no chat: círculo neutro (pessoas são círculos; agentes são mascotes).
struct AvatarVoce: View {
  var tamanho: CGFloat = 28
  var body: some View {
    Image(systemName: "person.fill").font(.system(size: tamanho * 0.46, weight: .medium)).foregroundStyle(Cor.texto2)
      .frame(width: tamanho, height: tamanho)
      .background(Circle().fill(LinearGradient(colors: [Cor.vidro2, Cor.vidro], startPoint: .top, endPoint: .bottom)))
      .overlay(Circle().strokeBorder(Cor.linha))
  }
}

/// Anexos de uma mensagem: imagens em miniatura e arquivos como cartões; clique abre a prévia.
private struct GradeAnexos: View {
  let caminhos: [String]
  let aDireita: Bool
  var body: some View {
    let imagens = caminhos.filter { Compose.ehImagem($0) }
    let outros = caminhos.filter { !Compose.ehImagem($0) }
    VStack(alignment: aDireita ? .trailing : .leading, spacing: 4) {
      if !imagens.isEmpty {
        HStack(spacing: 4) { ForEach(imagens, id: \.self) { c in ItemAnexoBalao(caminho: c, imagem: true, unica: imagens.count == 1) } }
      }
      ForEach(outros, id: \.self) { c in ItemAnexoBalao(caminho: c, imagem: false, unica: false) }
    }
  }
}

private struct ItemAnexoBalao: View {
  let caminho: String
  let imagem: Bool
  let unica: Bool
  @Estado private var previa = false

  var body: some View {
    Group {
      if imagem {
        let lado: CGFloat = unica ? 180 : 90
        MiniaturaArquivo(caminho: caminho, lado: lado)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Cor.linha))
      } else {
        HStack(spacing: 8) {
          MiniaturaArquivo(caminho: caminho, lado: 28)
          VStack(alignment: .leading, spacing: 1) {
            Text((caminho as NSString).lastPathComponent).font(F.ui(12, .medium)).foregroundStyle(Cor.texto).lineLimit(1).truncationMode(.middle)
            Text(Arquivos.descricao(caminho)).font(F.ui(10.5)).foregroundStyle(Cor.texto3)
          }
          .frame(maxWidth: 200, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Cor.vidro2))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Cor.linha))
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { previa = true }
    .help(caminho)
    .popover(isPresented: $previa) { PreviaArquivo(caminho: caminho) }
  }
}

/// Avatar de um personagem: o bicho dele sobre a cor dele. Com `estado`, um anel na cor do estado;
/// com `ferramenta`, o ícone real do app (Claude, Codex, Gemini) no canto.
struct AvatarPersona: View {
  let persona: Persona
  var tamanho: CGFloat = 32
  var ferramenta: String? = nil
  var estado: EstadoPainel? = nil
  var maestro = false

  /// Escala do ajuste "Tamanho dos mascotes" (desligue com `fixo` em seletores e diálogos).
  var fixo = false
  /// Animar (piscar, olhar, respirar). nil = automático: os que mostram estado e não são miúdos.
  var animado: Bool? = nil
  /// Mostra o ponto de estado no canto (o cabeçalho do painel usa o ícone da ferramenta no lugar).
  var pontoEstado = true

  var body: some View {
    let tamanho = fixo ? self.tamanho : (self.tamanho * Aparencia.atual.mascote).rounded()
    _ = Aparencia.atual.versao
    let vivo = (animado ?? (estado != nil && tamanho >= 22)) && Aparencia.atual.animarMascotes
    return DesenhoMascote(forma: Mascote.forma(persona), cor: persona.cor, tamanho: tamanho, humor: estado?.humor ?? .normal,
                          acessorio: Acessorio.de(papel: persona.papel, maestro: maestro), animado: vivo,
                          semente: Double(Mascote.hashEstavel(persona.nome) % 1000) / 100)
    // Estado: um ponto no canto (como num chat); sem estado, a ferramenta.
    .overlay(alignment: .bottomTrailing) {
      if pontoEstado, let anel {
        Circle().fill(anel).frame(width: max(7, tamanho * 0.28), height: max(7, tamanho * 0.28))
          .overlay(Circle().strokeBorder(Fundo.cor, lineWidth: max(1.5, tamanho * 0.06)))
          .offset(x: tamanho * 0.06, y: tamanho * 0.04)
      } else if let ferramenta {
        IconePrograma(processo: ferramenta, tamanho: max(11, tamanho * 0.38)).offset(x: tamanho * 0.1, y: tamanho * 0.08)
      }
    }
  }

  private var anel: SwiftUI.Color? {
    guard let e = estado else { return nil }
    switch e {
    case .trabalhando, .esperando, .rodando, .saiu: return e.cor
    default: return nil
    }
  }
}
