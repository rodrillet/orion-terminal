import AppKit

// Print da janela, só na cópia de desenvolvimento (ORION_DADOS): escrever um caminho .png em
// `<ORION_DADOS>/print.pedir` faz o app salvar a própria janela nele. Serve para conferir a
// interface sem dar ao terminal a permissão de gravar a tela.

@MainActor
enum PrintDev {
  private static var timer: Timer?

  static func ligar() {
    guard Armazem.desenvolvimento, timer == nil else { return }
    let pedido = Armazem.pasta.appendingPathComponent("print.pedir")
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
      MainActor.assumeIsolated {
        guard let destino = try? String(contentsOf: pedido, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: pedido)
        let caminho = destino.trimmingCharacters(in: .whitespacesAndNewlines)
        if caminho.hasSuffix("galeria.png") { galeria(em: caminho) } else { salvar(em: caminho) }
      }
    }
  }

  /// Todas as formas × humores (e os acessórios) do mascote em pixel, sobre o fundo do tema.
  static func galeria(em caminho: String) {
    let lado: CGFloat = 48, passo: CGFloat = 96, escala: CGFloat = 2
    let humores: [(Humor, Bool)] = [(.normal, false), (.normal, true), (.focado, false), (.atento, false), (.dormindo, false)]
    let acessorios: [Acessorio] = [.coroa, .oculos, .antena, .fones, .lupa, .boina]
    let pessoas = Persona.elenco.prefix(8)
    let colunas = humores.count + acessorios.count
    let w = Int(CGFloat(colunas) * passo * escala), h = Int(CGFloat(pessoas.count) * passo * escala)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(Tema.atual.corFundo.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .none
    for (j, p) in pessoas.enumerated() {
      for c in 0..<colunas {
        let (humor, feliz) = c < humores.count ? humores[c] : (.normal, false)
        let ac = c < humores.count ? Acessorio.nenhum : acessorios[c - humores.count]
        guard let img = MascotePixel.imagem(forma: p.avatar, cor: p.cor, lado: lado, margem: lado * 0.45, humor: humor, acessorio: ac,
                                            feliz: feliz, parte: .tudo, escala: escala) else { continue }
        let x = CGFloat(c) * passo * escala + (passo * escala - CGFloat(img.width)) / 2
        let y = CGFloat(h) - CGFloat(j + 1) * passo * escala + (passo * escala - CGFloat(img.height)) / 2
        ctx.draw(img, in: CGRect(x: x, y: y, width: CGFloat(img.width), height: CGFloat(img.height)))
      }
    }
    guard let img = ctx.makeImage() else { return }
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: caminho))
  }

  static func salvar(em caminho: String) {
    guard let janela = NSApp.windows.first(where: { $0 is JanelaPrincipal }) ?? NSApp.mainWindow,
          let vista = janela.contentView else { return }
    let r = vista.bounds
    guard let rep = vista.bitmapImageRepForCachingDisplay(in: r) else { return }
    vista.cacheDisplay(in: r, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: caminho))
  }
}
