import Cocoa
import CryptoKit

/// Contas do Claude Code e do Codex. Cada conta é uma pasta de configuração própria:
/// `CLAUDE_CONFIG_DIR` para o Claude e `CODEX_HOME` para o Codex. Uma aba recebe a variável da
/// conta escolhida, então duas abas podem usar contas diferentes ao mesmo tempo.
/// A conta "Padrão" de cada ferramenta não define variável nenhuma (~/.claude e ~/.codex).
enum Contas {
  static let arquivo = "contas.json"

  static func todas() -> [[String: Any]] {
    var lista = (Armazem.ler(arquivo) as? [[String: Any]]) ?? []
    // A conta da instalação normal de cada ferramenta (~/.claude, ~/.codex, ~/.gemini) sempre existe.
    for (i, f) in Ferramenta.todas.enumerated() where !lista.contains(where: { $0["id"] as? String == f.contaPrincipal }) {
      let conta: [String: Any] = ["id": f.contaPrincipal, "tipo": f.id, "nome": "Padrão", "cor": f.cor]
      if i == 0 { lista.insert(conta, at: 0) } else { lista.append(conta) }
    }
    return lista
  }

  static func salvar(_ lista: [[String: Any]]) { Armazem.gravar(arquivo, lista) }

  static func conta(_ id: String) -> [String: Any]? { todas().first { $0["id"] as? String == id } }

  /// Variáveis de ambiente que uma aba recebe para usar estas contas (ferramenta → id da conta).
  static func ambiente(_ contas: [String: String]) -> [String: String] {
    var env: [String: String] = [:]
    for f in Ferramenta.todas {
      if let id = contas[f.id], let c = conta(id), let dir = c["dir"] as? String, !dir.isEmpty { env[f.variavel] = dir }
    }
    return env
  }

  static func criar(tipo: String, nome: String, cor: String, compartilhar: Bool) throws -> [String: Any] {
    var slug = nome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    if slug.isEmpty { slug = "conta" }
    var lista = todas()
    var id = "\(tipo)-\(slug)"
    var n = 2
    while lista.contains(where: { $0["id"] as? String == id }) { id = "\(tipo)-\(slug)-\(n)"; n += 1 }
    let dir = Armazem.pastaPerfis.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    if compartilhar, let f = Ferramenta.de(tipo) {
      let origem = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(f.pastaPadrao)
      // O Gemini usa a pasta do perfil como "pasta pessoal": a configuração fica em <perfil>/.gemini.
      var destino = dir
      if tipo == "gemini" {
        destino = dir.appendingPathComponent(".gemini", isDirectory: true)
        try? FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      }
      for item in f.compartilhados {
        let o = origem.appendingPathComponent(item)
        if FileManager.default.fileExists(atPath: o.path) {
          try? FileManager.default.createSymbolicLink(at: destino.appendingPathComponent(item), withDestinationURL: o)
        }
      }
    }
    let conta: [String: Any] = ["id": id, "tipo": tipo, "nome": nome, "cor": cor, "dir": dir.path, "compartilhar": compartilhar]
    lista.append(conta)
    salvar(lista)
    return conta
  }

  static func atualizar(id: String, campos: [String: Any]) {
    var lista = todas()
    guard let i = lista.firstIndex(where: { $0["id"] as? String == id }) else { return }
    for (k, v) in campos where ["nome", "cor"].contains(k) { lista[i][k] = v }
    salvar(lista)
  }

  /// Remove a conta da lista; a pasta vai para a Lixeira (recuperável).
  static func remover(id: String) {
    guard !id.hasSuffix("-padrao") else { return }
    var lista = todas()
    if let c = lista.first(where: { $0["id"] as? String == id }), let dir = c["dir"] as? String,
       dir.hasPrefix(Armazem.pastaPerfis.path) {
      try? FileManager.default.trashItem(at: URL(fileURLWithPath: dir), resultingItemURL: nil)
    }
    lista.removeAll { $0["id"] as? String == id }
    salvar(lista)
  }

  // MARK: - Quem está logado

  static func info(_ id: String) -> [String: Any] {
    guard let c = conta(id), let tipo = c["tipo"] as? String else { return [:] }
    let dir = c["dir"] as? String
    if tipo == "claude" {
      let arq = dir.map { $0 + "/.claude.json" } ?? (NSHomeDirectory() + "/.claude.json")
      guard let d = FileManager.default.contents(atPath: arq),
            let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
            let o = j["oauthAccount"] as? [String: Any] else { return ["logado": false] }
      return ["logado": true, "email": o["emailAddress"] ?? "", "nome": o["displayName"] ?? "",
              "organizacao": o["organizationName"] ?? "", "plano": o["billingType"] ?? ""]
    }
    if tipo == "gemini" {
      // O Gemini CLI anota a conta em uso em google_accounts.json (só o e-mail; as credenciais
      // ficam em outro arquivo, que não é lido).
      let arq = (dir ?? NSHomeDirectory()) + "/.gemini/google_accounts.json"
      guard let d = FileManager.default.contents(atPath: arq), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
            let email = j["active"] as? String, !email.isEmpty else { return ["logado": false] }
      return ["logado": true, "email": email, "plano": ""]
    }
    let home = dir ?? (ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex")
    guard let d = FileManager.default.contents(atPath: home + "/auth.json"),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return ["logado": false] }
    if let tokens = j["tokens"] as? [String: Any], let idt = tokens["id_token"] as? String,
       let payload = jwt(idt) {
      let auth = payload["https://api.openai.com/auth"] as? [String: Any]
      return ["logado": true, "email": payload["email"] ?? "", "plano": auth?["chatgpt_plan_type"] ?? ""]
    }
    if let k = j["OPENAI_API_KEY"] as? String, !k.isEmpty { return ["logado": true, "email": "chave de API", "plano": "api"] }
    return ["logado": false]
  }

  private static func jwt(_ t: String) -> [String: Any]? {
    let partes = t.split(separator: ".")
    guard partes.count >= 2 else { return nil }
    var b = String(partes[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while b.count % 4 != 0 { b += "=" }
    guard let d = Data(base64Encoded: b) else { return nil }
    return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
  }

  // MARK: - Uso (limites de 5 h e 7 dias)

  /// Nome do item no Chaveiro onde o Claude Code guarda o login desta pasta.
  static func servicoChaveiro(dir: String?) -> String {
    guard let dir, !dir.isEmpty else { return "Claude Code-credentials" }
    let norm = dir.precomposedStringWithCanonicalMapping
    let h = SHA256.hash(data: Data(norm.utf8)).map { String(format: "%02x", $0) }.joined()
    return "Claude Code-credentials-\(h.prefix(8))"
  }

  /// Teste: `ORION_USO_FALSO=1` nunca lê o Chaveiro nem a rede (os números vêm de `orion depurar uso`).
  static let usoFalso = ProcessInfo.processInfo.environment["ORION_USO_FALSO"] == "1"

  static func uso(_ id: String, forcar: Bool = false, concluir: @escaping ([String: Any]) -> Void) {
    guard let c = conta(id), let tipo = c["tipo"] as? String else { concluir(["erro": "conta não existe"]); return }
    let dir = c["dir"] as? String
    DispatchQueue.global(qos: .utility).async {
      if tipo == "gemini" {
        DispatchQueue.main.async { concluir(["erro": "o Gemini CLI não informa uso"]) }
        return
      }
      if tipo == "codex" {
        let home = dir ?? NSHomeDirectory() + "/.codex"
        let r = usoCodex(home)
        DispatchQueue.main.async { concluir(r) }
        return
      }
      func fim(_ r: [String: Any]) { DispatchQueue.main.async { concluir(r) } }
      guard let t = tokenClaude(id: id, dir: dir, forcar: forcar) else { fim(["erro": "sem login nesta conta"]); return }
      pedirUsoClaude(t.token) { status, r in
        guard status == 401 else { fim(r); return }
        // 401 com token do cache: o Claude Code pode ter renovado o login; lê o Chaveiro de novo, uma vez.
        esquecerToken(id)
        guard t.doCache, let novo = tokenClaude(id: id, dir: dir, forcar: true), novo.token != t.token else { fim(r); return }
        pedirUsoClaude(novo.token) { s2, r2 in
          if s2 == 401 { esquecerToken(id) }
          fim(r2)
        }
      }
    }
  }

  private static func pedirUsoClaude(_ token: String, _ fim: @escaping (Int, [String: Any]) -> Void) {
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.setValue("orion-terminal/\(Shell.versao)", forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 10
    URLSession.shared.dataTask(with: req) { d, resp, _ in
      var r: [String: Any] = [:]
      let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
      if status == 401 {
        r["erro"] = "login expirado — abra o Claude nesta conta para renovar"
      } else if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        for (chave, nome) in [("five_hour", "h5"), ("seven_day", "d7")] {
          if let w = j[chave] as? [String: Any], let u = (w["utilization"] as? Double) ?? (w["utilization"] as? Int).map(Double.init) {
            r[nome] = ["pct": u, "reinicia": w["resets_at"] ?? NSNull()]
          }
        }
        if r.isEmpty { r["erro"] = status == 429 ? "muitas consultas — tento de novo depois" : "resposta sem dados de uso" }
      } else {
        r["erro"] = "sem conexão"
      }
      fim(status, r)
    }.resume()
  }

  // O token fica só na memória, com a validade dele: o Chaveiro é lido uma vez por conta e de
  // novo apenas quando o token vence (ou quando a API recusa). Uma fila só: nunca dois pedidos
  // ao Chaveiro ao mesmo tempo.
  private static let filaChaveiro = DispatchQueue(label: "orion.chaveiro")
  private static var tokens: [String: (token: String, vence: Date)] = [:]
  private static var semToken: [String: Date] = [:]

  private static func esquecerToken(_ id: String) {
    filaChaveiro.sync { tokens[id] = nil; semToken[id] = Date() }
  }

  private static func tokenClaude(id: String, dir: String?, forcar: Bool) -> (token: String, doCache: Bool)? {
    filaChaveiro.sync {
      if let t = tokens[id], t.vence > Date().addingTimeInterval(60) { return (t.token, true) }
      // Sem login ou login vencido: não insiste no Chaveiro a cada atualização.
      if !forcar, let quando = semToken[id], Date().timeIntervalSince(quando) < 600 { return nil }
      let svc = servicoChaveiro(dir: dir)
      var bruto = Armazem.rodar("/usr/bin/security", ["find-generic-password", "-s", svc, "-w"], em: nil, limite: 30)
      if bruto == nil, let dir {
        bruto = try? String(contentsOfFile: dir + "/.credentials.json", encoding: .utf8)
      }
      guard let s = bruto?.trimmingCharacters(in: .whitespacesAndNewlines), let d = s.data(using: .utf8),
            let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
            let o = j["claudeAiOauth"] as? [String: Any], let t = o["accessToken"] as? String else {
        semToken[id] = Date()
        return nil
      }
      let ms = (o["expiresAt"] as? Double) ?? (o["expiresAt"] as? Int).map(Double.init) ?? 0
      let vence = ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : Date().addingTimeInterval(1800)
      tokens[id] = (t, max(vence, Date().addingTimeInterval(120)))
      semToken[id] = nil
      return (t, false)
    }
  }

  /// O Codex grava os limites (rate_limits) nos eventos das sessões; lê o mais recente.
  private static func usoCodex(_ home: String) -> [String: Any] {
    let raiz = URL(fileURLWithPath: home + "/sessions")
    guard let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: [.contentModificationDateKey]) else {
      return ["erro": "nenhuma sessão do Codex ainda"]
    }
    var recentes: [(URL, Date)] = []
    for case let u as URL in e where u.pathExtension == "jsonl" {
      let dt = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      recentes.append((u, dt))
    }
    for (u, _) in recentes.sorted(by: { $0.1 > $1.1 }).prefix(5) {
      guard let d = try? Data(contentsOf: u), let texto = String(data: d.suffix(400_000), encoding: .utf8) else { continue }
      for linha in texto.split(separator: "\n").reversed() where linha.contains("\"rate_limits\"") {
        guard let j = try? JSONSerialization.jsonObject(with: Data(linha.utf8)) as? [String: Any],
              let payload = j["payload"] as? [String: Any],
              let rl = payload["rate_limits"] as? [String: Any] else { continue }
        var r: [String: Any] = [:]
        for (chave, padrao) in [("primary", "h5"), ("secondary", "d7")] {
          if let w = rl[chave] as? [String: Any], let p = (w["used_percent"] as? Double) ?? (w["used_percent"] as? Int).map(Double.init) {
            // Qual janela é qual depende do plano: há planos em que a "primary" já é a semanal.
            let minutos = (w["window_minutes"] as? Double) ?? (w["window_minutes"] as? Int).map(Double.init)
            let nome = minutos.map { $0 >= 24 * 60 ? "d7" : "h5" } ?? padrao
            var reinicia: Any = NSNull()
            if let s = w["resets_at"] as? Double { reinicia = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: s)) }
            else if let s = w["resets_in_seconds"] as? Double { reinicia = ISO8601DateFormatter().string(from: Date().addingTimeInterval(s)) }
            r[nome] = ["pct": p, "reinicia": reinicia, "janela": w["window_minutes"] ?? NSNull()]
          }
        }
        if !r.isEmpty { r["fonte"] = "última sessão"; return r }
      }
    }
    return ["erro": "sem dados de limite nas sessões recentes"]
  }
}
