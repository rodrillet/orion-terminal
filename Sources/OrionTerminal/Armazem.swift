import Cocoa

/// Arquivos do app em ~/Library/Application Support/Orion Terminal e as consultas que a
/// interface faz ao disco (histórico do shell, pastas, branches, scripts do package.json).
enum Armazem {
  /// Cópia de desenvolvimento: pasta de dados própria (ORION_DADOS).
  static let desenvolvimento = !(ProcessInfo.processInfo.environment["ORION_DADOS"] ?? "").isEmpty
  /// ORION_SEM_FOCO=1: a janela abre atrás das outras e o app nunca rouba o foco (testes automáticos).
  static let semFoco = ProcessInfo.processInfo.environment["ORION_SEM_FOCO"] == "1"
  static let pasta: URL = {
    // ORION_DADOS troca a pasta de dados (estado, ajustes, socket): serve para rodar uma cópia de
    // desenvolvimento ao lado da instalada sem que uma mexa na outra.
    let u: URL
    if let alt = ProcessInfo.processInfo.environment["ORION_DADOS"], !alt.isEmpty {
      u = URL(fileURLWithPath: (alt as NSString).expandingTildeInPath, isDirectory: true)
    } else {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      u = base.appendingPathComponent("Orion Terminal", isDirectory: true)
    }
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }()
  static var pastaZsh: URL { pasta.appendingPathComponent("shell/zsh", isDirectory: true) }
  static var pastaPerfis: URL { pasta.appendingPathComponent("perfis", isDirectory: true) }

  static func ler(_ nome: String) -> Any? {
    guard let d = try? Data(contentsOf: pasta.appendingPathComponent(nome)) else { return nil }
    return try? JSONSerialization.jsonObject(with: d)
  }

  static func gravar(_ nome: String, _ obj: Any) {
    guard JSONSerialization.isValidJSONObject(obj),
          let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? d.write(to: pasta.appendingPathComponent(nome), options: .atomic)
  }

  // MARK: - Histórico do zsh

  /// Últimos comandos do ~/.zsh_history (mais recente primeiro, sem repetidos).
  /// O zsh "metafica" bytes ≥ 0x80: 0x83 seguido do byte XOR 0x20.
  static func historico(limite: Int = 4000) -> [String] {
    let env = ProcessInfo.processInfo.environment
    var caminhos = [env["HISTFILE"], NSHomeDirectory() + "/.zsh_history", NSHomeDirectory() + "/.bash_history"].compactMap { $0 }
    caminhos = caminhos.filter { FileManager.default.fileExists(atPath: $0) }
    guard let caminho = caminhos.first, let bruto = FileManager.default.contents(atPath: caminho) else { return [] }
    var bytes = [UInt8](); bytes.reserveCapacity(bruto.count)
    var meta = false
    for b in bruto {
      if meta { bytes.append(b ^ 0x20); meta = false } else if b == 0x83 { meta = true } else { bytes.append(b) }
    }
    let texto = String(decoding: bytes, as: UTF8.self)
    var comandos: [String] = []
    var atual = ""
    for linha in texto.split(separator: "\n", omittingEmptySubsequences: false) {
      var l = String(linha)
      if atual.isEmpty, l.hasPrefix(": "), let i = l.firstIndex(of: ";") { l = String(l[l.index(after: i)...]) }
      if l.hasSuffix("\\") { atual += l.dropLast() + "\n"; continue }
      atual += l
      let c = atual.trimmingCharacters(in: .whitespaces)
      if !c.isEmpty { comandos.append(c) }
      atual = ""
    }
    var vistos = Set<String>()
    var saida: [String] = []
    for c in comandos.reversed() where c.count < 500 {
      if vistos.insert(c).inserted { saida.append(c) }
      if saida.count >= limite { break }
    }
    return saida
  }

  // MARK: - Consultas para o autocomplete

  static func listarPasta(_ caminho: String, base: String) -> [[String: Any]] {
    var p = (caminho as NSString).expandingTildeInPath
    if !p.hasPrefix("/") { p = ((base as NSString).expandingTildeInPath as NSString).appendingPathComponent(p) }
    guard let itens = try? FileManager.default.contentsOfDirectory(atPath: p) else { return [] }
    var saida: [[String: Any]] = []
    for nome in itens.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }).prefix(400) {
      var ehDir: ObjCBool = false
      FileManager.default.fileExists(atPath: (p as NSString).appendingPathComponent(nome), isDirectory: &ehDir)
      saida.append(["nome": nome, "dir": ehDir.boolValue])
    }
    return saida
  }

  static func rodar(_ exe: String, _ args: [String], em cwd: String?, limite: TimeInterval = 2) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath) }
    let saida = Pipe()
    p.standardOutput = saida
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let prazo = DispatchTime.now() + limite
    DispatchQueue.global().asyncAfter(deadline: prazo) { if p.isRunning { p.terminate() } }
    let d = saida.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(data: d, encoding: .utf8)
  }

  static func branches(_ cwd: String) -> [String] {
    guard let s = rodar("/usr/bin/git", ["for-each-ref", "--sort=-committerdate", "--format=%(refname:short)", "refs/heads", "refs/remotes"], em: cwd) else { return [] }
    return s.split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/HEAD") }.prefix(200).map { $0 }
  }

  static func gitInfo(_ cwd: String) -> [String: Any] {
    guard let s = rodar("/usr/bin/git", ["status", "--porcelain=v1", "--branch"], em: cwd, limite: 1.5) else { return [:] }
    let linhas = s.split(separator: "\n")
    var branch = ""
    if let primeira = linhas.first, primeira.hasPrefix("## ") {
      branch = String(primeira.dropFirst(3)).components(separatedBy: "...").first ?? ""
      branch = branch.replacingOccurrences(of: "No commits yet on ", with: "")
    }
    return ["branch": branch, "alterados": max(0, linhas.count - 1)]
  }

  static func scriptsNpm(_ cwd: String) -> [String] {
    var dir = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath)
    for _ in 0..<6 {
      let pkg = dir.appendingPathComponent("package.json")
      if let d = try? Data(contentsOf: pkg),
         let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
         let s = j["scripts"] as? [String: Any] {
        return s.keys.sorted()
      }
      let pai = dir.deletingLastPathComponent()
      if pai.path == dir.path { break }
      dir = pai
    }
    return []
  }

  /// Famílias de fonte monoespaçadas instaladas. Olha só os traços que o sistema já tem
  /// catalogados — não instancia fonte nenhuma (carregar centenas de fontes custava ~15 MB).
  static func fontesMono() -> [String] {
    let fm = NSFontManager.shared
    let fixa = UInt(NSFontTraitMask.fixedPitchFontMask.rawValue)
    return fm.availableFontFamilies.filter { fam in
      if fam.hasPrefix(".") { return false }
      if fam.localizedCaseInsensitiveContains("mono") || fam.localizedCaseInsensitiveContains("code") { return true }
      guard let membro = fm.availableMembers(ofFontFamily: fam)?.first, membro.count > 3 else { return false }
      let tracos = (membro[3] as? NSNumber)?.uintValue ?? 0
      return tracos & fixa != 0
    }.sorted()
  }
}
