<p align="center"><img src="https://raw.githubusercontent.com/rodrillet/orion-terminal/main/docs/og-image.png" alt="Orion Terminal — orquestre agentes num terminal feito para o Mac" width="100%"></p>

# Orion Terminal

**Terminal nativo para macOS feito para orquestrar agentes de IA.** Claude Code, Codex e Gemini CLI
rodam lado a lado, cada um com a sua conta, organizados em workspaces — um por projeto ou cliente.
Um agente "maestro" pode criar subagentes, acompanhar o trabalho deles e receber o resultado de volta.
Tudo em AppKit + SwiftUI + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm): leve (CPU parada
em 0% e ~40–90 MB de memória), com vidro de verdade, temas claros e escuros e um CLI (`orion`) para
que os próprios agentes operem o terminal.

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/rodrillet/orion-terminal/main/install.sh | bash
```

O instalador baixa o último [release](https://github.com/rodrillet/orion-terminal/releases), confere
o SHA-256, coloca o app em **Aplicativos**, libera a abertura no macOS e instala o comando `orion` em
`~/.local/bin`. Não pede senha. Rodar de novo atualiza.

**Requisitos:** Mac com Apple Silicon (M1 ou mais novo) e macOS 15 (Sequoia) ou mais novo. Para os
agentes, tenha instalado o que for usar: [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[Codex CLI](https://github.com/openai/codex) e/ou [Gemini CLI](https://github.com/google-gemini/gemini-cli).

<details>
<summary>Instalar sem o terminal</summary>

1. Baixe `Orion-Terminal-<versão>.zip` no [último release](https://github.com/rodrillet/orion-terminal/releases/latest) e abra o zip.
2. Arraste o **Orion Terminal** para Aplicativos.
3. Na primeira vez o macOS avisa que não pôde verificar o desenvolvedor (o app não é da App Store nem
   assinado com certificado pago). Abra **Ajustes do Sistema → Privacidade e Segurança** e clique em
   **Abrir Mesmo Assim** ao lado de "Orion Terminal". Alternativa: `xattr -dr com.apple.quarantine "/Applications/Orion Terminal.app"`.
</details>

## Atualizações automáticas

Assim que uma versão nova é publicada aqui, todos os apps instalados percebem e se atualizam:

- o app consulta o release mais novo ao abrir, ao voltar para a frente (no máximo a cada 20 min) e a
  cada hora — com ETag, então uma consulta sem novidade não gasta o limite da API do GitHub;
- versão nova é **baixada em segundo plano**, conferida pelo SHA-256 publicado no release e pelo
  identificador e número de versão do pacote;
- aparece um aviso (notificação + botão no topo) e ela **entra sozinha quando você fecha o app** —
  ou na hora, com *Reiniciar e atualizar*. A troca do pacote volta atrás se algo falhar.

Em **Ajustes → Sobre e atualizações** dá para escolher *Automáticas*, *Só avisar* ou *Desligadas*.
Pelo terminal: `orion versao` e `orion atualizar`.

## Privacidade

O Orion Terminal não tem conta, servidor nem telemetria. As únicas conexões que ele faz são:

| Para onde | Quando | Por quê |
|---|---|---|
| `api.github.com` / `github.com` | ao verificar e baixar atualizações | ler o release mais novo (público, sem login) |
| `api.anthropic.com/api/oauth/usage` | só se você ligar "Uso do Claude" | mostrar o uso de 5 h e 7 dias da sua conta; o login é lido do Chaveiro do seu Mac e nunca sai dele para outro lugar |

O uso do Codex é lido dos arquivos locais das sessões dele. Contas ficam em
`~/Library/Application Support/Orion Terminal/perfis` (uma pasta por conta, via `CLAUDE_CONFIG_DIR`,
`CODEX_HOME` e `GEMINI_CLI_HOME`).

## O que tem

| Parte | Como funciona |
|---|---|
| **Agentes como personagens** | Cada agente tem nome, mascote, cor e papel (Rigel, Vega, Lyra…), além da ferramenta (Claude Code, Codex ou Gemini CLI) e da conta. O mascote é desenhado em vetor — oito formas (gota, bolha, nuvem, pílula, hexágono, flor, fantasma, losango) — e os olhos mudam com o estado: focados trabalhando, arregalados esperando você, fechados dormindo; um ponto no canto mostra o estado. Duplo clique no avatar (ou menu → Personagem…) edita. No compose e no CLI ele é chamado pelo nome: `@rigel`. |
| **Nome que diz o que ele faz** | O título do agente é a tarefa: a primeira mensagem (do compose, do diálogo ou de `--mensagem`) resumida, e depois o título que a própria ferramenta manda. “Nome · papel · conta” fica na linha de baixo. Renomear: ⇧⌘R ou duplo clique no título, no quadro. |
| **Maestro e subagentes** | Um agente cria outros (`orion agente --pai $ORION_PAINEL …`, ou menu → Novo subagente…). Os filhos aparecem recuados sob o maestro na barra lateral e dentro do cartão dele no quadro. O maestro acompanha com `orion filhos`, espera com `orion esperar --filhos` e lê a resposta com `orion resultado ID`; com `--retorno`, o resultado volta sozinho para a conversa dele. |
| **Workspaces** | Seletor no topo (dropdown com a pasta, as abas e quantos agentes trabalham ou esperam em cada um); ⌃1…⌃9 troca (a tela desliza), ⌃⌘↑/↓ anterior e seguinte, ⇧⌘G cria. |
| **Barra lateral** | Trilho de ícones à esquerda (agentes, quadro, histórico, portas, notificações, ajustes) e, ao lado, a busca e as seções Agentes, Terminais e Histórico: cada agente com mascote, nome, papel, hora e o que está fazendo — ou a última coisa que disse. O histórico lista os agentes fechados por dia; um clique reabre na mesma conversa. |
| **Compose** (⌘E) | Caixa de escrita embaixo do painel. ↩ envia, ⇧↩ quebra a linha, ↑ ↓ histórico, esc volta ao terminal. **@** menciona outro terminal/agente (↩ anexa o contexto dele; ⌥↩ manda a mensagem para ele), pastas e arquivos — a menção vira uma **etiqueta** dentro do texto. **Imagens**: ⌘V (também com o terminal em foco), arrastar para qualquer lugar do painel, ou o clipe. Com o agente trabalhando e a caixa vazia, o botão vira “parar”. |
| **Vista de conversa** (⌥⌘C) | O mesmo agente lido como chat: o que você mandou pelo compose à direita, o que ele escreveu depois à esquerda (tirado do texto do terminal, que continua por baixo). Só existe com a vista aberta e só relê o terminal quando chega saída. |
| **Quadro de agentes** (⇧⌘A) | Cinco colunas: esperando você · trabalhando · revisar · parados · concluído. Cartões com o personagem; o maestro mostra os subagentes dentro dele. Filtros por workspace, ferramenta e texto. Vira lista em janela estreita. |
| **Fechados há pouco** (⌥⌘Z) | Fechou um agente sem querer? O relógio na barra do topo lista os últimos 20; um clique reabre na mesma pasta, conta e personagem, retomando a conversa (`claude --resume <id>` / `codex resume <id>` quando o id é encontrado; senão a última daquela pasta). Ao sair do app, o id de cada conversa é anotado para voltar exatamente nela. |
| **Portas em uso** (⌥⌘P) | Os servidores que os painéis subiram (node, vite, next, python…): a porta aparece no cabeçalho do painel (clique abre no navegador) e na barra de baixo; a lista abre no navegador, leva ao painel e **libera a porta** (encerra o processo, com confirmação). `orion portas`, `orion liberar 3000`. |
| **Botões do Claude / Codex / Gemini** | Hover = resumo; clique = painel (contas, uso, agentes, “Novo …”); ⌥-clique ou duplo clique abre direto. O seletor de conta do painel é um popover com cor, e-mail e barras de uso. |
| **Gemini CLI** | Terceira ferramenta, com multiconta: cada conta é uma pasta apontada por `GEMINI_CLI_HOME` (a configuração fica em `<pasta>/.gemini`). O Gemini CLI não informa uso; o resto é igual. Dá para esconder qualquer ferramenta em Ajustes → Janela. |
| **Vidro de verdade** | A janela é transparente: em Ajustes → Aparência, “Transparência” diz quanto se vê do que está atrás e “Desfoque” vai de nítido a fosco. Sem `NSVisualEffectView`. |
| **Ajustes** | Linhas com ícone, nome e controle; prévia ao vivo na Aparência; busca que acha um ajuste em qualquer seção. A janela é descartada ao fechar. |
| **Menu de contexto / ⌘-clique** | Detecta caminho ou link sob o mouse: abrir, navegador, Finder, novo terminal, copiar, mencionar no compose. |
| **Texto nítido** | Os painéis ficam sempre em pixels inteiros e, ao redimensionar, a camada do terminal fica ancorada (nunca esticada) até redesenhar no tamanho novo; o programa só recebe o tamanho (SIGWINCH) quando o arrasto para. |
| **Leve** | Nada anima em loop (o ponto de estado é estático): CPU ociosa em 0%. O tique de 1 s só lê o nome do processo quando ele muda; memória a cada 10 s e portas a cada 12 s, só com a janela à vista. |
| **Sessões, temas, autocomplete, avisos** | Reabre workspaces e abas; 17 temas + editor (exporta/importa); modo claro, escuro ou automático; lista de sugestões embaixo do que você digita; notificações quando um agente para e espera você. |

## Atalhos

| | |
|---|---|
| Workspace 1–9 · seguinte / anterior · novo | ⌃1…⌃9 · ⌃⌘↓ / ⌃⌘↑ · ⇧⌘G |
| Quadro · interromper agente · atualizar uso | ⇧⌘A · ⌘. · ⌥⌘U |
| Novo terminal · Claude · Codex · Gemini | ⌘T · ⇧⌘T · ⇧⌘X · ⌥⌘G |
| Novo agente com opções · novo subagente · reabrir fechado | ⌥⌘N · ⇧⌥⌘N · ⌥⌘Z |
| Compose: escrever/voltar · mostrar/esconder · anexar | ⌘E · ⇧⌘E · ⌥⌘A |
| Conversa / terminal · portas em uso | ⌥⌘C · ⌥⌘P |
| Aba 1–9 · seguinte / anterior · voltar / avançar | ⌘1…⌘9 · ⇧⌘] / ⇧⌘[ · ⌥⌘[ / ⌥⌘] |
| Dividir · painel vizinho · maximizar | ⌘D / ⇧⌘D · ⌥⌘setas · ⇧⌘↩ |
| Paleta · barra lateral · barra de agentes · ajustes | ⌘P · ⌘B · ⇧⌘B · ⌘, |

## Para agentes de IA: o comando `orion`

Cada painel exporta `ORION_PAINEL` (o próprio id) e `ORION_SOCKET`. O app escuta em
`~/Library/Application Support/Orion Terminal/controle.sock` (só o seu usuário).

```
# Maestro e subagentes
orion agente --claude|--codex|--gemini --pai $ORION_PAINEL [--papel P] [--nome N] [--retorno]
             --mensagem "tarefa"             cria um subagente (em segundo plano) e devolve o id
orion filhos [ID] [--json]                   subagentes de um maestro: personagem, estado, tarefa
orion esperar --filhos [ID] [--tempo S]      espera todos pararem  (orion esperar ID = um só)
orion resultado ID [--linhas N]              a última resposta do agente, em bloco <contexto-orion>

# Agentes
orion agentes [--json] [--workspace W]       personagem, papel, pai, estado, tarefa, conta, memória
orion agente --claude|--codex|--gemini [--workspace W] [--pasta P] [--conta ID] [--nome N]
             [--papel P] [--mensagem "tarefa"] [--fundo]
orion enviar ID "texto" [--enter] [--anexo ARQ]… [--mencionar ID]…
orion compor ID ["texto"] [--anexo ARQ]… [--mencionar ID]… [--para ID]… [--focar] [--limpar]
orion contexto [ID] · orion ler [ID] [--linhas N] · orion interromper ID · orion reiniciar ID
orion marcar [ID] revisar|concluido|nada · orion personagem [ID] [--nome N] [--papel P] [--avatar 🦊] [--maestro]
orion fechados · orion reabrir [N|ID] [--fundo]
orion conta ID CONTA · orion conta --padrao CONTA · orion contas · orion uso · orion memoria

# Workspaces, terminais e servidores
orion workspaces · orion workspace novo|focar|renomear|editar|fechar …
orion abas [--json] · orion nova --shell|--claude|… · orion dividir [ID] [--abaixo] [--comando C]
orion rodar "cmd" [--painel ID] --esperar    saída + código de saída
orion portas [--todas] [--json] · orion liberar PORTA
orion focar|fechar ID · orion notificar "texto"

# Interface
orion ui quadro|paleta|ajustes [seção]|contas|temas|lateral|barra|portas|fechar
orion ui claude|codex|gemini · orion ui uso [ferramenta] · orion ui conversa [ID]
orion ui compose [ID] | novo-agente [ferramenta] | subagente [ID] | personagem [ID] | novo-workspace
```

Ajustes → IA e CLI copia um bloco pronto para o CLAUDE.md / AGENTS.md, com as instruções do
maestro. `--grupo` (v0.2) ainda é aceito como sinônimo de `--workspace`.

## Compilar a partir do código

A licença permite compilar o código sem modificações para uso próprio. Só precisa das Command Line Tools (`xcode-select --install`); Xcode não é necessário.

```bash
git clone https://github.com/rodrillet/orion-terminal.git && cd orion-terminal
./build.sh             # build/Orion Terminal.app
./build.sh --instalar  # copia para /Applications e liga ~/.local/bin/orion
./build.sh --publico   # pacote de distribuição em dist/ (.zip + .zip.sha256)
```

**Publicar uma versão:** suba `VERSAO` no `build.sh`, escreva as novidades em `notas/<versão>.md`,
faça o commit e rode `./release.sh` — ele gera o pacote, cria a tag e o release no GitHub. Os apps
instalados se atualizam sozinhos.

**Sem Xcode:** `@State` virou macro no SDK novo e o plugin dela só vem com o Xcode; o código usa
`@Estado` (apelido para o property wrapper `SwiftUI.State`).

## Arquivos

| Arquivo | Papel |
|---|---|
| `Sources/OrionTerminal/Pty.swift` | `forkpty`, leitura em fila própria, processo em primeiro plano, pasta |
| `Shell.swift` | ambiente das abas e integração com o zsh (OSC 133 / 633 / 7) via `ZDOTDIR` |
| `Painel.swift` | terminal SwiftTerm + sessão; marcas OSC, captura da saída, estado do agente; `CaixaPainel` (o cartão: cabeçalho, terminal, compose, sombra) |
| `Compose.swift` | compose: rascunho, campo de texto (AppKit), menções `@`, anexos, contexto entre terminais, envio |
| `Contexto.swift` | detecção de caminho/link sob o mouse, ⌘-clique e o menu de contexto do terminal |
| `Dialogos.swift` | diálogos do app (confirmar, texto, workspace, agente, conta) — assíncronos |
| `Memoria.swift` | memória do app e da árvore de processos de cada painel |
| `Ferramentas.swift` | as três ferramentas (`Ferramenta`), personagens (`Persona`), nomes a partir da tarefa, descoberta do id da sessão, fechados |
| `Portas.swift` | portas em escuta (lsof), liberar porta, fechados há pouco e reabrir |
| `Conversa.swift` | vista de conversa e o avatar dos personagens |
| `Modelo.swift` | `Workspace`, `Aba`, árvore de divisões (`No`), `EstadoPainel`, `Conta`, `Uso` |
| `Loja.swift` | estado central: workspaces, abas, navegação, quadro, aparência, memória, persistência e migração |
| `LojaContas.swift` / `Contas.swift` | contas, login, cache de uso, cartão das ferramentas |
| `Temas.swift` | temas embutidos e do usuário (`temas.json`), cores (`Cor`), fontes (`F`) e raios (`R`) da interface |
| `Area.swift` | layout das divisões em AppKit (raízes guardadas por aba; nada é recriado ao trocar) |
| `Interface.swift` | janela, barra do topo, trilho, barra lateral, barra de agentes, memória, doca |
| `PainelUI.swift` / `Quadro.swift` / `UsoUI.swift` | cabeçalho do painel · quadro de agentes · botões do Claude/Codex (resumo e painel) |
| `Paleta.swift` / `AjustesView.swift` / `AparenciaView.swift` | paleta ⌘P · ajustes e guia para IA · aparência e editor de tema |
| `Sugestoes.swift` / `Specs.swift` | autocomplete |
| `Controle.swift` + `Sources/orion` | socket e CLI para agentes |
| `Atualizador.swift` / `AtualizacaoUI.swift` | atualização pelos releases do GitHub (ETag, SHA-256, troca segura do pacote) e a seção Sobre |
| `tools/icone.swift` | desenha o ícone (placa grafite, prompt e a estrela da família Orion) |

Dados em `~/Library/Application Support/Orion Terminal/` (`ajustes.json`, `estado.json`, `contas.json`,
`uso.json`, `temas.json`, `compose.json`, `fechados.json`, `perfis/`).

## Testar sem atrapalhar a cópia instalada

```
ORION_DADOS=/tmp/orion-dev ORION_SEM_FOCO=1 ORION_USO_FALSO=1 "build/Orion Terminal.app/Contents/MacOS/OrionTerminal" &
ORION_SOCKET=/tmp/orion-dev/controle.sock "build/Orion Terminal.app/Contents/MacOS/orion" workspaces
```

`ORION_DADOS` troca a pasta de dados (estado, ajustes, socket — caminho curto, o socket Unix tem
limite de 103 caracteres). `ORION_SEM_FOCO=1` abre a janela atrás das outras, sem ícone no Dock e
sem roubar o foco. `ORION_USO_FALSO=1` nunca lê o Chaveiro nem a rede. Para capturas de tela sem
mouse nem teclado: `orion ui …` abre quadro, paleta, ajustes, o painel das ferramentas e os
diálogos, e `orion depurar …` injeta estados de teste: `uso`, `estado`, `agente`, `tamanho`,
`tema ID`, `ajuste CHAVE VALOR`, `dialogo confirmar|texto|workspace|agente|conta|ok|fechar`,
`mencao ID "@termo" [--aceitar]`, `colar ID --texto ARQUIVO` (área de transferência privada),
`soltar ID --texto ARQUIVO` (arrasto para o painel), `sessao ID` (id da conversa encontrado), `aliviar`,
`alvo ID --texto "linha" --coluna N`, `ponto ID --linha L --coluna C`, `menu ID --texto "linha"`
(lista os itens; com `--tempo S` também mostra o menu), `editar-tema`, `sistema claro|escuro`, `sair`.
O terminal só redesenha com a janela à vista: use `orion depurar frente` antes de capturar e
`orion depurar fundo` logo depois (a janela de teste na frente atrapalha quem está usando o Mac).

## Licença e direitos

**© 2026 Orya Growth. Todos os direitos reservados.** O código está aberto para leitura, não para
reuso: você pode baixar e usar o app de graça (inclusive no trabalho) e ler o código, mas **não pode
copiar, modificar, redistribuir, vender, nem usar o nome ou o ícone** sem autorização por escrito.
Texto completo em [LICENSE](LICENSE) (Lei nº 9.609/98 e Lei nº 9.610/98). Componentes de terceiros
mantêm as próprias licenças e estão em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Claude, Codex, ChatGPT e Gemini são marcas dos
respectivos donos; o Orion Terminal não é afiliado a eles e apenas abre as ferramentas de linha de
comando que você já tem instaladas.
