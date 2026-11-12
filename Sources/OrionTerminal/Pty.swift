import Foundation
import Darwin

/// Um processo rodando num pseudo-terminal. Lê a saída numa fila própria e entrega os bytes
/// direto para quem consome (o painel alimenta o terminal na mesma fila, sem cópia extra).
final class Sessao {
  let id: String
  private(set) var pid: pid_t = -1
  private(set) var fd: Int32 = -1
  private var leitura: DispatchSourceRead?
  private var fim: DispatchSourceProcess?
  private let filaLeitura: DispatchQueue
  private let filaEscrita: DispatchQueue
  private(set) var encerrada = false
  /// Enquanto morre, a sessão segura a si mesma: quem a matou já soltou a referência, e sem isto
  /// o aviso de saída (waitpid + close do pty) nunca rodava — cada aba fechada deixava um fd de
  /// pty aberto e um processo zumbi.
  private var morrendo: Sessao?
  var aoSair: ((Int32) -> Void)?
  /// Chamado na fila de leitura com cada bloco lido.
  var aoReceber: ((ArraySlice<UInt8>) -> Void)?

  init(id: String) {
    self.id = id
    filaLeitura = DispatchQueue(label: "orion.pty.leitura.\(id)")
    filaEscrita = DispatchQueue(label: "orion.pty.escrita.\(id)")
  }

  /// Inicia `executavel` com `argv` (argv[0] pode começar com "-" para shell de login).
  func iniciar(executavel: String, argv: [String], env: [String: String], cwd: String,
               cols: Int, linhas: Int) throws {
    // Tudo que o filho usa é preparado ANTES do fork: depois dele só chamadas seguras.
    let cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { s -> UnsafeMutablePointer<CChar>? in strdup(s) } + [nil]
    let cEnv: [UnsafeMutablePointer<CChar>?] = env.map { (k, v) -> UnsafeMutablePointer<CChar>? in strdup("\(k)=\(v)") } + [nil]
    let cExe = strdup(executavel)
    let cDir = strdup(cwd)
    defer {
      cArgs.forEach { free($0) }; cEnv.forEach { free($0) }
      free(cExe); free(cDir)
    }
    var ws = winsize(ws_row: UInt16(max(linhas, 2)), ws_col: UInt16(max(cols, 10)), ws_xpixel: 0, ws_ypixel: 0)
    var mestre: Int32 = -1
    let p = forkpty(&mestre, nil, nil, &ws)
    if p < 0 { throw NSError(domain: "Orion", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "forkpty falhou (\(errno))"]) }
    if p == 0 {
      _ = chdir(cDir)
      // Nada do app (sockets, outros PTYs) pode vazar para o shell.
      var d: Int32 = 3
      while d < 256 { close(d); d += 1 }
      // Sinais que o app ignora não podem vazar para o shell.
      signal(SIGINT, SIG_DFL); signal(SIGQUIT, SIG_DFL); signal(SIGPIPE, SIG_DFL)
      signal(SIGTERM, SIG_DFL); signal(SIGCHLD, SIG_DFL); signal(SIGHUP, SIG_DFL)
      execve(cExe!, cArgs, cEnv)
      _exit(127)
    }
    pid = p
    fd = mestre
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

    let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: filaLeitura)
    let tamanho = 128 * 1024
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: tamanho)
    src.setEventHandler { [weak self] in
      guard let self else { return }
      let n = read(self.fd, buf, tamanho)
      if n > 0 {
        self.aoReceber?(ArraySlice(UnsafeBufferPointer(start: buf, count: n)))
      } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
        self.leitura?.cancel()
      }
    }
    src.setCancelHandler { buf.deallocate() }
    leitura = src
    src.resume()

    let f = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: filaLeitura)
    f.setEventHandler { [weak self] in
      guard let self else { return }
      var status: Int32 = 0
      waitpid(self.pid, &status, 0)
      // Deixa a leitura drenar o que sobrou antes de avisar.
      self.filaLeitura.asyncAfter(deadline: .now() + 0.15) {
        let codigo: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        self.encerrar()
        DispatchQueue.main.async { self.aoSair?(codigo) }
      }
    }
    fim = f
    f.resume()
  }

  func escrever(_ dados: Data) {
    guard !encerrada, fd >= 0 else { return }
    let f = fd
    filaEscrita.async {
      dados.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard var p = raw.baseAddress else { return }
        var resta = raw.count
        while resta > 0 {
          let n = write(f, p, resta)
          if n < 0 { if errno == EINTR || errno == EAGAIN { usleep(1000); continue }; return }
          resta -= n; p = p.advanced(by: n)
        }
      }
    }
  }

  func redimensionar(cols: Int, linhas: Int) {
    guard !encerrada, fd >= 0 else { return }
    var ws = winsize(ws_row: UInt16(max(linhas, 2)), ws_col: UInt16(max(cols, 10)), ws_xpixel: 0, ws_ypixel: 0)
    _ = ioctl(fd, TIOCSWINSZ, &ws)
  }

  /// Fecha a aba: SIGHUP no grupo do shell (como o Terminal faz) e no grupo do que está em
  /// primeiro plano (o agente roda num grupo próprio), SIGKILL se não sair.
  func matar() {
    guard !encerrada, pid > 0 else { return }
    morrendo = self
    let p = pid
    let g = fd >= 0 ? tcgetpgrp(fd) : -1
    if g > 0 && g != p { kill(-g, SIGHUP) }
    kill(-p, SIGHUP); kill(p, SIGHUP)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
      if g > 0 && g != p { kill(-g, SIGKILL) }
      kill(-p, SIGKILL); kill(p, SIGKILL)
    }
    // Rede de segurança: se o aviso de saída não vier, solta e fecha mesmo assim.
    filaLeitura.asyncAfter(deadline: .now() + 5) { [weak self] in self?.encerrar() }
  }

  private func encerrar() {
    if encerrada { morrendo = nil; return }
    encerrada = true
    leitura?.cancel()
    fim?.cancel()
    if fd >= 0 { close(fd); fd = -1 }
    if pid > 0 { var st: Int32 = 0; waitpid(pid, &st, WNOHANG) }
    morrendo = nil
  }

  // MARK: - O que está rodando

  /// Processo em primeiro plano no terminal (o comando que o usuário rodou, ou o próprio shell).
  func processoAtivo() -> (pid: pid_t, nome: String)? {
    guard !encerrada, fd >= 0 else { return nil }
    let g = tcgetpgrp(fd)
    guard g > 0 else { return nil }
    return (g, Sessao.nomeDoProcesso(g))
  }

  /// Só o pid do processo em primeiro plano (barato: uma chamada, sem ler nome nem argumentos).
  func pidAtivo() -> pid_t? {
    guard !encerrada, fd >= 0 else { return nil }
    let g = tcgetpgrp(fd)
    return g > 0 ? g : nil
  }

  /// Pasta atual do shell (vale quando a integração do zsh não mandou OSC 7).
  func pastaAtual() -> String? {
    guard pid > 0 else { return nil }
    return Sessao.pasta(de: pid)
  }

  static func pasta(de pid: pid_t) -> String? {
    var vi = proc_vnodepathinfo()
    let r = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vi, Int32(MemoryLayout<proc_vnodepathinfo>.size))
    guard r > 0 else { return nil }
    let s = withUnsafePointer(to: vi.pvi_cdir.vip_path) {
      $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
    return s.isEmpty ? nil : s
  }

  /// Nome "humano": argv[0] (o Claude nativo roda de .../versions/2.1.x, então o executável
  /// sozinho mentiria), com fallback para o nome do processo.
  static func nomeDoProcesso(_ pid: pid_t) -> String {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var tam = 0
    if sysctl(&mib, 3, nil, &tam, nil, 0) == 0, tam > 8 {
      var buf = [UInt8](repeating: 0, count: tam)
      if sysctl(&mib, 3, &buf, &tam, nil, 0) == 0 {
        // [argc:int32][exec_path\0][\0...][argv0\0][argv1\0]...
        var i = 4
        while i < tam && buf[i] != 0 { i += 1 }
        while i < tam && buf[i] == 0 { i += 1 }
        var j = i
        while j < tam && buf[j] != 0 { j += 1 }
        if j > i, let argv0 = String(bytes: buf[i..<j], encoding: .utf8) {
          var nome = (argv0 as NSString).lastPathComponent
          if nome.hasPrefix("-") { nome.removeFirst() }
          // node/python rodando um script: mostra o script (ex.: "codex", "vite").
          if ["node", "python", "python3", "bun", "deno"].contains(nome) {
            var k = j + 1
            while k < tam && buf[k] != 0 {
              var e = k
              while e < tam && buf[e] != 0 { e += 1 }
              if let arg = String(bytes: buf[k..<e], encoding: .utf8), !arg.hasPrefix("-") {
                let base = (arg as NSString).lastPathComponent
                if !base.isEmpty { return base.replacingOccurrences(of: ".js", with: "") }
                break
              }
              k = e + 1
            }
          }
          if !nome.isEmpty { return nome }
        }
      }
    }
    var nb = [CChar](repeating: 0, count: 256)
    proc_name(pid, &nb, 256)
    return String(cString: nb)
  }
}
