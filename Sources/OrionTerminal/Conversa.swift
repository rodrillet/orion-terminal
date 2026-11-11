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
  }

  struct Balao: Identifiable, Equatable {
    let id: Int
    let meu: Bool
    let texto: String
    let em: Date?
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
      saida.append(l)
    }
    while saida.first == "" { saida.removeFirst() }
    while saida.last == "" { saida.removeLast() }
    return saida.joined(separator: "\n")
  }
}

extension Painel {
  /// Linha (absoluta, no buffer do terminal) em que o cursor está agora.
  func linhaDoCursor() -> Int {
    view?.terminalContentSnapshot(region: .history(maximumScrollbackRows: 0))?.cursorRow ?? 0
  }

  /// Monta os balões: antes da primeira mensagem, o que já estava na tela; depois, pergunta e resposta.
  func baloes() -> [Conversa.Balao] {
    guard let v = view, let snap = v.terminalContentSnapshot(region: .all) else { return [] }
    var linhas: [(Int, String)] = []
    for r in snap.rows {
      let t = r.text.replacingOccurrences(of: "\u{0}", with: " ")
      if r.isWrapped, !linhas.isEmpty { linhas[linhas.count - 1].1 += t } else { linhas.append((r.absoluteRow, t)) }
    }
    var out: [Conversa.Balao] = []
    var n = 0
    func agente(de: Int, ate: Int, eco: String?) {
      let trecho = linhas.filter { $0.0 >= de && $0.0 < ate }.map(\.1)
      let texto = Conversa.limpar(trecho, eco: eco)
      if !texto.isEmpty { out.append(Conversa.Balao(id: n, meu: false, texto: texto, em: nil)); n += 1 }
    }
    let fim = (linhas.last?.0 ?? 0) + 1
    let primeira = enviadas.first?.linha ?? fim
    // O que veio antes da primeira mensagem (no máximo as últimas 60 linhas).
    agente(de: max(linhas.first?.0 ?? 0, primeira - 60), ate: primeira, eco: nil)
    for (i, m) in enviadas.enumerated() {
      out.append(Conversa.Balao(id: n, meu: true, texto: m.texto, em: m.em)); n += 1
      agente(de: m.linha, ate: i + 1 < enviadas.count ? enviadas[i + 1].linha : fim, eco: m.texto)
    }
    return out
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
    let novos = p.baloes()
    if novos != baloes { baloes = novos }
  }
}

struct ConversaView: View {
  @Bindable var painel: Painel
  @Bindable var estado: EstadoConversa

  var body: some View {
    let persona = painel.persona
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          Text("Conversa — o terminal continua por baixo (⌥⌘C volta)").font(F.ui(10.5)).foregroundStyle(Cor.texto4).frame(maxWidth: .infinity)
          if estado.baloes.isEmpty {
            Text("Nada ainda. Escreva no compose abaixo — a conversa aparece aqui.")
              .font(F.ui(12.5)).foregroundStyle(Cor.texto3).frame(maxWidth: .infinity).padding(.top, 30)
          }
          ForEach(estado.baloes) { b in
            HStack(alignment: .top, spacing: 8) {
              if b.meu { Spacer(minLength: 40) }
              else if let persona { AvatarPersona(persona: persona, tamanho: 26) }
              else { IconePrograma(processo: painel.tipoAgente ?? painel.programa, tamanho: 24) }
              VStack(alignment: b.meu ? .trailing : .leading, spacing: 3) {
                Text(b.texto)
                  .font(b.meu ? F.ui(13) : F.mono(12))
                  .foregroundStyle(b.meu ? Cor.sobreAcento : Cor.texto)
                  .textSelection(.enabled)
                  .lineSpacing(2)
                  .padding(.horizontal, 11).padding(.vertical, 8)
                  .background(RoundedRectangle(cornerRadius: R.controle + 3, style: .continuous).fill(b.meu ? Cor.acento : Cor.elevado))
                  .overlay(RoundedRectangle(cornerRadius: R.controle + 3, style: .continuous).strokeBorder(b.meu ? Color.clear : Cor.linha))
                if let em = b.em { Text(Self.hora.string(from: em)).font(F.ui(10)).foregroundStyle(Cor.texto4) }
              }
              if !b.meu { Spacer(minLength: 24) }
            }
            .id(b.id)
          }
          Color.clear.frame(height: 4).id(-1)
        }
        .padding(12)
      }
      .onChange(of: estado.baloes.count) { _, _ in proxy.scrollTo(-1, anchor: .bottom) }
      .onChange(of: estado.baloes.last?.texto.count) { _, _ in proxy.scrollTo(-1, anchor: .bottom) }
      .onAppear { proxy.scrollTo(-1, anchor: .bottom) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .preferredColorScheme(Cor.claro ? .light : .dark)
  }

  static let hora: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
}

/// Avatar de um personagem: o bicho dele sobre a cor dele. Com `estado`, um anel na cor do estado;
/// com `ferramenta`, o ícone real do app (Claude, Codex, Gemini) no canto.
struct AvatarPersona: View {
  let persona: Persona
  var tamanho: CGFloat = 32
  var ferramenta: String? = nil
  var estado: EstadoPainel? = nil
  var maestro = false

  var body: some View {
    let cor = Color(hex: persona.cor)
    ZStack {
      Circle().fill(LinearGradient(colors: [cor.opacity(Cor.claro ? 0.38 : 0.42), cor.opacity(Cor.claro ? 0.20 : 0.16)], startPoint: .top, endPoint: .bottom))
      Text(persona.avatar).font(.system(size: tamanho * 0.56))
    }
    .frame(width: tamanho, height: tamanho)
    .overlay(Circle().strokeBorder(anel ?? cor.opacity(0.55), lineWidth: anel != nil ? max(1.5, tamanho * 0.07) : 1))
    .overlay(alignment: .bottomTrailing) {
      if let ferramenta { IconePrograma(processo: ferramenta, tamanho: max(12, tamanho * 0.42)).offset(x: tamanho * 0.12, y: tamanho * 0.12) }
    }
    .overlay(alignment: .topLeading) {
      if maestro {
        Image(systemName: "wand.and.stars").font(.system(size: max(7, tamanho * 0.26), weight: .bold)).foregroundStyle(Cor.claro ? .white : .black)
          .padding(tamanho * 0.07).background(Circle().fill(Cor.ambar)).offset(x: -tamanho * 0.12, y: -tamanho * 0.12)
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
