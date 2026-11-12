import SwiftUI
import AppKit
import QuickLookThumbnailing

// Prévia de anexos (compose e vista de conversa): miniatura pequena para o cartão e uma prévia
// grande no popover. Imagens são lidas reduzidas (ImageIO); outros arquivos usam a miniatura do
// Quick Look, com o ícone do Finder enquanto ela não chega. Texto curto mostra as primeiras linhas.

enum Arquivos {
  /// Cache pequeno de miniaturas (caminho + lado), para não reler a cada redesenho.
  @MainActor private static var cache: [String: NSImage] = [:]

  @MainActor static func emCache(_ caminho: String, lado: Int) -> NSImage? { cache["\(lado):\(caminho)"] }

  @MainActor static func guardar(_ img: NSImage, _ caminho: String, lado: Int) {
    if cache.count > 120 { cache.removeAll() }
    cache["\(lado):\(caminho)"] = img
  }

  static func ehPasta(_ caminho: String) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: caminho, isDirectory: &d) && d.boolValue
  }

  /// "PNG · 240 KB", "Pasta", "Swift · 3 KB".
  static func descricao(_ caminho: String) -> String {
    let limpo = caminho.hasSuffix("/") ? String(caminho.dropLast()) : caminho
    if ehPasta(limpo) { return "Pasta" }
    let ext = (limpo as NSString).pathExtension.uppercased()
    let tam = (try? FileManager.default.attributesOfItem(atPath: limpo)[.size] as? Int) ?? nil
    let bytes = tam.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    if !FileManager.default.fileExists(atPath: limpo) { return "não encontrado" }
    return [ext.isEmpty ? "Arquivo" : ext, bytes].compactMap { $0 }.joined(separator: " · ")
  }

  static let extensoesDeTexto: Set<String> = ["txt", "md", "markdown", "json", "yaml", "yml", "toml", "swift", "js", "ts", "tsx", "jsx",
                                              "py", "rb", "go", "rs", "c", "h", "cpp", "m", "java", "kt", "sh", "zsh", "css", "scss",
                                              "html", "htm", "xml", "csv", "log", "env", "sql", "ini", "conf"]

  /// Primeiras linhas de um arquivo de texto (no máximo ~16 KB lidos).
  static func inicioDoTexto(_ caminho: String, linhas: Int = 40) -> String? {
    guard extensoesDeTexto.contains((caminho as NSString).pathExtension.lowercased()),
          let h = FileHandle(forReadingAtPath: caminho) else { return nil }
    defer { try? h.close() }
    let dados = h.readData(ofLength: 16_384)
    guard let s = String(data: dados, encoding: .utf8) ?? String(data: dados, encoding: .isoLatin1) else { return nil }
    return s.split(separator: "\n", omittingEmptySubsequences: false).prefix(linhas).joined(separator: "\n")
  }
}

/// Miniatura de um arquivo: imagem reduzida, Quick Look, ou o ícone do Finder.
struct MiniaturaArquivo: View {
  let caminho: String
  var lado: CGFloat = 48
  @Estado private var imagem: NSImage?

  private var limpo: String { caminho.hasSuffix("/") ? String(caminho.dropLast()) : caminho }
  private var ehImagem: Bool { Compose.ehImagem(limpo) }

  var body: some View {
    Group {
      if let imagem {
        Image(nsImage: imagem).resizable().aspectRatio(contentMode: ehImagem ? .fill : .fit)
      } else {
        Image(nsImage: NSWorkspace.shared.icon(forFile: limpo)).resizable().aspectRatio(contentMode: .fit)
      }
    }
    .frame(width: lado, height: lado)
    .clipped()
    .task(id: caminho) { await carregar() }
  }

  @MainActor private func carregar() async {
    let px = Int(lado * 2)
    if let c = Arquivos.emCache(limpo, lado: px) { imagem = c; return }
    if ehImagem {
      if let img = Compose.miniatura(limpo, lado: px) { imagem = img; Arquivos.guardar(img, limpo, lado: px) }
      return
    }
    if Arquivos.ehPasta(limpo) { return }
    let pedido = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: limpo), size: CGSize(width: lado, height: lado),
                                              scale: 2, representationTypes: .thumbnail)
    if let r = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: pedido) {
      imagem = r.nsImage
      Arquivos.guardar(r.nsImage, limpo, lado: px)
    }
  }
}

/// Prévia grande no popover: imagem, primeiras linhas de um texto, ou a miniatura do Quick Look.
struct PreviaArquivo: View {
  let caminho: String
  var aoRemover: (() -> Void)? = nil
  @Estado private var grande: NSImage?

  private var limpo: String { caminho.hasSuffix("/") ? String(caminho.dropLast()) : caminho }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: limpo)).resizable().frame(width: 18, height: 18)
        VStack(alignment: .leading, spacing: 1) {
          Text((limpo as NSString).lastPathComponent).font(F.ui(12.5, .semibold)).foregroundStyle(Cor.texto).lineLimit(1).truncationMode(.middle)
          Text("\(Arquivos.descricao(limpo)) · \(Loja.encurtar((limpo as NSString).deletingLastPathComponent))")
            .font(F.ui(10.5)).foregroundStyle(Cor.texto3).lineLimit(1).truncationMode(.head)
        }
        Spacer(minLength: 0)
      }
      conteudo
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Cor.vidro))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      HStack(spacing: 6) {
        BotaoDialogo(titulo: "Abrir", compacto: true) { NSWorkspace.shared.open(URL(fileURLWithPath: limpo)) }
        BotaoDialogo(titulo: "Finder", compacto: true) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: limpo)]) }
        BotaoDialogo(titulo: "Copiar caminho", compacto: true) { MenuTerminal.copiar(limpo) }
        Spacer(minLength: 0)
        if let aoRemover { BotaoDialogo(titulo: "Remover", destrutivo: true, compacto: true, acao: aoRemover) }
      }
    }
    .padding(12)
    .frame(width: 420)
    .task(id: caminho) { await carregar() }
  }

  @ViewBuilder private var conteudo: some View {
    if let grande {
      Image(nsImage: grande).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 320)
    } else if let texto = Arquivos.inicioDoTexto(limpo) {
      ScrollView {
        Text(texto).font(F.mono(11)).foregroundStyle(Cor.texto2).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading).padding(10)
      }
      .frame(height: 260)
    } else {
      Image(nsImage: NSWorkspace.shared.icon(forFile: limpo)).resizable().frame(width: 96, height: 96).padding(30)
    }
  }

  @MainActor private func carregar() async {
    if Compose.ehImagem(limpo) { grande = Compose.miniatura(limpo, lado: 900); return }
    if Arquivos.inicioDoTexto(limpo) != nil || Arquivos.ehPasta(limpo) { return }
    let pedido = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: limpo), size: CGSize(width: 400, height: 320),
                                              scale: 2, representationTypes: .thumbnail)
    if let r = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: pedido) { grande = r.nsImage }
  }
}
