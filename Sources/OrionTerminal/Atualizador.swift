import Cocoa
import Observation
import CryptoKit
import UserNotifications

/// Atualizações pelos releases do GitHub.
///
/// Como chega a todo mundo logo depois de publicar:
/// - consulta `releases/latest` ao abrir, ao voltar para a frente (no máximo a cada 20 min) e a cada hora;
///   usa ETag, então uma consulta sem novidade custa um 304 e não gasta o limite da API;
/// - achou versão nova: baixa em segundo plano, confere o SHA-256 publicado no release, confere que o
///   pacote é o Orion Terminal na versão anunciada e deixa pronto em Application Support;
/// - avisa uma vez (notificação + botão no topo) e aplica sozinho quando o app fecha — ou na hora,
///   com "Reiniciar e atualizar". Um script espera o app sair, troca o pacote (voltando atrás se falhar)
///   e reabre se foi pedido.
/// Nada é enviado: é só leitura pública dos releases.
@MainActor @Observable
final class Atualizador {
  static let shared = Atualizador()
  static let repositorio = "rodrillet/orion-terminal"

  struct Versao: Equatable {
    let numero: String
    let notas: String
    let pagina: URL
    let zip: URL
    let sha256: URL?
  }

  enum Estado: Equatable { case ocioso, verificando, baixando, pronto, erro(String) }

  var disponivel: Versao?
  var estado: Estado = .ocioso
  var ultimaVerificacao: Date?
  /// Pacote já baixado e conferido, esperando para entrar no lugar.
  @ObservationIgnored private(set) var preparado: URL?
  @ObservationIgnored private var relogio: Timer?
  @ObservationIgnored private var etag: String?
  @ObservationIgnored private var ultimoJSON: Data?
  @ObservationIgnored private var modo = "automatica"     // automatica | avisar | desligada
  @ObservationIgnored weak var loja: Loja?

  var atual: String { Shell.versao }
  var pasta: URL { Armazem.pasta.appendingPathComponent("atualizacao", isDirectory: true) }

  // MARK: - Quando verificar

  func comecar(modo: String, loja: Loja) {
    self.modo = modo
    self.loja = loja
    relogio?.invalidate()
    limparPreparosAntigos()
    guard modo != "desligada", atual != "dev" else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.verificar() }
    relogio = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.verificar() }
    }
    relogio?.tolerance = 300
  }

  func mudouModo(_ novo: String) {
    guard let loja else { return }
    comecar(modo: novo, loja: loja)
  }

  /// O app voltou para a frente: vale uma olhada se a última foi há mais de 20 min.
  func appAtivou() {
    guard modo != "desligada" else { return }
    if let u = ultimaVerificacao, Date().timeIntervalSince(u) < 20 * 60 { return }
    verificar()
  }

  /// "0.10.0" > "0.9.3". Sufixos (ex.: "-beta") são ignorados.
  static func maior(_ a: String, que b: String) -> Bool {
    func partes(_ s: String) -> [Int] {
      s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: "-").first.map {
        $0.split(separator: ".").map { Int($0) ?? 0 }
      } ?? []
    }
    let x = partes(a), y = partes(b)
    for i in 0..<max(x.count, y.count) {
      let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
      if p != q { return p > q }
    }
    return false
  }

  // MARK: - Verificar

  func verificar(_ concluir: ((Versao?, String?) -> Void)? = nil) {
    guard estado != .baixando else { concluir?(disponivel, nil); return }
    if estado != .pronto { estado = .verificando }
    var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Atualizador.repositorio)/releases/latest")!)
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    req.setValue("orion-terminal/\(atual)", forHTTPHeaderField: "User-Agent")
    if let e = etag, ultimoJSON != nil { req.setValue(e, forHTTPHeaderField: "If-None-Match") }
    req.cachePolicy = .reloadIgnoringLocalCacheData
    req.timeoutInterval = 15
    URLSession.shared.dataTask(with: req) { dados, resp, erro in
      let http = resp as? HTTPURLResponse
      let status = http?.statusCode ?? 0
      let novaEtag = http?.value(forHTTPHeaderField: "ETag")
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.ultimaVerificacao = Date()
          var json = dados
          if status == 304 { json = self.ultimoJSON }
          else if status == 200 { self.ultimoJSON = dados; self.etag = novaEtag }
          var falha: String?
          if (status == 200 || status == 304), let json, let v = Atualizador.ler(json) {
            if Atualizador.maior(v.numero, que: self.atual) {
              let nova = self.disponivel?.numero != v.numero
              self.disponivel = v
              if nova { self.achouNova(v) }
            } else { self.disponivel = nil; self.preparado = nil }
          } else if status == 404 { falha = "nenhum release publicado ainda" }
          else if status == 403 || status == 429 { falha = "limite da API do GitHub; tento de novo mais tarde" }
          else if status != 200 && status != 304 { falha = erro?.localizedDescription ?? "GitHub respondeu \(status)" }
          if self.estado == .verificando { self.estado = falha.map { .erro($0) } ?? .ocioso }
          concluir?(self.disponivel, falha)
        }
      }
    }.resume()
  }

  private static func ler(_ dados: Data) -> Versao? {
    guard let j = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
          let tag = j["tag_name"] as? String, j["draft"] as? Bool != true, j["prerelease"] as? Bool != true,
          let pagina = (j["html_url"] as? String).flatMap(URL.init) else { return nil }
    let assets = j["assets"] as? [[String: Any]] ?? []
    func url(_ fim: String) -> URL? {
      assets.first { ($0["name"] as? String)?.hasSuffix(fim) == true }
        .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init)
    }
    guard let zip = url(".zip") else { return nil }
    return Versao(numero: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), notas: j["body"] as? String ?? "",
                  pagina: pagina, zip: zip, sha256: url(".zip.sha256"))
  }

  /// Versão nova: avisa uma vez e, no modo automático, já deixa pronta.
  private func achouNova(_ v: Versao) {
    let chave = "OrionAvisouVersao"
    if UserDefaults.standard.string(forKey: chave) != v.numero {
      UserDefaults.standard.set(v.numero, forKey: chave)
      let c = UNUserNotificationCenter.current()
      c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
        guard ok else { return }
        let n = UNMutableNotificationContent()
        n.title = "Orion Terminal \(v.numero) disponível"
        n.body = "Entra sozinha quando você fechar o app — ou clique em Atualizar no topo."
        n.userInfo = ["atualizacao": v.numero]
        c.add(UNNotificationRequest(identifier: "atualizacao-\(v.numero)", content: n, trigger: nil))
      }
    }
    if modo == "automatica" { preparar(v) { _ in } }
  }

  // MARK: - Baixar e conferir

  /// Baixa, confere SHA-256, descompacta e valida o pacote. Chama `fim` com o .app pronto (ou nil).
  func preparar(_ v: Versao, _ fim: @escaping (String?) -> Void) {
    if estado == .pronto, preparado != nil, disponivel == v { fim(nil); return }
    guard estado != .baixando else { return }
    estado = .baixando
    let alvo = pasta.appendingPathComponent(v.numero, isDirectory: true)
    try? FileManager.default.removeItem(at: alvo)
    try? FileManager.default.createDirectory(at: alvo, withIntermediateDirectories: true)
    let zip = alvo.appendingPathComponent("app.zip")
    let erro: (String) -> Void = { m in self.estado = .erro(m); fim(m) }
    URLSession.shared.downloadTask(with: v.zip) { arq, resp, e in
      var ok = false
      if let arq, ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200 { ok = (try? FileManager.default.moveItem(at: arq, to: zip)) != nil }
      let descricao = e?.localizedDescription
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard ok else { erro("não consegui baixar (\(descricao ?? "erro"))"); return }
          self.conferirSHA(v, zip: zip) { confere in
            guard confere else { erro("o arquivo baixado não confere com o SHA-256 do release"); return }
            self.descompactar(zip: zip, em: alvo, versao: v) { app in
              guard let app else { erro("o pacote baixado não é o Orion Terminal \(v.numero)"); return }
              self.preparado = app
              self.estado = .pronto
              fim(nil)
            }
          }
        }
      }
    }.resume()
  }

  private func conferirSHA(_ v: Versao, zip: URL, _ fim: @escaping (Bool) -> Void) {
    guard let s = v.sha256 else { fim(false); return }   // sem soma publicada, não instala
    URLSession.shared.dataTask(with: s) { d, _, _ in
      let esperado = d.flatMap { String(data: $0, encoding: .utf8) }?
        .split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map { String($0).lowercased() }
      let real = (try? Data(contentsOf: zip)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
      DispatchQueue.main.async { MainActor.assumeIsolated { fim(esperado != nil && esperado == real) } }
    }.resume()
  }

  private func descompactar(zip: URL, em alvo: URL, versao v: Versao, _ fim: @escaping (URL?) -> Void) {
    let saida = alvo.appendingPathComponent("novo", isDirectory: true)
    let id = Bundle.main.bundleIdentifier
    DispatchQueue.global(qos: .utility).async {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
      p.arguments = ["-x", "-k", zip.path, saida.path]
      try? p.run(); p.waitUntilExit()
      let app = (try? FileManager.default.contentsOfDirectory(at: saida, includingPropertiesForKeys: nil))?.first { $0.pathExtension == "app" }
      let info = app.flatMap { NSDictionary(contentsOf: $0.appendingPathComponent("Contents/Info.plist")) as? [String: Any] }
      let valido = p.terminationStatus == 0 && info?["CFBundleIdentifier"] as? String == id
        && info?["CFBundleShortVersionString"] as? String == v.numero
      try? FileManager.default.removeItem(at: zip)
      DispatchQueue.main.async { MainActor.assumeIsolated { fim(valido ? app : nil) } }
    }
  }

  private func limparPreparosAntigos() {
    guard let itens = try? FileManager.default.contentsOfDirectory(atPath: pasta.path) else { return }
    for n in itens where !Atualizador.maior(n, que: atual) { try? FileManager.default.removeItem(at: pasta.appendingPathComponent(n)) }
  }

  // MARK: - Instalar

  /// "Atualizar agora": prepara se preciso e reinicia já na versão nova.
  func instalarAgora() {
    guard let v = disponivel, let loja else { return }
    guard podeEscrever else {
      loja.avisar("Sem permissão para atualizar", "O app está numa pasta onde não consigo escrever. Baixe a versão \(v.numero) pela página do release.",
                  simbolo: "lock.fill")
      NSWorkspace.shared.open(v.pagina)
      return
    }
    preparar(v) { erro in
      if let erro { loja.avisar("A atualização não foi feita", erro.prefix(1).uppercased() + erro.dropFirst() + ". Nada foi trocado.", simbolo: "exclamationmark.triangle.fill"); return }
      if self.agendarTroca(reabrir: true) { NSApp.terminate(nil) }
    }
  }

  /// Chamado ao fechar o app: se há versão pronta, ela entra no lugar (sem reabrir).
  func aoSair() {
    guard modo == "automatica", preparado != nil else { return }
    _ = agendarTroca(reabrir: false)
  }

  private var podeEscrever: Bool {
    FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
  }

  @ObservationIgnored private var trocaAgendada = false

  private func agendarTroca(reabrir: Bool) -> Bool {
    guard !trocaAgendada, let novo = preparado, podeEscrever else { return false }
    let destino = Bundle.main.bundleURL
    let script = """
    #!/bin/bash
    PID="$1"; NOVO="$2"; DESTINO="$3"; REABRIR="$4"
    for i in $(seq 1 2400); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
    kill -0 "$PID" 2>/dev/null && exit 1
    rm -rf "$DESTINO.antigo"
    if mv "$DESTINO" "$DESTINO.antigo" && mv "$NOVO" "$DESTINO"; then
      rm -rf "$DESTINO.antigo"
      xattr -dr com.apple.quarantine "$DESTINO" 2>/dev/null
    else
      [ -d "$DESTINO.antigo" ] && [ ! -d "$DESTINO" ] && mv "$DESTINO.antigo" "$DESTINO"
    fi
    [ "$REABRIR" = "1" ] && open "$DESTINO"
    rm -rf "$(dirname "$(dirname "$NOVO")")"
    """
    let arq = pasta.appendingPathComponent("trocar.sh")
    try? script.write(to: arq, atomically: true, encoding: .utf8)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [arq.path, String(getpid()), novo.path, destino.path, reabrir ? "1" : "0"]
    do { try p.run() } catch { estado = .erro("não consegui iniciar a troca"); return false }
    trocaAgendada = true
    return true
  }
}
