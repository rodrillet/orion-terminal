import Cocoa
import SwiftUI

/// Ícones reais: o ícone do app instalado (Claude.app, ChatGPT.app, VS Code…) para o programa
/// que está rodando na aba. Sem app correspondente, um SF Symbol do sistema.
enum Icones {
  private static var cache: [String: NSImage] = [:]

  /// programa → apps candidatos (bundle id), na ordem de preferência.
  private static let apps: [String: [String]] = [
    "claude": ["com.anthropic.claudefordesktop", "com.anthropic.claude"],
    "codex": ["com.openai.codex", "com.openai.chat"],
    "gemini": ["com.google.GeminiMacOS", "com.google.Gemini", "com.google.gemini.macos"],
    "code": ["com.microsoft.VSCode"],
    "cursor": ["com.todesktop.230313mzl4w4u92"],
    "docker": ["com.docker.docker"],
    "shell": ["com.apple.Terminal"],
    "ssh": ["com.apple.Terminal"],
    "python": ["org.python.IDLE"],
    "safari": ["com.apple.Safari"],
    "chrome": ["com.google.Chrome"],
    "git": ["com.github.GitHubClient"],
    "gh": ["com.github.GitHubClient"],
    "vim": ["org.vim.MacVim"], "nvim": ["org.vim.MacVim"],
    "warp": ["dev.warp.Warp-Stable"],
  ]

  private static let simbolos: [String: String] = [
    "git": "arrow.triangle.branch", "gh": "arrow.triangle.branch", "lazygit": "arrow.triangle.branch",
    "node": "hexagon", "npm": "shippingbox", "pnpm": "shippingbox", "yarn": "shippingbox", "bun": "shippingbox", "npx": "shippingbox",
    "vite": "bolt", "next": "bolt", "deno": "bolt",
    "python": "chevron.left.forwardslash.chevron.right", "python3": "chevron.left.forwardslash.chevron.right", "uv": "chevron.left.forwardslash.chevron.right",
    "ssh": "network", "mosh": "network", "curl": "arrow.down.circle", "wget": "arrow.down.circle",
    "vim": "pencil.line", "nvim": "pencil.line", "nano": "pencil.line", "hx": "pencil.line",
    "top": "gauge.with.dots.needle.33percent", "htop": "gauge.with.dots.needle.33percent", "btop": "gauge.with.dots.needle.33percent",
    "brew": "mug", "make": "hammer", "cargo": "hammer", "swift": "swift", "go": "hammer",
    "psql": "cylinder", "redis-cli": "cylinder", "sqlite3": "cylinder", "docker": "shippingbox.circle",
    "less": "doc.text", "man": "book", "bat": "doc.text", "tail": "doc.text",
  ]

  /// Normaliza o nome do processo para a chave do ícone.
  static func chave(_ processo: String) -> String {
    let p = processo.lowercased()
    if ["zsh", "bash", "fish", "sh", "login", "-zsh"].contains(p) || p.isEmpty { return "shell" }
    if p.hasPrefix("python") { return "python" }
    if p == "docker-compose" { return "docker" }
    return p
  }

  static func app(_ processo: String) -> NSImage? {
    let k = chave(processo)
    if let i = cache[k] { return i }
    for id in apps[k] ?? [] {
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
        let img = reduzir(NSWorkspace.shared.icon(forFile: url.path))
        cache[k] = img
        return img
      }
    }
    return nil
  }

  /// Guarda só uma versão pequena do ícone (o maior desenho na interface tem ~56 pt): o ícone
  /// inteiro de um app carrega todas as resoluções, vários MB cada.
  private static func reduzir(_ img: NSImage, lado: CGFloat = 128) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(lado), pixelsHigh: Int(lado), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    guard let rep, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return img }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: lado, height: lado), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let pequeno = NSImage(size: NSSize(width: lado / 2, height: lado / 2))
    pequeno.addRepresentation(rep)
    return pequeno
  }

  static func simbolo(_ processo: String) -> String {
    simbolos[chave(processo)] ?? "terminal"
  }
}

/// Ícone de um programa: imagem do app real ou símbolo do sistema.
struct IconePrograma: View {
  let processo: String
  var tamanho: CGFloat = 18

  var body: some View {
    if let img = Icones.app(processo) {
      Image(nsImage: img)
        .resizable()
        .interpolation(.high)
        .frame(width: tamanho, height: tamanho)
    } else if let f = Ferramenta.de(Icones.chave(processo)) {
      // Ferramenta sem app instalado para emprestar o ícone (ex.: Gemini CLI): a marca dela, simples.
      Image(systemName: f.simbolo)
        .font(.system(size: tamanho * 0.5, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: tamanho * 0.86, height: tamanho * 0.86)
        .background(RoundedRectangle(cornerRadius: tamanho * 0.22, style: .continuous).fill(Color(hex: f.cor)))
        .frame(width: tamanho, height: tamanho)
    } else {
      Image(systemName: Icones.simbolo(processo))
        .font(.system(size: tamanho * 0.62, weight: .medium))
        .foregroundStyle(Cor.texto2)
        .frame(width: tamanho, height: tamanho)
        .background(RoundedRectangle(cornerRadius: tamanho * 0.24).fill(Cor.vidro2))
    }
  }
}
