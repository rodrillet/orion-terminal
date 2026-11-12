import SwiftUI
import AppKit
import Observation

// Diálogos do próprio app (no lugar dos alertas do macOS): confirmar, perguntar um texto,
// novo workspace, novo agente, nova conta. Aparecem por cima da janela em que a ação começou.
// Nada aqui é síncrono — quem pede passa o que fazer depois (`entao`).

@MainActor @Observable
final class Dialogo: Identifiable {
  enum Tipo { case confirmar, texto, workspace, agente, conta, personagem }
  let id = UUID()
  let tipo: Tipo
  var titulo: String
  var texto: String
  var ok: String
  var cancelar: String? = "Cancelar"      // nil = só o botão principal (aviso)
  var destrutivo = false
  var simbolo: String?
  var programa: String?                    // ícone real do app (claude, codex, shell)
  var emAjustes = false
  // Campo de texto (renomear, nome da conta…)
  var valor = ""
  var dica = ""
  var permiteVazio = false
  // Workspace
  var pasta = NSHomeDirectory()
  var cor = Cor.paletaGrupos[0]
  var simboloWs = "folder"
  // Agente
  var kind = "claude"
  var conta = ""
  var workspace = ""
  var mensagem = ""
  var pastaEscolhida = false               // a pasta foi trocada à mão (senão segue o workspace)
  // Personagem (novo agente e edição)
  var nomePersona = ""
  var avatar = "🦊"
  var papel = ""
  var descricao = ""
  var pai: String?                         // maestro deste subagente

  @ObservationIgnored var aoConfirmar: (Dialogo) -> Void = { _ in }
  @ObservationIgnored var aoCancelar: (() -> Void)?

  init(_ tipo: Tipo, titulo: String, texto: String = "", ok: String = "OK") {
    self.tipo = tipo; self.titulo = titulo; self.texto = texto; self.ok = ok
  }

  var valido: Bool {
    switch tipo {
    case .texto, .conta: return permiteVazio || !valor.trimmingCharacters(in: .whitespaces).isEmpty
    case .personagem: return !nomePersona.trimmingCharacters(in: .whitespaces).isEmpty
    default: return true
    }
  }
}

extension Loja {
  func mostrar(_ d: Dialogo) {
    let del = NSApp.delegate as? Delegado
    if let j = del?.janelaAjustes, j.isVisible, NSApp.keyWindow === j || d.emAjustes { d.emAjustes = true } else { d.emAjustes = false }
    if !d.emAjustes, let j = janela, !j.isVisible, !Armazem.semFoco { j.makeKeyAndOrderFront(nil) }
    paletaAberta = false
    fecharUso()
    sugestoes.fechar()
    dialogo = d
  }

  func confirmarDialogo() {
    guard let d = dialogo, d.valido else { return }
    dialogo = nil
    d.aoConfirmar(d)
    devolverFoco()
  }

  func cancelarDialogo() {
    guard let d = dialogo else { return }
    dialogo = nil
    d.aoCancelar?()
    devolverFoco()
  }

  /// Depois de um diálogo, o teclado volta para o terminal ativo (se nada mais pegou o foco).
  func devolverFoco() {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.dialogo == nil, !self.quadroAberto, !self.paletaAberta, let j = self.janela, j.isKeyWindow else { return }
      if j.firstResponder is NSTextView { return }
      if let v = self.painelAtivo?.view { j.makeFirstResponder(v) }
    }
  }

  /// Pergunta de sim ou não. `entao` roda se a pessoa confirmar; `senao`, se cancelar.
  func confirmar(_ titulo: String, _ texto: String, _ ok: String, destrutivo: Bool = false, simbolo: String? = nil,
                 senao: (() -> Void)? = nil, entao: @escaping () -> Void) {
    let d = Dialogo(.confirmar, titulo: titulo, texto: texto, ok: ok)
    d.destrutivo = destrutivo
    d.simbolo = simbolo ?? (destrutivo ? "exclamationmark.triangle.fill" : nil)
    d.aoConfirmar = { _ in entao() }
    d.aoCancelar = senao
    mostrar(d)
  }

  /// Aviso com um botão só.
  func avisar(_ titulo: String, _ texto: String, simbolo: String = "info.circle.fill") {
    let d = Dialogo(.confirmar, titulo: titulo, texto: texto, ok: "OK")
    d.cancelar = nil
    d.simbolo = simbolo
    mostrar(d)
  }

  /// Pede um texto de uma linha.
  func perguntar(_ titulo: String, valor: String = "", texto: String = "", ok: String = "OK", dica: String = "",
                 permiteVazio: Bool = false, simbolo: String? = "pencil", entao: @escaping (String) -> Void) {
    let d = Dialogo(.texto, titulo: titulo, texto: texto, ok: ok)
    d.valor = valor; d.dica = dica; d.permiteVazio = permiteVazio; d.simbolo = simbolo
    d.aoConfirmar = { d in entao(d.valor.trimmingCharacters(in: .whitespaces)) }
    mostrar(d)
  }

  func renomear(_ a: Aba) {
    perguntar("Renomear a aba", valor: a.titulo ?? titulo(a), texto: "Vazio volta ao nome automático (a pasta ou a tarefa do agente).",
              ok: "Renomear", dica: "Nome da aba", permiteVazio: true) { [weak self] n in
      a.titulo = n.isEmpty ? nil : n
      self?.salvarDepois()
    }
  }

  func renomear(_ w: Workspace) {
    perguntar("Renomear o workspace", valor: w.nome, ok: "Renomear", dica: "Nome do workspace") { [weak self] n in
      w.nome = n
      self?.salvarDepois()
    }
  }

  /// Seletor de pasta do sistema (o único diálogo que continua sendo o do macOS).
  func escolherUmaPasta(inicial: String, mensagem: String) -> String? {
    let p = NSOpenPanel()
    p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false; p.canCreateDirectories = true
    p.directoryURL = URL(fileURLWithPath: (inicial as NSString).expandingTildeInPath)
    p.prompt = "Usar esta pasta"
    p.message = mensagem
    return p.runModal() == .OK ? p.url?.path : nil
  }

  func escolherPasta(_ w: Workspace) {
    if let dir = escolherUmaPasta(inicial: w.pasta, mensagem: "Pasta do workspace “\(w.nome)”: novos terminais e agentes abrem nela.") {
      w.pasta = dir
      salvarDepois()
    }
  }

  /// Nome, pasta, cor e símbolo num diálogo só; cria o workspace (vazio, pronto para abrir agentes).
  /// `entao` recebe o workspace criado (padrão: ir para ele).
  func novoWorkspacePerguntando(nome: String = "", pasta: String? = nil, entao: ((Workspace) -> Void)? = nil) {
    let d = Dialogo(.workspace, titulo: "Novo workspace",
                    texto: "Um workspace é um projeto ou cliente: tem a sua pasta, os seus terminais e os seus agentes.", ok: "Criar workspace")
    d.valor = nome
    d.dica = "Nome (vazio = o nome da pasta)"
    d.pasta = pasta ?? workspaceAtivo?.pasta ?? NSHomeDirectory()
    let usadas = Set(workspaces.map(\.cor))
    d.cor = Cor.paletaGrupos.first { !usadas.contains($0) } ?? Cor.paletaGrupos[workspaces.count % Cor.paletaGrupos.count]
    d.aoConfirmar = { [weak self] d in
      guard let self else { return }
      var n = d.valor.trimmingCharacters(in: .whitespaces)
      if n.isEmpty { n = d.pasta == NSHomeDirectory() ? "Workspace \(self.workspaces.count + 1)" : (d.pasta as NSString).lastPathComponent }
      let w = self.criarWorkspace(n, pasta: d.pasta, cor: d.cor, simbolo: d.simboloWs)
      if let entao { entao(w) } else { self.ativarWorkspace(w) }
    }
    mostrar(d)
  }

  /// Novo agente com tudo à vista: ferramenta, conta, personagem, workspace, pasta e a primeira
  /// tarefa (que dá o nome a ele). Com `pai`, nasce como subagente daquele maestro.
  func novoAgentePerguntando(kind: String = "claude", conta: String? = nil, workspace: String? = nil, pai: String? = nil) {
    let maestro = pai.flatMap { acharPainel($0) }
    let d = Dialogo(.agente, titulo: maestro.map { "Novo subagente de \($0.persona?.nome ?? $0.titulo)" } ?? "Novo agente", ok: "Abrir")
    d.kind = kind
    d.conta = conta ?? contaPadrao(kind)?.id ?? ""
    let w = workspace.flatMap { self.workspace($0) } ?? maestro?.aba.flatMap { self.workspace(de: $0) } ?? workspaceAtivo
    d.workspace = w?.id ?? ""
    d.pasta = maestro?.cwd ?? w?.pasta ?? NSHomeDirectory()
    d.pai = pai
    let p = novaPersona(papel: pai != nil ? "Subagente" : "")
    d.nomePersona = p.nome; d.avatar = p.avatar; d.cor = p.cor; d.papel = p.papel
    d.aoConfirmar = { [weak self] d in
      guard let self else { return }
      self.abrirQuadro(false)
      var comando = self.comandoDoTipo(d.kind) ?? d.kind
      let m = d.mensagem.trimmingCharacters(in: .whitespacesAndNewlines)
      if !m.isEmpty { comando += " '" + m.replacingOccurrences(of: "'", with: "'\\''") + "'" }
      let c = self.conta(d.conta).flatMap { $0.tipo == d.kind ? $0.id : nil }
      let nome = d.nomePersona.trimmingCharacters(in: .whitespaces)
      let persona = Persona(nome: nome.isEmpty ? p.nome : nome, avatar: d.avatar, cor: d.cor, papel: d.papel.trimmingCharacters(in: .whitespaces))
      let a = self.criarAba(kind: d.kind, cwd: d.pasta, workspace: d.workspace.isEmpty ? nil : d.workspace, conta: c,
                            comando: comando, persona: persona, pai: d.pai, tarefa: m.isEmpty ? nil : m)
      if !m.isEmpty, let x = self.painelPrincipal(a) { x.enviadas.append(Conversa.Enviada(texto: m, em: Date(), linha: 0)) }
    }
    mostrar(d)
  }

  /// Edita o personagem de um agente: nome, avatar, cor e papel.
  func editarPersonagem(_ p: Painel) {
    let atual = p.persona ?? novaPersona()
    let d = Dialogo(.personagem, titulo: "Personagem", texto: "Quem é este agente na equipe. O nome também é como você o menciona no compose (@\(p.apelido)).", ok: "Salvar")
    d.nomePersona = atual.nome; d.avatar = atual.avatar; d.cor = atual.cor; d.papel = atual.papel; d.descricao = atual.descricao
    d.kind = p.tipoAgente ?? "claude"
    d.aoConfirmar = { [weak self, weak p] d in
      p?.persona = Persona(nome: d.nomePersona.trimmingCharacters(in: .whitespaces), avatar: d.avatar, cor: d.cor, papel: d.papel.trimmingCharacters(in: .whitespaces),
                           descricao: d.descricao.trimmingCharacters(in: .whitespacesAndNewlines))
      self?.salvarDepois()
    }
    mostrar(d)
  }

  /// Nova conta de uma ferramenta: nome e cor; ao criar, abre uma aba nela para o login.
  func novaContaPerguntando(_ tipo: String) {
    let nome = nomeFerramenta(tipo)
    let d = Dialogo(.conta, titulo: "Nova conta do \(nome)",
                    texto: "Cada conta é uma pasta de configuração própria; ajustes, skills e plugins da Principal são compartilhados. Ao criar, uma aba abre nessa conta para você fazer o login.",
                    ok: "Criar e fazer login")
    d.programa = tipo
    d.kind = tipo
    d.dica = "Ex.: Trabalho, Conta 2, Cliente X"
    d.cor = Cor.paletaGrupos[(contas.count + 2) % Cor.paletaGrupos.count]
    d.emAjustes = true
    d.aoConfirmar = { [weak self] d in
      guard let self else { return }
      let n = d.valor.trimmingCharacters(in: .whitespaces)
      do {
        let c = try Contas.criar(tipo: tipo, nome: n, cor: d.cor, compartilhar: true)
        self.carregarContas()
        let id = c["id"] as? String ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          // Claude e Gemini pedem o login ao abrir; o Codex tem um comando próprio.
          let cmd = tipo == "codex" ? "\(self.comandoDoTipo("codex") ?? "codex") login" : self.comandoDoTipo(tipo)
          let a = self.criarAba(kind: tipo, conta: id, comando: cmd, titulo: "Login · \(n)")
          a.definirConta(tipo, id)
          (NSApp.delegate as? Delegado)?.janelaAjustes?.close()
        }
      } catch {
        self.avisar("Não consegui criar a conta", error.localizedDescription, simbolo: "exclamationmark.triangle.fill")
      }
    }
    mostrar(d)
  }
}

// MARK: - Views

/// Aviso curto ("Copiado") que sobe do rodapé da janela.
struct CamadaAviso: View {
  @Bindable var loja: Loja
  var body: some View {
    VStack {
      Spacer()
      if let a = loja.aviso {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(Cor.verde)
          Text(a.texto).foregroundStyle(Cor.texto)
        }
        .font(F.ui(12, .medium))
        .padding(.horizontal, 12).frame(height: 30)
        .cartaoFlutuante(raio: 15)
        .padding(.bottom, 56)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .id(a.id)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(false)
    .animation(.easeOut(duration: 0.16), value: loja.aviso?.id)
  }
}

/// Camada do diálogo: véu + cartão centralizado. Uma por janela (principal e ajustes).
struct CamadaDialogo: View {
  @Bindable var loja: Loja
  let emAjustes: Bool

  var body: some View {
    ZStack {
      if let d = loja.dialogo, d.emAjustes == emAjustes {
        Cor.veu.onTapGesture { loja.cancelarDialogo() }.transition(.opacity)
        CartaoDialogo(loja: loja, d: d)
          .padding(20)
          .transition(.scale(scale: 0.97).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeOut(duration: 0.14), value: loja.dialogo?.id)
  }
}

struct CartaoDialogo: View {
  @Bindable var loja: Loja
  @Bindable var d: Dialogo
  @FocusState private var foco: Bool

  /// Confirmação/aviso: cartão pequeno, sem campos.
  private var simples: Bool { d.tipo == .confirmar }

  private var larguraMaxima: CGFloat {
    switch d.tipo {
    case .agente, .workspace, .personagem: return 500
    case .confirmar: return 360
    default: return 420
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: simples ? 16 : 14) {
      HStack(alignment: .top, spacing: 12) {
        if let p = d.programa {
          IconePrograma(processo: p, tamanho: 32)
        } else if let s = d.simbolo {
          Image(systemName: s).font(.system(size: 14, weight: .semibold))
            .foregroundStyle(d.destrutivo ? Cor.vermelho : Cor.acento)
            .frame(width: 30, height: 30)
            .background(Circle().fill((d.destrutivo ? Cor.vermelho : Cor.acento).opacity(0.14)))
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(d.titulo).font(F.ui(14, .semibold)).foregroundStyle(Cor.texto).fixedSize(horizontal: false, vertical: true)
          if !d.texto.isEmpty {
            Text(d.texto).font(F.ui(12)).foregroundStyle(Cor.texto2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.top, d.simbolo != nil || d.programa != nil ? 2 : 0)
        Spacer(minLength: 0)
      }
      if !simples {
        // Cabe na janela? Senão os campos rolam (janela pequena, fonte grande).
        ViewThatFits(in: .vertical) {
          campos
          ScrollView { campos.padding(.trailing, 6) }.scrollIndicators(.visible)
        }
      }
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        if let c = d.cancelar { BotaoDialogo(titulo: c, atalho: simples ? "" : "esc", compacto: simples) { loja.cancelarDialogo() } }
        BotaoDialogo(titulo: d.tipo == .agente ? "Abrir \(d.nomePersona.isEmpty ? nomeFerramenta(d.kind) : d.nomePersona)" : d.ok,
                     atalho: simples ? "" : "↩", primario: true, destrutivo: d.destrutivo, desligado: !d.valido, compacto: simples) { loja.confirmarDialogo() }
      }
    }
    .padding(simples ? 16 : 20)
    .frame(maxWidth: larguraMaxima)
    .fixedSize(horizontal: false, vertical: true)          // nunca estica até a altura da janela
    .cartaoFlutuante(raio: R.cartao + 4)
    .onTapGesture { }
    .onAppear { DispatchQueue.main.async { foco = true } }
  }

  @ViewBuilder var campos: some View {
    switch d.tipo {
    case .confirmar: EmptyView()
    case .texto: CampoDialogo(texto: $d.valor, dica: d.dica).focused($foco)
    case .workspace: camposWorkspace
    case .agente: camposAgente
    case .conta: camposConta
    case .personagem: camposPersonagem
    }
  }

  // MARK: Personagem

  @ViewBuilder var camposPersonagem: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AvatarPersona(persona: Persona(nome: d.nomePersona, avatar: d.avatar, cor: d.cor, papel: d.papel), tamanho: 52, ferramenta: d.kind, fixo: true)
        VStack(spacing: 8) {
          CampoDialogo(texto: $d.nomePersona, dica: "Nome").focused($foco)
          CampoDialogo(texto: $d.papel, dica: "Papel — o que ele faz (Dev, Revisor, Pesquisa…)")
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
       HStack(spacing: 5) {
        ForEach(Persona.papeis, id: \.self) { p in
          Text(p).font(F.ui(11, .medium)).foregroundStyle(d.papel == p ? Cor.texto : Cor.texto3).fixedSize()
            .padding(.horizontal, 8).frame(height: F.m(22))
            .background(Capsule().fill(d.papel == p ? Cor.vidro2 : Cor.vidro))
            .contentShape(Capsule()).onTapGesture { d.papel = p }
            .help("Papel: \(p)\(Self.dicaAcessorio(p))")
        }
       }
      }
      Rotulo("Descrição — o que ele faz e quando mandar trabalho para ele (os colegas leem em orion equipe)")
      CampoDialogo(texto: $d.descricao, dica: "Ex.: cuida do front-end em React; mande telas e bugs de interface", linhas: 3)
      Rotulo("Avatar")
      let atual = Mascote.forma(Persona(nome: d.nomePersona, avatar: d.avatar, cor: d.cor))
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
        ForEach(Mascote.formas, id: \.self) { a in
          DesenhoMascote(forma: a, cor: d.cor, tamanho: 34, humor: atual == a ? .atento : .normal,
                         acessorio: Acessorio.de(papel: d.papel, maestro: false))
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(atual == a ? Color(hex: d.cor).opacity(0.18) : Cor.vidro))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(atual == a ? Color(hex: d.cor).opacity(0.8) : .clear))
            .contentShape(Rectangle()).onTapGesture { d.avatar = a }.help(Mascote.nomes[a] ?? a)
        }
      }
      Rotulo("Cor")
      HStack(spacing: 8) {
        ForEach(Cor.paletaGrupos, id: \.self) { c in
          Circle().fill(Color(hex: c)).frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Cor.texto, lineWidth: d.cor == c ? 2 : 0).padding(-3))
            .contentShape(Circle()).onTapGesture { d.cor = c }.help(nomeCor(c))
        }
      }
    }
  }

  /// O papel também veste o mascote: mostra qual acessório ele ganha.
  static func dicaAcessorio(_ papel: String) -> String {
    switch Acessorio.de(papel: papel, maestro: false) {
    case .coroa: return " — ganha a coroa"
    case .oculos: return " — ganha óculos"
    case .antena: return " — ganha uma antena"
    case .fones: return " — ganha fones"
    case .lupa: return " — ganha uma lupa"
    case .boina: return " — ganha uma boina"
    case .nenhum: return ""
    }
  }

  // MARK: Workspace

  @ViewBuilder var camposWorkspace: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: d.simboloWs).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(hex: d.cor))
          .frame(width: 36, height: 36)
          .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: d.cor).opacity(0.22)))
        CampoDialogo(texto: $d.valor, dica: d.dica).focused($foco)
      }
      LinhaPasta(loja: loja, pasta: $d.pasta, mensagem: "Pasta do workspace: novos terminais e agentes abrem nela.")
      Rotulo("Cor")
      HStack(spacing: 8) {
        ForEach(Cor.paletaGrupos, id: \.self) { c in
          Circle().fill(Color(hex: c)).frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Cor.texto, lineWidth: d.cor == c ? 2 : 0).padding(-3))
            .contentShape(Circle()).onTapGesture { d.cor = c }.help(nomeCor(c))
        }
      }
      Rotulo("Símbolo")
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 12), spacing: 6) {
        ForEach(Workspace.simbolos, id: \.self) { s in
          Image(systemName: s).font(.system(size: 13, weight: .medium))
            .foregroundStyle(d.simboloWs == s ? Color(hex: d.cor) : Cor.texto2)
            .frame(maxWidth: .infinity).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(d.simboloWs == s ? Color(hex: d.cor).opacity(0.18) : Cor.vidro))
            .contentShape(Rectangle()).onTapGesture { d.simboloWs = s }.help("Símbolo: \(s)")
        }
      }
    }
  }

  // MARK: Agente

  @ViewBuilder var camposAgente: some View {
    let contas = loja.contas(d.kind)
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        ForEach(loja.ferramentas) { f in
          let t = f.id
          Button {
            d.kind = t
            d.conta = loja.contaPadrao(t)?.id ?? ""
          } label: {
            HStack(spacing: 7) {
              IconePrograma(processo: t, tamanho: 22)
              Text(f.nome).font(F.ui(13, .medium)).foregroundStyle(Cor.texto).lineLimit(1)
              Spacer(minLength: 0)
              if d.kind == t { Image(systemName: "checkmark.circle.fill").foregroundStyle(Cor.acento) }
            }
            .padding(.horizontal, 9).frame(maxWidth: .infinity).frame(height: F.m(38))
            .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(d.kind == t ? Cor.acento.opacity(0.12) : Cor.vidro))
            .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(d.kind == t ? Cor.acento.opacity(0.55) : Cor.linha))
            .contentShape(Rectangle())
          }.buttonStyle(.plain).help("Abrir com o \(f.nomeLongo)")
        }
      }
      Rotulo("Primeira tarefa — dá o nome ao agente (opcional)")
      CampoDialogo(texto: $d.mensagem, dica: "Ex.: revisar a landing do cliente e listar o que falta", linhas: 3).focused($foco)
      Rotulo("Personagem")
      HStack(spacing: 8) {
        AvatarPersona(persona: Persona(nome: d.nomePersona, avatar: d.avatar, cor: d.cor), tamanho: 34, ferramenta: d.kind, fixo: true)
          .contentShape(Rectangle())
          .onTapGesture { d.avatar = Mascote.proxima(Mascote.forma(Persona(nome: d.nomePersona, avatar: d.avatar, cor: d.cor))) }
          .help("Clique para trocar a forma")
        CampoDialogo(texto: $d.nomePersona, dica: "Nome")
        CampoDialogo(texto: $d.papel, dica: "Papel (Dev, Revisor…)")
      }
      if contas.count > 1 {
        Rotulo("Conta")
        FlowContas(loja: loja, contas: contas, escolhida: $d.conta)
      }
      Rotulo("Onde")
      HStack(spacing: 8) {
        Menu {
          ForEach(loja.workspaces) { w in
            Button { d.workspace = w.id; if !d.pastaEscolhida { d.pasta = w.pasta } } label: { Label(w.nome, systemImage: w.simbolo) }
          }
        } label: {
          HStack(spacing: 7) {
            if let w = loja.workspace(d.workspace) { SimboloWorkspace(ws: w, tamanho: 20); Text(w.nome).font(F.ui(12.5, .medium)).foregroundStyle(Cor.texto).lineLimit(1) }
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Cor.texto3)
          }
          .padding(.horizontal, 9).frame(height: F.m(32))
          .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.vidro))
          .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(Cor.linha))
          .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        LinhaPasta(loja: loja, pasta: $d.pasta, mensagem: "Pasta em que o agente começa.") { d.pastaEscolhida = true }
      }
    }
  }

  // MARK: Conta

  @ViewBuilder var camposConta: some View {
    VStack(alignment: .leading, spacing: 12) {
      CampoDialogo(texto: $d.valor, dica: d.dica).focused($foco)
      Rotulo("Cor")
      HStack(spacing: 8) {
        ForEach(Cor.paletaGrupos, id: \.self) { c in
          Circle().fill(Color(hex: c)).frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Cor.texto, lineWidth: d.cor == c ? 2 : 0).padding(-3))
            .contentShape(Circle()).onTapGesture { d.cor = c }.help(nomeCor(c))
        }
      }
    }
  }
}

struct Rotulo: View {
  let texto: String
  init(_ t: String) { texto = t }
  var body: some View {
    Text(texto).font(F.ui(11, .medium)).foregroundStyle(Cor.texto3)
  }
}

/// Contas como botões (uma linha que quebra se não couber).
struct FlowContas: View {
  let loja: Loja
  let contas: [Conta]
  @Binding var escolhida: String
  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
      ForEach(contas) { c in
        let ativo = c.id == escolhida
        let uso = loja.usoVisivel(c.id)?.resumo
        Button { escolhida = c.id } label: {
          HStack(spacing: 6) {
            Circle().fill(Color(hex: c.cor)).frame(width: 8, height: 8)
            Text(c.nome).font(F.ui(12, ativo ? .semibold : .regular)).foregroundStyle(Cor.texto).lineLimit(1)
            Spacer(minLength: 0)
            if let uso { Text("\(Int(uso.pct.rounded()))%").font(F.ui(11)).monospacedDigit().foregroundStyle(uso.pct >= 60 ? Cor.uso(uso.pct) : Cor.texto3) }
          }
          .padding(.horizontal, 9).frame(height: F.m(30))
          .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(ativo ? Cor.acento.opacity(0.12) : Cor.vidro))
          .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(ativo ? Cor.acento.opacity(0.55) : Cor.linha))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(c.email.isEmpty ? c.nome : "\(c.nome) · \(c.email)")
      }
    }
  }
}

/// Caminho da pasta + botão para trocar.
struct LinhaPasta: View {
  let loja: Loja
  @Binding var pasta: String
  let mensagem: String
  var aoTrocar: (() -> Void)? = nil
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Cor.texto3)
      Text(Loja.encurtar(pasta)).font(F.mono(11.5)).foregroundStyle(Cor.texto2).lineLimit(1).truncationMode(.head)
      Spacer(minLength: 4)
      Button("Escolher…") {
        if let dir = loja.escolherUmaPasta(inicial: pasta, mensagem: mensagem) { pasta = dir; aoTrocar?() }
      }
      .buttonStyle(.plain).font(F.ui(11.5, .medium)).foregroundStyle(Cor.acento)
    }
    .padding(.horizontal, 10).frame(height: F.m(32))
    .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.vidro))
    .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(Cor.linha))
  }
}

/// Campo de texto no visual do app.
struct CampoDialogo: View {
  @Binding var texto: String
  var dica = ""
  var linhas = 1
  @FocusState private var focado: Bool
  var body: some View {
    Group {
      if linhas > 1 {
        TextField("", text: $texto, prompt: Text(dica).foregroundStyle(Cor.texto4), axis: .vertical).lineLimit(1...linhas)
      } else {
        TextField("", text: $texto, prompt: Text(dica).foregroundStyle(Cor.texto4))
      }
    }
    .textFieldStyle(.plain).font(F.ui(13)).foregroundStyle(Cor.texto)
    .focused($focado)
    .padding(.horizontal, 10).padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: F.m(34), alignment: .leading)
    .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(Cor.vidro))
    .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(focado ? Cor.acento.opacity(0.7) : Cor.linhaForte, lineWidth: focado ? 1.5 : 1))
  }
}

struct BotaoDialogo: View {
  let titulo: String
  var atalho = ""
  var primario = false
  var destrutivo = false
  var desligado = false
  var compacto = false
  let acao: () -> Void
  @Estado private var sobre = false
  var body: some View {
    let fundo: Color = primario ? (destrutivo ? Cor.vermelho : Cor.acento) : Cor.vidro2
    let frente: Color = primario ? (destrutivo ? .white : Cor.sobreAcento) : Cor.texto
    Button(action: acao) {
      HStack(spacing: 7) {
        Text(titulo).font(F.ui(compacto ? 12.5 : 13, .medium))
        if !atalho.isEmpty { Text(atalho).font(F.ui(11)).opacity(0.6) }
      }
      .foregroundStyle(frente)
      .padding(.horizontal, compacto ? 12 : 14).frame(minWidth: compacto ? 72 : 0).frame(height: F.m(compacto ? 28 : 34))
      .background(RoundedRectangle(cornerRadius: R.controle, style: .continuous).fill(fundo).brightness(sobre ? (Cor.claro ? -0.04 : 0.06) : 0))
      .overlay(RoundedRectangle(cornerRadius: R.controle, style: .continuous).strokeBorder(primario ? Color.clear : Cor.linha))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).onHover { sobre = $0 }
    .disabled(desligado).opacity(desligado ? 0.45 : 1)
  }
}
