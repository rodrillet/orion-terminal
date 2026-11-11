import SwiftUI
import AppKit

/// Seção "Sobre e atualizações" dos Ajustes.
struct SobreAtualizacoes: View {
  @Bindable var loja: Loja
  @Bindable var at = Atualizador.shared
  @Estado private var resultado: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 14) {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 60, height: 60)
        VStack(alignment: .leading, spacing: 3) {
          Text("Orion Terminal").font(F.ui(17, .semibold)).foregroundStyle(Cor.texto)
          Text("Versão \(at.atual)").font(F.mono(12)).foregroundStyle(Cor.texto2)
          Button("github.com/\(Atualizador.repositorio)") { NSWorkspace.shared.open(URL(string: "https://github.com/\(Atualizador.repositorio)")!) }
            .buttonStyle(.plain).font(F.ui(12)).foregroundStyle(Cor.acento).help("Abrir o repositório no navegador")
        }
        Spacer()
      }
      .padding(14)
      .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(Cor.elevado))
      .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linha))

      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: icone).font(.system(size: 14, weight: .semibold)).foregroundStyle(corEstado)
          Text(titulo).font(F.ui(13.5, .semibold)).foregroundStyle(Cor.texto)
          Spacer()
          if at.estado == .verificando || at.estado == .baixando { ProgressView().controlSize(.small) }
        }
        if let sub = subtitulo { Text(sub).font(F.ui(12)).foregroundStyle(Cor.texto2).fixedSize(horizontal: false, vertical: true) }
        if let v = at.disponivel, !v.notas.isEmpty {
          ScrollView {
            Text(v.notas).font(F.ui(12)).foregroundStyle(Cor.texto2).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
          }
          .frame(maxHeight: 140)
          .padding(10)
          .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.vidro))
        }
        HStack(spacing: 8) {
          if at.disponivel != nil {
            BotaoAjuste(titulo: "Reiniciar e atualizar", simbolo: "arrow.triangle.2.circlepath") { at.instalarAgora() }
              .help("Baixa (se ainda não baixou), confere e reabre já na versão nova")
            BotaoAjuste(titulo: "Ver no GitHub", simbolo: "safari") { if let p = at.disponivel?.pagina { NSWorkspace.shared.open(p) } }
          }
          BotaoAjuste(titulo: "Verificar agora", simbolo: "arrow.clockwise") {
            resultado = nil
            at.verificar { v, erro in
              resultado = erro.map { "Não deu para verificar: \($0)." } ?? (v == nil ? "Você já está na versão mais nova." : nil)
            }
          }
          .disabled(at.estado == .verificando || at.estado == .baixando)
          Spacer()
          if let u = at.ultimaVerificacao {
            Text("verificado \(u.formatted(.relative(presentation: .named)))").font(F.ui(11)).foregroundStyle(Cor.texto3)
          }
        }
        if let r = resultado { Text(r).font(F.ui(11.5)).foregroundStyle(Cor.texto3) }
      }
      .padding(14)
      .background(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).fill(Cor.elevado))
      .overlay(RoundedRectangle(cornerRadius: R.cartao, style: .continuous).strokeBorder(Cor.linha))

      VStack(alignment: .leading, spacing: 8) {
        Text("ATUALIZAÇÕES").font(F.ui(10.5, .semibold)).kerning(0.5).foregroundStyle(Cor.texto3)
        Escolha(valor: $loja.ajustes.atualizacao, opcoes: [
          ("automatica", "Automáticas", "sparkles"), ("avisar", "Só avisar", "bell"), ("desligada", "Desligadas", "slash.circle"),
        ])
        Text(explicacao).font(F.ui(11.5)).foregroundStyle(Cor.texto3).fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 8) {
        BotaoAjuste(titulo: "Licenças de terceiros", simbolo: "doc.text") {
          if let u = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") { NSWorkspace.shared.open(u) }
          else { NSWorkspace.shared.open(URL(string: "https://github.com/\(Atualizador.repositorio)/blob/main/THIRD_PARTY_NOTICES.md")!) }
        }
        .help("Bibliotecas usadas pelo app, cada uma com a sua licença, e créditos das paletas de cor")
        BotaoAjuste(titulo: "Notas de todas as versões", simbolo: "list.bullet.rectangle") {
          NSWorkspace.shared.open(URL(string: "https://github.com/\(Atualizador.repositorio)/releases")!)
        }
      }
    }
  }

  private var explicacao: String {
    switch loja.ajustes.atualizacao {
    case "automatica": return "Verifica ao abrir, ao voltar para o app e a cada hora. Versão nova é baixada e conferida em segundo plano e entra quando você fechar o app — sem interromper nada."
    case "avisar": return "Verifica do mesmo jeito, mas só avisa. Você decide quando instalar."
    default: return "Não consulta o GitHub. Use “Verificar agora” quando quiser."
    }
  }

  private var icone: String {
    switch at.estado {
    case .pronto: return "checkmark.seal.fill"
    case .erro: return "exclamationmark.triangle.fill"
    default: return at.disponivel != nil ? "arrow.down.circle.fill" : "checkmark.circle.fill"
    }
  }

  private var corEstado: Color {
    if case .erro = at.estado { return Cor.amarelo }
    return at.disponivel != nil ? Cor.acento : Cor.verde
  }

  private var titulo: String {
    switch at.estado {
    case .verificando: return "Procurando atualizações…"
    case .baixando: return "Baixando a versão \(at.disponivel?.numero ?? "")…"
    case .pronto: return "Versão \(at.disponivel?.numero ?? "") pronta"
    default: return at.disponivel.map { "Versão \($0.numero) disponível" } ?? "Você está na versão mais nova"
    }
  }

  private var subtitulo: String? {
    switch at.estado {
    case .pronto: return "Entra sozinha quando você fechar o app. Ou reinicie agora."
    case .erro(let m): return "Última tentativa: \(m)."
    default: return nil
    }
  }
}

/// Botão no topo quando há versão nova.
struct BotaoAtualizacao: View {
  @Bindable var at = Atualizador.shared
  @Estado private var sobre = false

  var body: some View {
    if let v = at.disponivel {
      Button { (NSApp.delegate as? Delegado)?.abrirAjustes(aba: "sobre") } label: {
        HStack(spacing: 5) {
          Image(systemName: at.estado == .pronto ? "checkmark.seal.fill" : "arrow.down.circle.fill").font(.system(size: 11.5, weight: .semibold))
          Text(at.estado == .pronto ? "Atualizar" : "\(v.numero)").font(F.ui(12, .semibold)).lineLimit(1)
        }
        .foregroundStyle(Cor.sobreAcento)
        .padding(.horizontal, 10).frame(height: F.m(26))
        .background(Capsule().fill(Cor.acento.opacity(sobre ? 1 : 0.88)))
      }
      .buttonStyle(.plain)
      .onHover { sobre = $0 }
      .help(at.estado == .pronto
            ? "Orion Terminal \(v.numero) baixado e conferido — entra quando você fechar o app. Clique para ver as novidades ou reiniciar agora."
            : "Orion Terminal \(v.numero) disponível — clique para ver as novidades")
      .transition(.scale.combined(with: .opacity))
    }
  }
}
