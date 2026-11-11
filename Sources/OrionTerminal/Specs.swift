import Foundation

/// O que o autocomplete sabe de cada comando: subcomandos, opções e o tipo de argumento.
final class Spec {
  let desc: String
  let op: [(String, String)]
  let sub: [String: Spec]
  let arg: String?
  init(_ desc: String = "", op: [(String, String)] = [], sub: [String: Spec] = [:], arg: String? = nil) {
    self.desc = desc; self.op = op; self.sub = sub; self.arg = arg
  }
}

enum Specs {
  private static func s(_ nomes: String) -> [String: Spec] {
    Dictionary(uniqueKeysWithValues: nomes.split(separator: " ").map { (String($0), Spec()) })
  }

  static let todos: [String: Spec] = [
    "claude": Spec("Claude Code", op: [
      ("-c", "continua a última conversa nesta pasta"), ("--continue", "continua a última conversa"),
      ("-r", "escolhe uma conversa para retomar"), ("--resume", "retoma uma conversa"),
      ("-p", "responde e sai"), ("--print", "responde e sai"), ("--model", "opus, sonnet, haiku…"),
      ("--permission-mode", "default, acceptEdits, plan, bypassPermissions"),
      ("--dangerously-skip-permissions", "pula todas as permissões"), ("--add-dir", "libera outra pasta"),
      ("--allowedTools", "ferramentas liberadas"), ("--mcp-config", "arquivo de MCP"),
      ("--output-format", "text, json, stream-json"), ("--append-system-prompt", "acrescenta ao prompt"),
      ("--fork-session", "retoma numa conversa nova"), ("--verbose", "mostra tudo"), ("-v", "versão"),
    ], sub: [
      "mcp": Spec("servidores MCP", sub: s("add add-json list get remove serve")),
      "config": Spec("ajustes", sub: s("get set list add remove")),
      "plugin": Spec("plugins", sub: s("install uninstall list enable disable marketplace")),
      "doctor": Spec("diagnóstico"), "update": Spec("atualiza o Claude Code"), "install": Spec("versão nativa"),
      "setup-token": Spec("token de longa duração"), "agents": Spec("subagentes"),
    ]),
    "codex": Spec("Codex CLI", op: [
      ("-m", "modelo"), ("--model", "modelo"), ("--full-auto", "edita e roda sem pedir (sandbox)"),
      ("--dangerously-bypass-approvals-and-sandbox", "sem sandbox nem aprovação"),
      ("-s", "read-only, workspace-write, danger-full-access"), ("-a", "untrusted, on-failure, on-request, never"),
      ("-C", "pasta de trabalho"), ("--search", "busca na web"), ("-i", "anexa imagem"), ("-p", "perfil"), ("-c", "chave do config"),
    ], sub: [
      "exec": Spec("roda sem interface", op: [("--json", "saída em JSON"), ("--skip-git-repo-check", "fora de repositório")]),
      "resume": Spec("retoma conversa", op: [("--last", "a mais recente")]),
      "login": Spec("entra na conta", op: [("--with-api-key", "chave de API")]), "logout": Spec("sai da conta"),
      "mcp": Spec("servidores MCP", sub: s("add list get remove login logout")),
      "apply": Spec("aplica o último diff"), "cloud": Spec("tarefas na nuvem"), "sandbox": Spec("roda na sandbox"),
    ]),
    "git": Spec("controle de versão", sub: [
      "status": Spec("o que mudou", op: [("-s", "curto"), ("-sb", "curto com branch")]),
      "add": Spec("prepara arquivos", op: [("-A", "tudo"), ("-p", "por trecho")], arg: "arquivos"),
      "commit": Spec("grava", op: [("-m", "mensagem"), ("--amend", "corrige o último"), ("-a", "inclui modificados"), ("--no-verify", "pula hooks")]),
      "push": Spec("envia", op: [("-u", "define upstream"), ("--force-with-lease", "força com segurança")]),
      "pull": Spec("traz e junta", op: [("--rebase", "com rebase"), ("--ff-only", "só fast-forward")]),
      "fetch": Spec("traz sem juntar", op: [("--all", "todos"), ("--prune", "limpa removidas")]),
      "checkout": Spec("troca de branch", op: [("-b", "cria branch")], arg: "branches"),
      "switch": Spec("troca de branch", op: [("-c", "cria branch")], arg: "branches"),
      "branch": Spec("branches", op: [("-d", "apaga"), ("-D", "força"), ("-a", "todas"), ("-m", "renomeia")], arg: "branches"),
      "merge": Spec("junta branch", op: [("--no-ff", "sempre merge"), ("--abort", "cancela")], arg: "branches"),
      "rebase": Spec("reaplica commits", op: [("-i", "interativo"), ("--continue", "continua"), ("--abort", "cancela")], arg: "branches"),
      "log": Spec("histórico", op: [("--oneline", "uma linha"), ("--graph", "gráfico"), ("-p", "com diff")]),
      "diff": Spec("diferenças", op: [("--staged", "preparado"), ("--stat", "resumo")], arg: "arquivos"),
      "stash": Spec("guarda mudanças", sub: s("push pop list apply drop show")),
      "restore": Spec("desfaz em arquivo", op: [("--staged", "tira do preparo")], arg: "arquivos"),
      "reset": Spec("volta o HEAD", op: [("--soft", "mantém mudanças"), ("--hard", "descarta tudo")]),
      "clone": Spec("clona"), "init": Spec("cria repositório"), "remote": Spec("remotos", sub: s("add remove set-url -v")),
      "worktree": Spec("árvores de trabalho", sub: s("add list remove")), "show": Spec("mostra commit"), "tag": Spec("tags"),
    ]),
    "gh": Spec("GitHub CLI", sub: [
      "pr": Spec("pull requests", sub: s("create list view checkout merge status diff checks")),
      "issue": Spec("issues", sub: s("create list view close")), "repo": Spec("repositórios", sub: s("clone create view fork")),
      "run": Spec("Actions", sub: s("list view watch rerun")), "auth": Spec("login", sub: s("login status logout")),
    ]),
    "npm": Spec("Node", sub: [
      "run": Spec("roda script", arg: "scripts"), "install": Spec("instala", op: [("-D", "dev"), ("-g", "global")]),
      "i": Spec("instala"), "ci": Spec("instala do lock"), "test": Spec("testes"), "start": Spec("inicia"),
      "uninstall": Spec("remove"), "update": Spec("atualiza"), "outdated": Spec("desatualizados"), "exec": Spec("roda binário"),
    ]),
    "pnpm": Spec("pnpm", sub: ["run": Spec("roda script", arg: "scripts"), "install": Spec(), "add": Spec(), "remove": Spec(), "dlx": Spec()], arg: "scripts"),
    "bun": Spec("bun", sub: ["run": Spec("roda script", arg: "scripts"), "install": Spec(), "add": Spec(), "remove": Spec(), "x": Spec()], arg: "scripts"),
    "yarn": Spec("yarn", sub: s("add remove install"), arg: "scripts"),
    "docker": Spec("containers", sub: [
      "ps": Spec("rodando", op: [("-a", "todos")]), "run": Spec(), "exec": Spec(), "logs": Spec("logs", op: [("-f", "acompanha")]),
      "build": Spec(), "images": Spec(), "stop": Spec(), "rm": Spec(), "pull": Spec(),
      "compose": Spec("compose", sub: ["up": Spec(op: [("-d", "segundo plano"), ("--build", "reconstrói")]), "down": Spec(), "logs": Spec(), "ps": Spec(), "restart": Spec()]),
    ]),
    "brew": Spec("Homebrew", sub: [
      "install": Spec(), "uninstall": Spec(), "upgrade": Spec(), "update": Spec(), "list": Spec(), "search": Spec(),
      "info": Spec(), "outdated": Spec(), "cleanup": Spec(), "services": Spec("serviços", sub: s("list start stop restart")),
    ]),
    "orion": Spec("controla o Orion Terminal", sub: [
      "abas": Spec("lista abas e painéis"), "ler": Spec("lê a tela de um painel"), "rodar": Spec("roda comando e espera"),
      "enviar": Spec("digita num painel"), "nova": Spec("abre aba"), "dividir": Spec("divide o painel"),
      "focar": Spec("mostra um painel"), "fechar": Spec("fecha um painel"), "esperar": Spec("espera ficar livre"),
      "notificar": Spec("mostra uma notificação"), "renomear": Spec("renomeia a aba"), "contas": Spec("lista contas"), "ajuda": Spec("guia para IA"),
    ]),
    "cd": Spec("entra na pasta", arg: "pastas"), "z": Spec("zoxide", arg: "pastas"),
    "ls": Spec(arg: "arquivos"), "ll": Spec(arg: "arquivos"), "la": Spec(arg: "arquivos"), "eza": Spec(arg: "arquivos"),
    "cat": Spec(arg: "arquivos"), "bat": Spec(arg: "arquivos"), "less": Spec(arg: "arquivos"), "tail": Spec(arg: "arquivos"),
    "code": Spec("abre no VS Code", arg: "arquivos"), "cursor": Spec("abre no Cursor", arg: "arquivos"),
    "open": Spec("abre no macOS", op: [(".", "pasta no Finder"), ("-a", "com o app")], arg: "arquivos"),
    "vim": Spec(arg: "arquivos"), "nvim": Spec(arg: "arquivos"), "nano": Spec(arg: "arquivos"),
    "rm": Spec(op: [("-r", "recursivo"), ("-f", "força")], arg: "arquivos"), "mv": Spec(arg: "arquivos"),
    "cp": Spec(op: [("-r", "recursivo")], arg: "arquivos"), "mkdir": Spec(op: [("-p", "cria os pais")], arg: "pastas"),
    "touch": Spec(arg: "arquivos"), "python3": Spec(arg: "arquivos"), "node": Spec(arg: "arquivos"), "source": Spec(arg: "arquivos"),
    "cswap": Spec("contas do Claude", sub: s("status list switch run")),
  ]

  static let comandosBase: Set<String> = Set(todos.keys).union([
    "clear", "exit", "echo", "export", "grep", "rg", "fd", "find", "which", "man", "history", "pwd", "top", "htop",
    "curl", "wget", "tar", "unzip", "chmod", "ps", "lsof", "sudo", "tmux", "make", "swift", "go", "cargo",
    "pip3", "uv", "fnm", "deno", "vercel", "supabase", "psql", "jq", "tree", "du", "df", "npx", "ssh", "kill",
  ])
}
