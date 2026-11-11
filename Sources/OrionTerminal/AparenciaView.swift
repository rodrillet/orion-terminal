import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Temas: a grade de escolha e o editor de um tema do usuário (usados em Ajustes → Aparência).

struct GradeTemas: View {
  @Bindable var loja: Loja
  let temas: [Tema]
  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
      ForEach(temas) { t in CartaoTema(loja: loja, tema: t) }
    }
    .padding(.vertical, 4)
  }
}

struct CartaoTema: View {
  @Bindable var loja: Loja
  let tema: Tema
  @Estado private var sobre = false

  var body: some View {
    let t = tema
    let emUso = loja.tema.id == t.id
    let doModo = (t.claro ? loja.ajustes.temaClaro : loja.ajustes.temaEscuro) == t.id
    VStack(alignment: .leading, spacing: 6) {
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.janelaUI)
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.fundoUI).padding(5)
          .shadow(color: .black.opacity(t.claro ? 0.12 : 0.4), radius: 3, y: 1)
        VStack(alignment: .leading, spacing: 8) {
          (Text("❯ ").foregroundColor(Color(hex: t.ansi[2])) + Text("git ").foregroundColor(Color(hex: t.ansi[4])) + Text("status").foregroundColor(Color(hex: t.texto)))
            .font(.system(size: 11.5, design: .monospaced))
          HStack(spacing: 3) { ForEach(1..<7) { i in RoundedRectangle(cornerRadius: 2).fill(Color(hex: t.ansi[i])).frame(width: 11, height: 11) } }
        }.padding(13)
      }
      .frame(height: 74)
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(emUso ? Color(hex: t.acento) : (doModo ? Cor.texto3 : Cor.linhaForte), lineWidth: emUso ? 2 : 1))
      .overlay(alignment: .topTrailing) {
        if sobre {
          HStack(spacing: 3) {
            if !t.embutido { miniBotao("pencil", "Editar") { loja.escolherTema(t); loja.temaEmEdicao = t.id } }
            miniBotao("plus.square.on.square", "Duplicar para editar") { let n = Tema.duplicar(t); loja.versaoTemas += 1; loja.escolherTema(n); loja.temaEmEdicao = n.id }
          }.padding(6)
        }
      }
      HStack(spacing: 4) {
        Text(t.nome).font(F.ui(12, emUso ? .semibold : .regular)).foregroundStyle(emUso ? Cor.texto : Cor.texto2).lineLimit(1)
        if doModo && !emUso { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Cor.texto3).help(t.claro ? "É o tema do modo claro" : "É o tema do modo escuro") }
        if !t.embutido { Image(systemName: "person.fill").font(.system(size: 8)).foregroundStyle(Cor.texto4).help("Tema seu") }
      }
    }
    .contentShape(Rectangle())
    .onHover { sobre = $0 }
    .onTapGesture { loja.escolherTema(t); if loja.temaEmEdicao != nil { loja.temaEmEdicao = t.embutido ? nil : t.id } }
    .help("Usar o tema \(t.nome) (\(t.claro ? "claro" : "escuro"))")
  }

  func miniBotao(_ simbolo: String, _ dica: String, _ acao: @escaping () -> Void) -> some View {
    Button(action: acao) {
      Image(systemName: simbolo).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.55)))
    }.buttonStyle(.plain).help(dica)
  }
}

/// Editor de um tema do usuário: nome, claro/escuro, fundo, texto, destaque, as 16 cores ANSI e
/// a opacidade. Tudo vale na hora, em todos os terminais.
struct EditorTema: View {
  @Bindable var loja: Loja
  let tema: Tema
  static let nomesAnsi = ["Preto", "Vermelho", "Verde", "Amarelo", "Azul", "Magenta", "Ciano", "Branco"]

  /// Aplica uma mudança ao tema, grava e redesenha.
  func mudar(_ f: (inout Tema) -> Void) {
    var t = tema
    f(&t)
    guard t != tema else { return }
    Tema.atualizar(t)
    loja.versaoTemas += 1
    if t.claro != tema.claro { loja.escolherTema(t) } else { loja.aplicarAparencia() }
  }

  func cor(_ leitura: @escaping (Tema) -> String, _ escrita: @escaping (inout Tema, String) -> Void) -> Binding<Color> {
    Binding(get: { Color(hex: leitura(tema)) }, set: { nova in mudar { escrita(&$0, NSColor(nova).hex) } })
  }

  var body: some View {
    let t = tema
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        TextField("Nome", text: Binding(get: { t.nome }, set: { n in mudar { $0.nome = n } }))
          .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
        Picker("", selection: Binding(get: { t.claro }, set: { c in mudar { $0.claro = c } })) {
          Text("Escuro").tag(false); Text("Claro").tag(true)
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 150)
        Spacer()
        Button { exportar() } label: { Label("Exportar…", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { excluir() } label: { Image(systemName: "trash") }.help("Excluir este tema")
        Button("Concluir") { loja.temaEmEdicao = nil }.keyboardShortcut(.defaultAction)
      }
      .controlSize(.small)
      // Prévia
      VStack(alignment: .leading, spacing: 3) {
        (Text("~/projeto ").foregroundColor(Color(hex: t.ansi[4])) + Text("main ").foregroundColor(Color(hex: t.ansi[5])) + Text("❯ ").foregroundColor(Color(hex: t.ansi[2])) + Text("npm run build").foregroundColor(Color(hex: t.texto)))
        (Text("✓ ").foregroundColor(Color(hex: t.ansi[2])) + Text("compilado em 1,2 s  ").foregroundColor(Color(hex: t.texto)) + Text("2 avisos").foregroundColor(Color(hex: t.ansi[3])))
        (Text("✗ ").foregroundColor(Color(hex: t.ansi[1])) + Text("erro em ").foregroundColor(Color(hex: t.texto)) + Text("src/app.ts:42").foregroundColor(Color(hex: t.ansi[6])) + Text("  comentário").foregroundColor(Color(hex: t.ansi[8])))
        HStack(spacing: 0) { Text("seleção").padding(.horizontal, 3).background(Color(hex: t.acento).opacity(0.32)); Text(" ▏").foregroundColor(Color(hex: t.acento)) }
          .foregroundColor(Color(hex: t.texto))
      }
      .font(.system(size: 12, design: .monospaced))
      .padding(12).frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.fundoUI))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Cor.linhaForte))
      HStack(spacing: 18) {
        campoCor("Fundo", cor({ $0.fundo }, { $0.fundo = $1 }), t.fundo)
        campoCor("Texto", cor({ $0.texto }, { $0.texto = $1 }), t.texto)
        campoCor("Destaque", cor({ $0.acento }, { $0.acento = $1 }), t.acento)
        Spacer()
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Cores ANSI — normais em cima, brilhantes embaixo").font(F.ui(11)).foregroundStyle(.secondary)
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
          GridRow { ForEach(0..<8) { i in Text(EditorTema.nomesAnsi[i]).font(F.ui(10)).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
          ForEach(0..<2) { linha in
            GridRow {
              ForEach(0..<8) { i in
                let n = linha * 8 + i
                ColorPicker("", selection: cor({ $0.ansi[n] }, { $0.ansi[n] = $1 }), supportsOpacity: false)
                  .labelsHidden().frame(maxWidth: .infinity)
                  .help("\(EditorTema.nomesAnsi[i])\(linha == 1 ? " brilhante" : "") · \(t.ansi[n])")
              }
            }
          }
        }
      }
      HStack(spacing: 10) {
        Toggle("Opacidade própria", isOn: Binding(get: { t.opacidade != nil }, set: { liga in mudar { $0.opacidade = liga ? loja.ajustes.opacidade : nil } }))
        if let o = t.opacidade {
          Slider(value: Binding(get: { o }, set: { v in mudar { $0.opacidade = v } }), in: 0.2...1)
          Text("\(Int(o * 100))%").monospacedDigit().frame(width: 44)
        } else {
          Text("usa a dos ajustes (\(Int(loja.ajustes.opacidade * 100))%)").foregroundStyle(.secondary)
          Spacer()
        }
      }
      .font(F.ui(12))
    }
    .padding(.vertical, 4)
  }

  func campoCor(_ nome: String, _ b: Binding<Color>, _ hex: String) -> some View {
    HStack(spacing: 6) {
      ColorPicker("", selection: b, supportsOpacity: false).labelsHidden()
      VStack(alignment: .leading, spacing: 0) {
        Text(nome).font(F.ui(12))
        Text(hex).font(F.mono(10.5)).foregroundStyle(.secondary)
      }
    }
  }

  func exportar() {
    let p = NSSavePanel()
    p.allowedContentTypes = [.json]
    p.nameFieldStringValue = tema.nome + ".json"
    p.message = "O arquivo pode ser importado em outro Mac (Ajustes → Aparência → Importar tema)."
    guard p.runModal() == .OK, let u = p.url else { return }
    if !tema.exportar(para: u) { loja.avisar("Não consegui exportar", "Confira se dá para gravar nessa pasta.", simbolo: "exclamationmark.triangle.fill") }
  }

  func excluir() {
    let t = tema
    loja.confirmar("Excluir o tema “\(t.nome)”?", "Não dá para desfazer (exporte antes, se quiser guardar).", "Excluir", destrutivo: true) {
      Tema.remover(t.id)
      loja.temaEmEdicao = nil
      loja.versaoTemas += 1
      var a = loja.ajustes
      if a.temaEscuro == t.id { a.temaEscuro = "orion" }
      if a.temaClaro == t.id { a.temaClaro = "orion-claro" }
      if a == loja.ajustes { loja.aplicarAparencia() } else { loja.ajustes = a }
    }
  }
}
