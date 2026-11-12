import SwiftUI
import AppKit

// Pedido de permissão: quando o agente para perguntando "Do you want to proceed?" com opções
// numeradas (Claude Code, Codex e Gemini CLI fazem assim), o Orion lê a pergunta da tela e
// oferece as opções como botões — no chat e no cartão do painel. Também serve para a caixa de
// entrada não colar mensagens por cima da pergunta nem avisar "parou sem responder" por engano.

struct Permissao: Equatable {
  struct Opcao: Equatable, Identifiable {
    let id: Int              // número na tela (1, 2, 3…)
    let rotulo: String
    let selecionada: Bool
    var tecla: String { String(id) }
    /// "Não", "No", "Negar"…: botão sem destaque.
    var negativa: Bool {
      let r = rotulo.lowercased()
      return r.hasPrefix("no") || r.hasPrefix("não") || r.hasPrefix("nao") || r.contains("tell claude") || r.contains("deny") || r.contains("cancel")
    }
  }

  let pergunta: String
  let detalhe: String
  let opcoes: [Opcao]
}

enum DetectorPermissao {
  private static let moldura = CharacterSet(charactersIn: "╭╮╰╯│─━┃┌┐└┘├┤┬┴┼═║╔╗╚╝▌▐ ")

  private static func limpar(_ l: String) -> String {
    var s = l.replacingOccurrences(of: "\u{0}", with: " ")
    s = s.trimmingCharacters(in: moldura)
    return s.trimmingCharacters(in: .whitespaces)
  }

  /// Lê as últimas linhas da tela. Só reconhece quando há uma pergunta (linha com "?") logo
  /// acima de duas ou mais opções numeradas em sequência, perto do fim da tela.
  static func ler(_ brutas: [String]) -> Permissao? {
    var linhas = brutas.map(limpar)
    while linhas.last?.isEmpty == true { linhas.removeLast() }
    guard linhas.count >= 3 else { return nil }
    let janela = Array(linhas.suffix(30))
    let opcaoRx = try! NSRegularExpression(pattern: #"^([❯>›»]\s*)?(\d)[.)]\s+(.+)$"#)
    var opcoes: [(Int, Permissao.Opcao)] = []          // (índice da linha, opção)
    for (i, l) in janela.enumerated() {
      let ns = l as NSString
      guard let m = opcaoRx.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { continue }
      let n = Int(ns.substring(with: m.range(at: 2))) ?? 0
      let sel = m.range(at: 1).location != NSNotFound
      var rotulo = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
      rotulo = rotulo.replacingOccurrences(of: #"\s{2,}.*$"#, with: "", options: .regularExpression)   // dica à direita
      opcoes.append((i, Permissao.Opcao(id: n, rotulo: rotulo, selecionada: sel)))
    }
    // Precisa ser um bloco 1, 2, 3… contínuo, e o último bloco da tela.
    guard let ultimoUm = opcoes.lastIndex(where: { $0.1.id == 1 }) else { return nil }
    var bloco = [opcoes[ultimoUm]]
    var k = ultimoUm + 1
    while k < opcoes.count, opcoes[k].1.id == bloco.last!.1.id + 1, opcoes[k].0 - bloco.last!.0 <= 2 { bloco.append(opcoes[k]); k += 1 }
    guard bloco.count >= 2, let fim = bloco.last?.0, janela.count - fim <= 8 else { return nil }
    // A pergunta: a linha com "?" mais próxima acima da primeira opção (até 6 linhas).
    let inicio = bloco[0].0
    var q: Int?
    var j = inicio - 1
    while j >= 0 && inicio - j <= 6 {
      if janela[j].contains("?") { q = j; break }
      j -= 1
    }
    guard let qi = q else { return nil }
    // Detalhe: o que vem logo acima da pergunta (o comando, o arquivo), até 6 linhas.
    var det: [String] = []
    var d = qi - 1
    while d >= 0 && det.count < 6 {
      let l = janela[d]
      if l.isEmpty { if !det.isEmpty { break } } else { det.insert(l, at: 0) }
      d -= 1
    }
    return Permissao(pergunta: janela[qi], detalhe: det.joined(separator: "\n"), opcoes: bloco.map(\.1))
  }
}

extension Painel {
  /// Relê a tela e atualiza o pedido de permissão (só com o agente parado).
  func lerPermissao() {
    guard tipoAgente != nil, !ocupado, let v = view, let snap = v.terminalContentSnapshot(region: .viewport) else {
      if permissao != nil { permissao = nil }
      return
    }
    var nova = DetectorPermissao.ler(snap.rows.map(\.text))
    if nova != nil && nova == permissaoRespondida { nova = nil }     // a mesma pergunta que já foi respondida
    if nova != permissao { permissao = nova }
  }

  /// Escolhe uma opção do pedido de permissão (manda o número para o agente).
  func responderPermissao(_ o: Permissao.Opcao) {
    permissaoRespondida = permissao
    permissao = nil
    escrever(o.tecla)
  }
}

/// Cartão do pedido de permissão: o que o agente quer fazer e as opções como botões. Cartão
/// neutro; o âmbar fica só no chip "pede permissão" (o que espera você é uma peça pequena).
struct CartaoPermissao: View {
  let painel: Painel
  let permissao: Permissao
  var compacto = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        ChipRotulo(simbolo: "hand.raised.fill", texto: "\(painel.persona?.nome ?? "O agente") pede permissão", cor: Cor.ambar)
        Text(permissao.pergunta).font(F.ui(12.5, .semibold)).foregroundStyle(Cor.texto).lineLimit(2)
        Spacer(minLength: 0)
      }
      if !permissao.detalhe.isEmpty && !compacto {
        Text(permissao.detalhe).font(F.mono(11.5)).foregroundStyle(Cor.texto).lineLimit(6).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 10).padding(.vertical, 8)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Cor.vidro))
      }
      FlowBotoes(opcoes: permissao.opcoes) { painel.responderPermissao($0) }
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Cor.elevado))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Cor.linhaForte))
  }
}

private struct FlowBotoes: View {
  let opcoes: [Permissao.Opcao]
  let escolher: (Permissao.Opcao) -> Void
  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
      ForEach(opcoes) { o in
        let principal = o.id == 1 && !o.negativa
        Button { escolher(o) } label: {
          HStack(spacing: 7) {
            Text("\(o.id)").font(F.ui(10.5, .bold)).monospacedDigit()
              .frame(width: 16, height: 16)
              .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(principal ? Cor.sobreTinta.opacity(0.18) : Cor.vidro2))
            Text(o.rotulo).font(F.ui(12, .medium)).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
          }
          .foregroundStyle(principal ? Cor.sobreTinta : Cor.texto)
          .padding(.horizontal, 9).padding(.vertical, 7)
          .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(principal ? Cor.texto : Cor.vidro))
          .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(principal ? SwiftUI.Color.clear : Cor.linhaForte))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Responde \(o.id) no terminal (ou tecle \(o.id) nele)")
      }
    }
  }
}
