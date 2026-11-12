import Cocoa
import SwiftUI
import SwiftTerm
import Observation

/// Tema: paleta do terminal (16 cores ANSI) + as cores de base da interface. Um tema é claro
/// ou escuro; a interface inteira (texto, linhas, cartões) deriva disso.
struct Tema: Identifiable, Equatable, Codable {
  var id: String
  var nome: String
  var claro = false
  var fundo: String        // fundo dos terminais (a janela usa um tom derivado)
  var texto: String
  var acento: String
  var ansi: [String]
  /// Opacidade própria do tema (nil = a dos ajustes).
  var opacidade: Double?

  init(id: String, nome: String, claro: Bool = false, fundo: String, texto: String, acento: String, ansi: [String],
       opacidade: Double? = nil) {
    self.id = id; self.nome = nome; self.claro = claro; self.fundo = fundo; self.texto = texto
    self.acento = acento; self.ansi = ansi; self.opacidade = opacidade
  }

  enum Chaves: String, CodingKey { case id, nome, claro, fundo, texto, acento, ansi, opacidade }

  /// Leitura tolerante (arquivo importado ou editado à mão): o que faltar volta ao tema Orion.
  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: Chaves.self)
    let base = Tema.embutidos[0]
    id = (try? c.decode(String.self, forKey: .id)) ?? "tema-" + UUID().uuidString.prefix(8).lowercased()
    nome = (try? c.decode(String.self, forKey: .nome)) ?? "Tema"
    claro = (try? c.decode(Bool.self, forKey: .claro)) ?? false
    fundo = Tema.hexValido(try? c.decode(String.self, forKey: .fundo)) ?? base.fundo
    texto = Tema.hexValido(try? c.decode(String.self, forKey: .texto)) ?? base.texto
    acento = Tema.hexValido(try? c.decode(String.self, forKey: .acento)) ?? base.acento
    var cores = ((try? c.decode([String].self, forKey: .ansi)) ?? []).map { Tema.hexValido($0) ?? "#888888" }
    if cores.count < 16 { cores += base.ansi[cores.count...] }
    ansi = Array(cores.prefix(16))
    opacidade = (try? c.decodeIfPresent(Double.self, forKey: .opacidade)).flatMap { $0 }.map { min(1, max(0.2, $0)) }
  }

  func encode(to e: Encoder) throws {
    var c = e.container(keyedBy: Chaves.self)
    try c.encode(id, forKey: .id); try c.encode(nome, forKey: .nome); try c.encode(claro, forKey: .claro)
    try c.encode(fundo, forKey: .fundo); try c.encode(texto, forKey: .texto); try c.encode(acento, forKey: .acento)
    try c.encode(ansi, forKey: .ansi)
    try c.encodeIfPresent(opacidade, forKey: .opacidade)
  }

  static func hexValido(_ s: String?) -> String? {
    guard var h = s?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
    if !h.hasPrefix("#") { h = "#" + h }
    guard h.count == 7, h.dropFirst().allSatisfy({ $0.isHexDigit }) else { return nil }
    return h
  }

  var embutido: Bool { Tema.embutidos.contains { $0.id == id } }
  var corFundo: NSColor { NSColor(hex: fundo) }
  var corTexto: NSColor { NSColor(hex: texto) }
  var corAcento: NSColor { NSColor(hex: acento) }
  var acentoUI: SwiftUI.Color { SwiftUI.Color(nsColor: corAcento) }
  var fundoUI: SwiftUI.Color { SwiftUI.Color(nsColor: corFundo) }
  /// Fundo da janela (barras e trilho): um degrau atrás do fundo dos terminais, para os painéis
  /// parecerem cartões pousados sobre ela.
  var corJanela: NSColor { corFundo.blended(withFraction: claro ? 0.045 : 0.30, of: .black) ?? corFundo }
  var janelaUI: SwiftUI.Color { SwiftUI.Color(nsColor: corJanela) }

  var coresTerminal: [SwiftTerm.Color] {
    ansi.map { h in
      let c = NSColor(hex: h).usingColorSpace(.sRGB) ?? .white
      return SwiftTerm.Color(red: UInt16(c.redComponent * 65535), green: UInt16(c.greenComponent * 65535), blue: UInt16(c.blueComponent * 65535))
    }
  }

  // MARK: - Temas que vêm com o app

  static let embutidos: [Tema] = [
    Tema(id: "orion", nome: "Orion", fundo: "#0b0b10", texto: "#e8e8ee", acento: "#ff9e66",
         ansi: ["#1d1d24", "#ff6b6b", "#9ee37d", "#f5d76e", "#7aa2ff", "#c792ea", "#6fd6d6", "#c8c8d0",
                "#5c5c68", "#ff8a8a", "#b5f09a", "#ffe58f", "#9cbcff", "#dbb2ff", "#8ef0f0", "#ffffff"]),
    Tema(id: "hub", nome: "Orion Hub", fundo: "#1a1a1a", texto: "#f0f0f0", acento: "#42a0ff",
         ansi: ["#2c2c2c", "#ff6069", "#31cf76", "#ffb84d", "#42a0ff", "#b496f5", "#4fd1d9", "#dcdcdc",
                "#6b6b6b", "#ff8189", "#5fe096", "#ffcc7a", "#74b9ff", "#cbb5fa", "#7fe3ea", "#ffffff"]),
    Tema(id: "meianoite", nome: "Meia-noite", fundo: "#0e0f18", texto: "#c0caf5", acento: "#7aa2f7",
         ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"]),
    Tema(id: "mocha", nome: "Catppuccin Mocha", fundo: "#181825", texto: "#cdd6f4", acento: "#cba6f7",
         ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
                "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]),
    Tema(id: "dracula", nome: "Dracula", fundo: "#1e1f29", texto: "#f8f8f2", acento: "#bd93f9",
         ansi: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"]),
    Tema(id: "rosepine", nome: "Rosé Pine", fundo: "#161421", texto: "#e0def4", acento: "#ebbcba",
         ansi: ["#26233a", "#eb6f92", "#9ccfd8", "#f6c177", "#31748f", "#c4a7e7", "#ebbcba", "#e0def4",
                "#6e6a86", "#eb6f92", "#9ccfd8", "#f6c177", "#31748f", "#c4a7e7", "#ebbcba", "#e0def4"]),
    Tema(id: "grafite", nome: "Grafite", fundo: "#0f0f0f", texto: "#d6d6d6", acento: "#f0f0f0",
         ansi: ["#262626", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#d4d4d4",
                "#5a5a5a", "#ef8189", "#a9d48a", "#f0cf8f", "#7cc0f5", "#d48ff0", "#6fcbd6", "#ffffff"]),
    Tema(id: "nord", nome: "Nord", fundo: "#2e3440", texto: "#d8dee9", acento: "#88c0d0",
         ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]),
    Tema(id: "gruvbox", nome: "Gruvbox", fundo: "#282828", texto: "#ebdbb2", acento: "#fabd2f",
         ansi: ["#3c3836", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"]),
    Tema(id: "onedark", nome: "One Dark", fundo: "#21252b", texto: "#abb2bf", acento: "#61afef",
         ansi: ["#3f4451", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
                "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff"]),
    Tema(id: "solarized-escuro", nome: "Solarized Escuro", fundo: "#002b36", texto: "#a3b1b1", acento: "#2aa198",
         ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#586e75", "#cb4b16", "#98ad0c", "#c99c12", "#4a9fe0", "#6c71c4", "#3cb8ae", "#fdf6e3"]),
    // Claros
    Tema(id: "orion-claro", nome: "Orion Claro", claro: true, fundo: "#fcfcfd", texto: "#1c2026", acento: "#1f6fe5",
         ansi: ["#1c2026", "#c4313f", "#2b7d4f", "#9a6b00", "#1f6fe5", "#8a46c8", "#0f7f8f", "#6b7785",
                "#4a5561", "#d9485a", "#33935d", "#b07e09", "#3b82f6", "#a05fe0", "#1697a8", "#12161b"]),
    Tema(id: "papel", nome: "Papel", claro: true, fundo: "#f6f3ec", texto: "#2a2723", acento: "#c2562c",
         ansi: ["#2a2723", "#b3392b", "#55742a", "#96690b", "#2f6690", "#8a4a86", "#2f7a78", "#75706a",
                "#57524c", "#cf4a3a", "#678c34", "#ad7c14", "#3c7bab", "#a25d9e", "#3b9390", "#1c1a17"]),
    Tema(id: "latte", nome: "Catppuccin Latte", claro: true, fundo: "#eff1f5", texto: "#4c4f69", acento: "#8839ef",
         ansi: ["#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#7c7f93",
                "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#4c4f69"]),
    Tema(id: "github-claro", nome: "Nuvem", claro: true, fundo: "#ffffff", texto: "#24292f", acento: "#0969da",
         ansi: ["#24292f", "#cf222e", "#116329", "#7d4e00", "#0969da", "#8250df", "#1b7c83", "#6e7781",
                "#57606a", "#a40e26", "#1a7f37", "#9a6700", "#218bff", "#a475f9", "#3192aa", "#1f2328"]),
    Tema(id: "solarized-claro", nome: "Solarized Claro", claro: true, fundo: "#fdf6e3", texto: "#475b62", acento: "#268bd2",
         ansi: ["#073642", "#dc322f", "#6c7c00", "#a67c00", "#268bd2", "#d33682", "#1f8f87", "#7b8a8a",
                "#586e75", "#cb4b16", "#859900", "#b58900", "#4a9fe0", "#6c71c4", "#2aa198", "#002b36"]),
    Tema(id: "rosepine-dawn", nome: "Rosé Pine Dawn", claro: true, fundo: "#faf4ed", texto: "#575279", acento: "#b4637a",
         ansi: ["#575279", "#b4637a", "#286983", "#c77f1c", "#56949f", "#907aa9", "#d7827e", "#797593",
                "#6e6a86", "#b4637a", "#286983", "#ea9d34", "#56949f", "#907aa9", "#d7827e", "#3f3b5c"]),
  ]

  // MARK: - Temas do usuário (temas.json)

  nonisolated(unsafe) static var personalizados: [Tema] = carregarPersonalizados()
  static var todos: [Tema] { embutidos + personalizados }

  static func porId(_ id: String) -> Tema { todos.first { $0.id == id } ?? embutidos[0] }
  static func existe(_ id: String) -> Bool { todos.contains { $0.id == id } }

  private static func carregarPersonalizados() -> [Tema] {
    guard let d = try? Data(contentsOf: Armazem.pasta.appendingPathComponent("temas.json")),
          let lista = try? JSONDecoder().decode([Tema].self, from: d) else { return [] }
    var vistos = Set(embutidos.map(\.id))
    return lista.filter { vistos.insert($0.id).inserted }
  }

  static func salvarPersonalizados() {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let d = try? e.encode(personalizados) { try? d.write(to: Armazem.pasta.appendingPathComponent("temas.json"), options: .atomic) }
  }

  /// Cópia editável de um tema, com id e nome novos.
  static func duplicar(_ t: Tema) -> Tema {
    var novo = t
    novo.id = "tema-" + UUID().uuidString.prefix(8).lowercased()
    var nome = t.nome + " (cópia)"
    var n = 2
    while todos.contains(where: { $0.nome == nome }) { nome = "\(t.nome) (cópia \(n))"; n += 1 }
    novo.nome = nome
    personalizados.append(novo)
    salvarPersonalizados()
    return novo
  }

  /// Grava as mudanças de um tema do usuário (os embutidos não mudam).
  static func atualizar(_ t: Tema) {
    guard let i = personalizados.firstIndex(where: { $0.id == t.id }) else { return }
    personalizados[i] = t
    salvarPersonalizados()
  }

  static func remover(_ id: String) {
    personalizados.removeAll { $0.id == id }
    salvarPersonalizados()
  }

  /// Lê um tema de um arquivo .json exportado e o adiciona (id novo se já existir um igual).
  static func importar(_ url: URL) -> Tema? {
    guard let d = try? Data(contentsOf: url), var t = try? JSONDecoder().decode(Tema.self, from: d) else { return nil }
    if existe(t.id) { t.id = "tema-" + UUID().uuidString.prefix(8).lowercased() }
    if todos.contains(where: { $0.nome == t.nome }) { t.nome += " (importado)" }
    personalizados.append(t)
    salvarPersonalizados()
    return t
  }

  func exportar(para url: URL) -> Bool {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let d = try? e.encode(self) else { return false }
    return (try? d.write(to: url, options: .atomic)) != nil
  }

  /// Tema em uso (a Loja atualiza). Serve às peças da interface, que não recebem a Loja.
  nonisolated(unsafe) static var atual = embutidos[0]
}

/// O que muda a cara da interface inteira (tema, modo claro/escuro, tamanho da fonte, raio).
/// As cores e fontes abaixo leem `versao`, então toda view que usa `Cor` ou `F` se redesenha
/// sozinha quando algo disso muda — em qualquer janela, sem recriar a árvore.
@Observable final class Aparencia: @unchecked Sendable {
  static let atual = Aparencia()
  var versao = 0
  @ObservationIgnored var escala: CGFloat = 1
  @ObservationIgnored var raio: CGFloat = 14
  @ObservationIgnored var sombras = true
  @ObservationIgnored var mascote: CGFloat = 1.15
  @ObservationIgnored var animarMascotes = true
}

extension NSColor {
  convenience init(hex: String) {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    let r, g, b: CGFloat
    if s.count == 6 {
      r = CGFloat((v >> 16) & 0xff) / 255; g = CGFloat((v >> 8) & 0xff) / 255; b = CGFloat(v & 0xff) / 255
    } else { r = 1; g = 1; b = 1 }
    self.init(srgbRed: r, green: g, blue: b, alpha: 1)
  }

  var hex: String {
    let c = usingColorSpace(.sRGB) ?? .white
    return String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
  }

  /// Claridade percebida (0 = preto, 1 = branco).
  var luminancia: CGFloat {
    let c = usingColorSpace(.sRGB) ?? .white
    return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
  }
}

extension SwiftUI.Color {
  init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}

/// Cores da interface. Derivam do tema em uso: sobre tema escuro o texto é branco translúcido,
/// sobre tema claro é preto translúcido; as cores de estado têm uma versão para cada fundo.
enum Cor {
  private static var t: Tema { _ = Aparencia.atual.versao; return Tema.atual }
  static var claro: Bool { t.claro }
  private static func tinta(_ escuro: Double, _ claro: Double) -> SwiftUI.Color {
    t.claro ? SwiftUI.Color.black.opacity(claro) : SwiftUI.Color.white.opacity(escuro)
  }
  private static func par(_ escuro: String, _ claro: String) -> SwiftUI.Color { SwiftUI.Color(hex: t.claro ? claro : escuro) }

  /// Cor de destaque do tema (seleção, botões ativos).
  static var acento: SwiftUI.Color { t.acentoUI }
  /// Texto sobre um botão preenchido com o destaque.
  static var sobreAcento: SwiftUI.Color { t.corAcento.luminancia > 0.6 ? .black.opacity(0.85) : .white }
  static var texto: SwiftUI.Color { tinta(0.92, 0.88) }
  /// Texto sobre um botão preenchido com a tinta (`texto`): a ação principal é em tinta, não em cor.
  static var sobreTinta: SwiftUI.Color { t.claro ? .white : .black }
  static var texto2: SwiftUI.Color { tinta(0.64, 0.66) }
  static var texto3: SwiftUI.Color { tinta(0.42, 0.48) }
  static var texto4: SwiftUI.Color { tinta(0.26, 0.32) }
  static var linha: SwiftUI.Color { tinta(0.08, 0.10) }
  static var linhaForte: SwiftUI.Color { tinta(0.15, 0.17) }
  /// Preenchimento discreto (controles em repouso) e o do hover / selecionado.
  static var vidro: SwiftUI.Color { tinta(0.05, 0.045) }
  static var vidro2: SwiftUI.Color { tinta(0.10, 0.085) }
  /// Superfície elevada (cartões, itens selecionados): mais clara que o fundo nos dois modos.
  static var elevado: SwiftUI.Color { t.claro ? SwiftUI.Color.white.opacity(0.78) : SwiftUI.Color.white.opacity(0.065) }
  /// Fundo de painéis flutuantes (quadro, diálogos, cartão de uso), por cima do material.
  static var flutuante: SwiftUI.Color { t.claro ? SwiftUI.Color.white.opacity(0.55) : SwiftUI.Color.black.opacity(0.32) }
  /// Véu atrás de um painel flutuante.
  static var veu: SwiftUI.Color { SwiftUI.Color.black.opacity(t.claro ? 0.16 : 0.36) }
  static var sombra: SwiftUI.Color { SwiftUI.Color.black.opacity(t.claro ? 0.16 : 0.5) }
  static var verde: SwiftUI.Color { par("#8fdc6e", "#2f8f4e") }
  static var amarelo: SwiftUI.Color { par("#f5d76e", "#a67700") }
  static var ambar: SwiftUI.Color { par("#ffb454", "#c26a00") }      // "esperando você"
  static var vermelho: SwiftUI.Color { par("#ff6b6b", "#cf3a35") }
  static var azul: SwiftUI.Color { par("#7aa2ff", "#1f6fe5") }
  static var lilas: SwiftUI.Color { par("#b3b6ff", "#6b45b8") }
  static let paletaGrupos = ["#ff9e66", "#ff6b6b", "#f5d76e", "#9ee37d", "#6fd6d6", "#7aa2ff", "#b79cff", "#ff79c6", "#a0a0aa"]
}

/// Fontes da interface: a do sistema, no tamanho escolhido em Ajustes → Aparência (separado do
/// terminal). Mono só onde ajuda a ler — caminhos, ids, números alinhados.
enum F {
  static var escala: CGFloat { _ = Aparencia.atual.versao; return Aparencia.atual.escala }
  static func ui(_ tamanho: CGFloat, _ peso: Font.Weight = .regular) -> Font { .system(size: tamanho * escala, weight: peso) }
  static func mono(_ tamanho: CGFloat, _ peso: Font.Weight = .regular) -> Font { .system(size: tamanho * escala, weight: peso, design: .monospaced) }
  /// Medida que acompanha a fonte (altura de linha, ícone ao lado de texto).
  static func m(_ v: CGFloat) -> CGFloat { (v * escala).rounded() }
}

/// Raios de canto: um só ajuste ("arredondamento") dá o dos cartões e, em proporção, o dos controles.
enum R {
  static var cartao: CGFloat { _ = Aparencia.atual.versao; return Aparencia.atual.raio }
  static var controle: CGFloat { max(4, (cartao * 0.72).rounded()) }
  static var pequeno: CGFloat { max(3, (cartao * 0.5).rounded()) }
}

extension View {
  /// Cartão flutuante (quadro, diálogos, cartão de uso, paleta): material + véu do tema + borda + sombra.
  func cartaoFlutuante(raio: CGFloat? = nil) -> some View {
    let r = raio ?? R.cartao + 2
    return self
      .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(Cor.flutuante))
      .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(.regularMaterial))
      .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Cor.linhaForte))
      .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
      .shadow(color: Cor.sombra, radius: 28, y: 12)
  }
}

/// `@State` virou macro no SDK novo e o plugin dela só vem com o Xcode. O apelido usa o
/// property wrapper direto (funciona só com as Command Line Tools).
typealias Estado<Valor> = SwiftUI.State<Valor>
