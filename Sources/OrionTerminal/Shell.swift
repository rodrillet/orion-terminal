import Foundation

/// Monta o ambiente do shell e a integração com o zsh (marcas OSC 133 / OSC 7),
/// que é o que deixa a interface saber onde começa o prompt, a pasta atual e o comando rodando.
enum Shell {
  static let versao = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"

  static var padrao: String {
    if let s = ProcessInfo.processInfo.environment["SHELL"], FileManager.default.isExecutableFile(atPath: s) { return s }
    if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell { return String(cString: sh) }
    return "/bin/zsh"
  }

  /// Variáveis herdadas que não podem vazar para as abas.
  private static let descartar: Set<String> = [
    "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CONFIG_DIR", "CODEX_HOME", "CODEX_SANDBOX", "GEMINI_CLI_HOME",
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "ITERM_SESSION_ID", "ITERM_PROFILE",
    "VSCODE_INJECTION", "VSCODE_GIT_IPC_HANDLE", "XPC_SERVICE_NAME", "__CFBundleIdentifier",
    "ZDOTDIR", "ORION_RUN", "ORION_ZDOTDIR_USUARIO", "ORION_INTEGRADO", "OLDPWD", "PWD", "SHLVL",
    "STARSHIP_SESSION_KEY", "STARSHIP_SHELL", "WARP_IS_LOCAL_SHELL_SESSION", "GHOSTTY_RESOURCES_DIR",
  ]

  struct Lancamento {
    var executavel: String
    var argv: [String]
    var env: [String: String]
  }

  static func preparar(shell: String?, comando: String?, extra: [String: String], idAba: String) -> Lancamento {
    let sh = (shell?.isEmpty == false ? shell! : padrao)
    var env = ProcessInfo.processInfo.environment.filter { (k, _) in
      !descartar.contains(k) && !k.hasPrefix("CLAUDE_CODE_") && !k.hasPrefix("CODEX_") && !k.hasPrefix("CLAUDE_AGENT")
    }
    let home = NSHomeDirectory()
    env["HOME"] = env["HOME"] ?? home
    env["USER"] = env["USER"] ?? NSUserName()
    env["LOGNAME"] = env["LOGNAME"] ?? NSUserName()
    env["SHELL"] = sh
    env["PATH"] = env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    if env["LANG"] == nil { env["LANG"] = "pt_BR.UTF-8" }
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    env["TERM_PROGRAM"] = "OrionTerminal"
    env["TERM_PROGRAM_VERSION"] = versao
    env["ORION_PAINEL"] = idAba
    env["ORION_SOCKET"] = Armazem.pasta.appendingPathComponent("controle.sock").path
    if let cli = Bundle.main.executableURL?.deletingLastPathComponent().path { env["PATH"] = (env["PATH"] ?? "") + ":" + cli }
    for (k, v) in extra { env[k] = v }

    let nome = (sh as NSString).lastPathComponent
    if nome == "zsh" {
      let usuario = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? home
      env["ORION_ZDOTDIR_USUARIO"] = usuario
      env["ZDOTDIR"] = Armazem.pastaZsh.path
    }
    if let c = comando, !c.isEmpty {
      if nome == "zsh" {
        env["ORION_RUN"] = c   // roda no primeiro prompt; ao sair, o shell continua aberto
      } else {
        return Lancamento(executavel: sh, argv: ["-" + nome, "-i", "-c", "\(c); exec \(sh) -l"], env: env)
      }
    }
    return Lancamento(executavel: sh, argv: ["-" + nome], env: env)
  }

  /// Escreve os arquivos de integração do zsh (recriados a cada abertura do app).
  static func instalarIntegracao() {
    let dir = Armazem.pastaZsh
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cabecalho = "# Orion Terminal — integração com o zsh. Recriado a cada abertura do app; não edite.\n"
    func estagio(_ arq: String) -> String {
      """
      \(cabecalho)ORION_ZDOTDIR="$ZDOTDIR"
      ZDOTDIR="${ORION_ZDOTDIR_USUARIO:-$HOME}"
      [[ -f "$ZDOTDIR/\(arq)" ]] && builtin source "$ZDOTDIR/\(arq)"
      ORION_ZDOTDIR_USUARIO="$ZDOTDIR"
      ZDOTDIR="$ORION_ZDOTDIR"

      """
    }
    let zshrc = """
    \(cabecalho)ZDOTDIR="${ORION_ZDOTDIR_USUARIO:-$HOME}"
    [[ -f "$ZDOTDIR/.zshrc" ]] && builtin source "$ZDOTDIR/.zshrc"
    # Daqui em diante o ZDOTDIR é o seu: o .zlogin e os shells filhos usam os seus arquivos.

    if [[ -z "$ORION_INTEGRADO" ]]; then
      typeset -g ORION_INTEGRADO=1
      autoload -Uz add-zsh-hook
      __orion_precmd() {
        local s=$?
        builtin printf '\\e]133;D;%s\\a\\e]7;file://%s%s\\a\\e]133;A\\a' "$s" "${HOST}" "${PWD// /%20}"
      }
      __orion_preexec() {
        builtin printf '\\e]133;C\\a\\e]633;E;%s\\a' "${1//[[:cntrl:]]/ }"
      }
      # Primeiro da fila: assim o $? é o do comando, não o de outro precmd.
      precmd_functions=(__orion_precmd ${precmd_functions:#__orion_precmd})
      add-zsh-hook preexec __orion_preexec

      if [[ -n "$ORION_RUN" ]]; then
        __orion_rodar() {
          add-zsh-hook -d precmd __orion_rodar
          local c="$ORION_RUN"; unset ORION_RUN
          builtin print -s -- "$c"
          builtin printf '\\e]133;C\\a\\e]633;E;%s\\a' "$c"
          builtin eval "$c"
        }
        add-zsh-hook precmd __orion_rodar
      fi
    fi

    """
    let arquivos: [String: String] = [
      ".zshenv": estagio(".zshenv"),
      ".zprofile": estagio(".zprofile"),
      ".zshrc": zshrc,
    ]
    for (nome, conteudo) in arquivos {
      try? conteudo.write(to: dir.appendingPathComponent(nome), atomically: true, encoding: .utf8)
    }
  }
}

