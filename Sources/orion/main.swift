import Foundation
import Darwin

// orion — controla o Orion Terminal pela linha de comando (feito para agentes de IA e scripts).

let ajuda = """
orion — controla o Orion Terminal

Workspaces (um por projeto/cliente; cada um com seus terminais e agentes)
  orion workspaces [--json]                    lista: número, nome, pasta, abas, agentes
  orion workspace novo "Nome" [--pasta P] [--cor #hex] [--simbolo S] [--fundo]
  orion workspace focar NOME|N                 troca o workspace na tela
  orion workspace renomear NOME "Novo nome"
  orion workspace editar NOME [--pasta P] [--cor #hex] [--simbolo S]
  orion workspace fechar NOME [--forcar]       fecha o workspace e as abas dele

Agentes (Claude Code / Codex / Gemini CLI) — cada um é um personagem
  orion agentes [--json] [--workspace W] [--tudo]
                                               personagem, estado, há quanto tempo, tarefa, conta
  orion agente --claude|--codex|--gemini [--workspace W] [--pasta P] [--conta ID]
               [--nome N] [--papel P] [--mensagem "tarefa"] [--fundo]
                                               abre um agente; a tarefa dá o nome a ele
  orion enviar ID "texto" [--enter] [--anexo ARQ]… [--mencionar ID]…
  orion compor ID ["texto"] [--anexo ARQ]… [--mencionar ID]… [--para ID]… [--focar] [--limpar]
  orion contexto [ID] [--linhas N]             tela recente / último comando, em bloco
  orion esperar ID [--tempo S]                 espera o agente parar / o comando terminar
  orion interromper ID · orion reiniciar ID
  orion marcar [ID] revisar|concluido|nada     coluna do quadro
  orion personagem [ID] [--nome N] [--papel P] [--avatar FORMA] [--maestro]
                                               FORMA: gota bolha nuvem pilula hexa flor fantasma losango
  orion fechados · orion reabrir [N|ID] [--fundo]
                                               agentes fechados há pouco voltam na mesma conversa
  orion conta ID CONTA · orion conta --padrao CONTA · orion contas · orion uso [--atualizar]
  orion memoria [--json]

Maestro e subagentes
  orion agente --claude --pai $ORION_PAINEL [--papel P] [--retorno] --mensagem "tarefa"
                                               cria um subagente seu (em segundo plano); com
                                               --retorno, o resultado volta sozinho quando ele parar
  orion filhos [ID] [--json]                   os subagentes de um maestro (padrão: os seus)
  orion esperar --filhos [ID] [--tempo S]      espera todos pararem
  orion resultado ID [--linhas N]              a última resposta do subagente

Terminais
  orion abas [--json] [--workspace W]          abas e painéis (id, pasta, programa, estado)
  orion ler [ID] [--linhas N]                  texto da tela (+ N linhas de rolagem)
  orion rodar "cmd" [--painel ID] [--esperar] [--tempo S]
                                               roda num painel; com --esperar devolve a saída
                                               e sai com o código do comando. Sem --painel,
                                               usa um painel auxiliar abaixo do seu.
  orion nova [--claude|--codex|--shell] [--workspace W] [--pasta P] [--conta ID]
             [--titulo T] [--comando C] [--fundo]
  orion dividir [ID] [--abaixo] [--comando C] [--focar]
  orion focar ID | orion fechar ID | orion renomear [ID] "título"
  orion notificar "texto" [--titulo T]
  orion portas [--todas] [--json]              servidores em escuta: porta, processo, painel
  orion liberar PORTA                          encerra o processo que ocupa a porta

Interface
  orion versao | atualizar                     versão instalada / instala a mais nova do GitHub
  orion ui quadro | paleta | ajustes [seção] | contas | temas | lateral | barra | fechar
  orion ui workspaces | historico | agentes     seletor de workspace / o que a barra lateral mostra
  orion ui claude | codex | gemini             painel da ferramenta (contas, uso, agentes, novo)
  orion ui conversa [ID] | portas | subagente [ID] | personagem [ID]
  orion ui uso [claude|codex]                  o resumo (o mesmo do hover)
  orion ui compose [ID] | novo-agente [claude|codex] | novo-workspace
  orion estado [--json] · orion ajuda

ID = id do painel (veja `orion abas` ou `orion agentes`), ou "atual".
Dentro do Orion, $ORION_PAINEL é o seu próprio painel.
"""

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first, !["-h", "--help", "ajuda", "help"].contains(cmd) else { print(ajuda); exit(0) }
args.removeFirst()

var pedido: [String: Any] = ["cmd": cmd]
if let o = ProcessInfo.processInfo.environment["ORION_PAINEL"] { pedido["origem"] = o }
var soltos: [String] = []
var anexos: [String] = [], mencionar: [String] = [], para: [String] = []
var json = false
var i = 0
while i < args.count {
  let a = args[i]
  func valor() -> String? { i + 1 < args.count ? { i += 1; return args[i] }() : nil }
  switch a {
  case "--json": json = true
  case "--linhas": pedido["linhas"] = Int(valor() ?? "") ?? 0
  case "--tempo": pedido["tempo"] = Double(valor() ?? "") ?? 600
  case "--painel": pedido["painel"] = valor()
  case "--esperar": pedido["esperar"] = true
  case "--enter": pedido["enter"] = true
  case "--abaixo": pedido["abaixo"] = true
  case "--focar": pedido["focar"] = true
  case "--fundo": pedido["fundo"] = true
  case "--forcar": pedido["forcar"] = true
  case "--tudo": pedido["tudo"] = true
  case "--atualizar": pedido["atualizar"] = true
  case "--padrao": pedido["padrao"] = true
  case "--claude": pedido["kind"] = "claude"
  case "--codex": pedido["kind"] = "codex"
  case "--gemini": pedido["kind"] = "gemini"
  case "--pai": pedido["pai"] = valor()
  case "--sub": pedido["pai"] = "eu"
  case "--papel": pedido["papel"] = valor()
  case "--nome": pedido["nome"] = valor()
  case "--avatar": pedido["avatar"] = valor()
  case "--retorno": pedido["retorno"] = true
  case "--maestro": pedido["maestro"] = true
  case "--filhos": pedido["filhos"] = true
  case "--todas": pedido["tudo"] = true
  case "--shell": pedido["kind"] = "shell"
  case "--pasta": pedido["pasta"] = valor()
  case "--conta": pedido["conta"] = valor()
  case "--workspace", "--grupo": pedido["workspace"] = valor()
  case "--titulo": pedido["titulo"] = valor()
  case "--comando": pedido["comando"] = valor()
  case "--mensagem": pedido["mensagem"] = valor()
  case "--cor": pedido["cor"] = valor()
  case "--simbolo": pedido["simbolo"] = valor()
  case "--ancora": pedido["ancora"] = valor()
  case "--estado": pedido["estado"] = valor()
  case "--largura": pedido["largura"] = Double(valor() ?? "") ?? 0
  case "--altura": pedido["altura"] = Double(valor() ?? "") ?? 0
  case "--valor": pedido["valor"] = Double(valor() ?? "") ?? 0
  case "--anexo", "--anexar": if let v = valor() { anexos.append(v) }
  case "--mencionar", "--contexto": if let v = valor() { mencionar.append(v) }
  case "--para": if let v = valor() { para.append(v) }
  case "--limpar": pedido["limpar"] = true
  case "--aceitar": pedido["aceitar"] = true
  case "--texto": pedido["texto"] = valor()
  case "--linha": pedido["linha"] = Int(valor() ?? "") ?? 0
  case "--coluna": pedido["coluna"] = Int(valor() ?? "") ?? 0
  default: soltos.append(a)
  }
  i += 1
}

if !anexos.isEmpty { pedido["anexos"] = anexos; pedido["cwd"] = FileManager.default.currentDirectoryPath }
if !mencionar.isEmpty { pedido["mencionar"] = mencionar }
if !para.isEmpty { pedido["para"] = para }

switch cmd {
case "ler", "esperar", "focar", "fechar", "dividir", "interromper", "reiniciar", "contexto", "filhos", "resultado", "personagem", "reabrir":
  if let s = soltos.first { pedido["painel"] = s }
case "liberar": pedido["porta"] = Int(soltos.first ?? "") ?? -1
case "compor": if let s = soltos.first { pedido["painel"] = s }; if soltos.count >= 2 { pedido["texto"] = soltos[1] }
case "marcar": if soltos.count >= 2 { pedido["painel"] = soltos[0]; pedido["marca"] = soltos[1] } else { pedido["marca"] = soltos.first ?? "" }
case "enviar": if soltos.count >= 2 { pedido["painel"] = soltos[0]; pedido["texto"] = soltos[1] } else if soltos.count == 1 { pedido["texto"] = soltos[0] }
case "rodar": pedido["comando"] = soltos.joined(separator: " ")
case "renomear": if soltos.count >= 2 { pedido["painel"] = soltos[0]; pedido["titulo"] = soltos[1] } else { pedido["titulo"] = soltos.first ?? "" }
case "notificar": pedido["texto"] = soltos.joined(separator: " ")
case "ui": pedido["alvo"] = soltos.first ?? ""; if soltos.count > 1 { pedido["secao"] = soltos[1] }
case "quadro": pedido["cmd"] = "ui"; pedido["alvo"] = "quadro"
case "workspace":
  // orion workspace <ação> [alvo] [nome]
  let acao = soltos.first ?? ""
  pedido["acao"] = acao
  let resto = Array(soltos.dropFirst())
  switch acao {
  case "novo", "criar": pedido["nome"] = resto.joined(separator: " ")
  case "renomear": if resto.count >= 2 { pedido["workspace"] = resto[0]; pedido["nome"] = resto[1...].joined(separator: " ") }
  default: if let r = resto.first, pedido["workspace"] == nil { pedido["workspace"] = r }
  }
case "agente": if pedido["mensagem"] == nil, !soltos.isEmpty { pedido["mensagem"] = soltos.joined(separator: " ") }
case "conta":
  if pedido["padrao"] != nil { if let c = soltos.first, pedido["conta"] == nil { pedido["conta"] = c } }
  else if soltos.count >= 2 { pedido["painel"] = soltos[0]; pedido["conta"] = soltos[1] }
case "depurar":
  pedido["alvo"] = soltos.first ?? ""
  if soltos.first == "uso", soltos.count >= 4 { pedido["conta"] = soltos[1]; pedido["h5"] = Double(soltos[2]) ?? 0; pedido["d7"] = Double(soltos[3]) ?? 0 }
  else if soltos.count >= 2 { pedido["painel"] = soltos[1] }
  if soltos.count >= 3, pedido["texto"] == nil { pedido["texto"] = soltos[2] }
default: break
}

let caminho = ProcessInfo.processInfo.environment["ORION_SOCKET"]
  ?? (NSHomeDirectory() + "/Library/Application Support/Orion Terminal/controle.sock")
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
var end = sockaddr_un()
end.sun_family = sa_family_t(AF_UNIX)
_ = withUnsafeMutablePointer(to: &end.sun_path) { p in caminho.withCString { strncpy(UnsafeMutableRawPointer(p).assumingMemoryBound(to: CChar.self), $0, 103) } }
let conectou = withUnsafePointer(to: &end) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
guard conectou == 0 else {
  FileHandle.standardError.write("orion: o Orion Terminal não está aberto (sem \(caminho))\n".data(using: .utf8)!)
  exit(2)
}
var dados = try! JSONSerialization.data(withJSONObject: pedido)
dados.append(10)
_ = dados.withUnsafeBytes { write(fd, $0.baseAddress, dados.count) }
var resposta = Data()
var buf = [UInt8](repeating: 0, count: 65536)
while true { let n = read(fd, &buf, buf.count); if n <= 0 { break }; resposta.append(buf, count: n) }
close(fd)

guard let r = try? JSONSerialization.jsonObject(with: resposta) as? [String: Any] else { print(String(decoding: resposta, as: UTF8.self)); exit(1) }
if json {
  let d = try! JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys])
  print(String(decoding: d, as: UTF8.self))
  exit((r["ok"] as? Bool) == true ? 0 : 1)
}
guard (r["ok"] as? Bool) == true else {
  FileHandle.standardError.write("orion: \(r["erro"] as? String ?? "erro")\n".data(using: .utf8)!)
  exit(1)
}

func duracao(_ s: Int) -> String {
  if s < 60 { return "\(s) s" }
  if s < 3600 { return "\(s / 60) min" }
  return "\(s / 3600) h \(String(format: "%02d", (s % 3600) / 60))"
}
func encurtar(_ p: String) -> String {
  let h = NSHomeDirectory()
  return p == h ? "~" : (p.hasPrefix(h + "/") ? "~" + p.dropFirst(h.count) : p)
}
func pct(_ v: Any?) -> String { (v as? Double).map { "\(Int($0.rounded()))%" } ?? "–" }

switch pedido["cmd"] as? String ?? cmd {
case "abas":
  var ultimo = ""
  for a in r["abas"] as? [[String: Any]] ?? [] {
    let ws = a["workspace"] as? String ?? ""
    if ws != ultimo { print("[\(ws)]"); ultimo = ws }
    print("\((a["ativa"] as? Bool) == true ? "▸" : " ") \(a["titulo"] as? String ?? "")")
    for p in a["paineis"] as? [[String: Any]] ?? [] {
      let voce = (p["voce"] as? Bool) == true ? "  ← você" : ""
      print("    \(p["id"] as? String ?? "")  \(p["estado"] as? String ?? "")  \(p["programa"] as? String ?? "")  \(p["pasta"] as? String ?? "")\(voce)")
    }
  }
case "workspaces":
  for w in r["workspaces"] as? [[String: Any]] ?? [] {
    let t = w["trabalhando"] as? Int ?? 0, e = w["esperando"] as? Int ?? 0
    var extra = "\(w["abas"] as? Int ?? 0) abas, \(w["agentes"] as? Int ?? 0) agentes"
    if t > 0 { extra += ", \(t) trabalhando" }
    if e > 0 { extra += ", \(e) esperando você" }
    print("\((w["ativo"] as? Bool) == true ? "▸" : " ") \(w["numero"] as? Int ?? 0)  \(w["nome"] as? String ?? "")  \(encurtar(w["pasta"] as? String ?? ""))  (\(extra))")
  }
case "workspace": if let n = r["nome"] as? String { print(n) }
case "agentes":
  let lista = r["agentes"] as? [[String: Any]] ?? []
  if lista.isEmpty { print("nenhum agente aberto") }
  for a in lista {
    let voce = (a["voce"] as? Bool) == true ? "  ← você" : ""
    let uso = (a["uso5h"] as? Double).map { " (5h \(Int($0.rounded()))%)" } ?? (a["uso7d"] as? Double).map { " (7d \(Int($0.rounded()))%)" } ?? ""
    let conta = (a["contaNome"] as? String).map { "  conta \($0)" + uso } ?? ""
    let quem = (a["personagem"] as? String).map { "\(a["avatar"] as? String ?? "") \($0)\((a["papel"] as? String).map { $0.isEmpty ? "" : " (\($0))" } ?? "")\((a["paiNome"] as? String).map { $0.isEmpty ? "" : " ↳\($0)" } ?? "")  " } ?? ""
    print("\(a["id"] as? String ?? "")  \(quem)\(a["tipo"] as? String ?? "")  \(a["estado"] as? String ?? "") há \(duracao(a["desde"] as? Int ?? 0))  [\(a["workspace"] as? String ?? "")]  \(a["titulo"] as? String ?? "")  \(encurtar(a["pasta"] as? String ?? ""))\(conta)\(voce)")
  }
case "ler", "contexto", "resultado": print(r["texto"] as? String ?? "")
case "filhos":
  let lista = r["agentes"] as? [[String: Any]] ?? []
  if lista.isEmpty { print("nenhum subagente") }
  for a in lista {
    print("\(a["id"] as? String ?? "")  \(a["avatar"] as? String ?? "") \(a["personagem"] as? String ?? "")\((a["papel"] as? String).map { $0.isEmpty ? "" : " (\($0))" } ?? "")  \(a["tipo"] as? String ?? "")  \(a["estado"] as? String ?? "") há \(duracao(a["desde"] as? Int ?? 0))  \(a["titulo"] as? String ?? "")")
  }
case "personagem": print("\(r["personagem"] as? String ?? "")\((r["papel"] as? String).map { $0.isEmpty ? "" : " (\($0))" } ?? "")  @\(r["apelido"] as? String ?? "")")
case "fechados":
  let lista = r["fechados"] as? [[String: Any]] ?? []
  if lista.isEmpty { print("nenhum agente fechado há pouco") }
  for f in lista {
    print("\(f["numero"] as? Int ?? 0)  \(f["tipo"] as? String ?? "")  \(f["personagem"] as? String ?? "")  \(f["titulo"] as? String ?? "")  [\(f["workspace"] as? String ?? "")]  \(encurtar(f["pasta"] as? String ?? ""))  há \(duracao(f["ha"] as? Int ?? 0))  \((f["sessao"] as? String ?? "").isEmpty ? "(última conversa da pasta)" : "(mesma conversa)")")
  }
case "reabrir": print(r["painel"] as? String ?? "")
case "portas":
  let lista = r["portas"] as? [[String: Any]] ?? []
  if lista.isEmpty { print("nenhuma porta em escuta\(pedido["tudo"] == nil ? " nos painéis do Orion (use --todas para o Mac inteiro)" : "")") }
  for x in lista {
    let dono = (x["painel"] as? String ?? "").isEmpty ? "(fora do Orion)" : "\(x["painel"] as? String ?? "")  [\(x["workspace"] as? String ?? "")] \(x["titulo"] as? String ?? "")"
    print(":\(x["porta"] as? Int ?? 0)  \(x["processo"] as? String ?? "")  pid \(x["pid"] as? Int ?? 0)  \(dono)")
  }
case "liberar":
  for e in r["encerrados"] as? [[String: Any]] ?? [] { print("porta \(r["porta"] as? Int ?? 0) liberada: encerrei \(e["processo"] as? String ?? "") (pid \(e["pid"] as? Int ?? 0))") }
case "compor":
  let n = (r["anexos"] as? [[String: Any]] ?? []).count
  print("rascunho no compose de \(r["painel"] as? String ?? "")\(n > 0 ? " (\(n) anexo\(n == 1 ? "" : "s"))" : "")")
case "marcar": print((r["marca"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "sem marca")
case "memoria":
  print("Orion Terminal: \(r["app"] as? Int ?? 0) MB · terminais e agentes: \(r["paineis"] as? Int ?? 0) MB")
  for x in r["lista"] as? [[String: Any]] ?? [] {
    print("  \(x["id"] as? String ?? "")  \(x["mb"] as? Int ?? 0) MB  \(x["processos"] as? Int ?? 0) proc  \(x["tipo"] as? String ?? "")  [\(x["workspace"] as? String ?? "")]  \(x["titulo"] as? String ?? "")")
  }
case "rodar":
  if let s = r["saida"] as? String { print(s) ; exit(Int32((r["codigo"] as? Int) ?? 0)) }
  print(r["painel"] as? String ?? "")
case "nova", "dividir", "agente": print(r["painel"] as? String ?? "")
case "esperar":
  if let lista = r["agentes"] as? [[String: Any]] {
    for a in lista { print("\(a["painel"] as? String ?? "")  \(a["personagem"] as? String ?? "")  \(a["estado"] as? String ?? "")") }
  } else { print(r["estado"] as? String ?? ""); if let c = r["codigo"] as? Int { exit(Int32(c)) } }
case "versao":
  let d = r["disponivel"] as? String
  print("Orion Terminal \(r["versao"] as? String ?? "?")" + (d.map { " · versão \($0) disponível (orion atualizar)" } ?? " · última versão"))
case "atualizar":
  print(r["mensagem"] as? String ?? "")
case "contas":
  for c in r["contas"] as? [[String: Any]] ?? [] {
    print("\((c["padrao"] as? Bool) == true ? "★" : " ") \(c["id"] as? String ?? "")  \(c["nome"] as? String ?? "")  \(c["email"] as? String ?? "")\((c["logado"] as? Bool) == true ? "" : "  (sem login)")")
  }
case "uso":
  if r["claude"] as? String != "ligado" { print("(uso do Claude ainda não ligado — ligue em Ajustes → Contas e uso, ou no cartão que abre ao passar o mouse no ícone)") }
  for c in r["contas"] as? [[String: Any]] ?? [] {
    var linha = "\((c["padrao"] as? Bool) == true ? "★" : " ") \(c["id"] as? String ?? "")  \(c["nome"] as? String ?? "")  5h \(pct(c["pct5h"]))  7d \(pct(c["pct7d"]))"
    if let e = c["erro"] as? String { linha += "  (\(e))" }
    if (c["logado"] as? Bool) != true { linha += "  (sem login)" }
    print(linha)
  }
case "estado":
  print("Orion Terminal \(r["versao"] as? String ?? "") · \(r["workspaces"] as? Int ?? 0) workspaces · \(r["abas"] as? Int ?? 0) abas · \(r["paineis"] as? Int ?? 0) painéis vivos · na tela: \(r["workspace"] as? String ?? "")")
case "depurar":
  if let a = r["ancoras"] { print(a) }
  else if let d = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) { print(String(decoding: d, as: UTF8.self)) }
default: break
}
