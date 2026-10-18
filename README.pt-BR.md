# ✦ Claude Notch · Claude Code

[English](README.md) · **Português**

Um "bigodinho" (o notch do MacBook) desenhado no topo do seu monitor, ligado **só ao Claude Code**.
Quando o Claude termina de responder, ou quando ele precisa da sua aprovação, o bigodinho se abre
com uma animação estilo Dynamic Island e mostra o que aconteceu e em qual chat. Clicou nele, ele traz
o terminal/editor daquele chat pra frente.

```
   ┌────────────────────────────────┐          ┌──────────────────────────────────────────────┐
   │        ▄▄▄▄▄▄▄▄▄▄▄▄▄▄          │   →      │   ✓  Claude respondeu                 abrir  │
   │       quieto no topo           │          │      meu-projeto · Pronto! Criei o arquivo…  │
   └────────────────────────────────┘          └──────────────────────────────────────────────┘
```

## O que ele faz

![prévia dos quatro estados](docs/previa.png)

| Momento no Claude Code                      | Bigodinho                                                          |
|---------------------------------------------|--------------------------------------------------------------------|
| Você manda um prompt                        | Pontinho laranja pulsando + nome do projeto (dá pra desligar)      |
| Claude termina a resposta                   | Abre com ✓ verde, primeira linha da resposta, som "Glass", recolhe |
| Claude pede permissão (rodar comando etc.)  | Abre com ✋ âmbar pulsando e **fica** até você clicar ou aprovar    |
| Claude parado esperando você                | Abre com 💬 azul                                                   |
| Clique no bigodinho                         | Abre o painel (estilo Dynamic Island) com os chats ativados: cor do estado, o que cada um está fazendo e % estimada enquanto pensa |
| Clique numa linha do painel / em "abrir →"  | Abre o chat no app Claude; sem isso, traz o Terminal / iTerm / Warp / VS Code / Cursor daquele chat |

Você escolhe quais chats contam: menu ✦ → **Chats (projetos)**. Cada pasta onde você usa o
Claude Code aparece ali com uma marcação pra ligar/desligar.

## Precisa abrir o Terminal?

**Uma vez só, e nem precisa digitar nada:** dê dois cliques em `instalar.command`. O macOS abre o
Terminal sozinho, o script compila e instala tudo (uns 2 minutos na primeira vez) e depois é só fechar.

Se o macOS reclamar que o arquivo "não pode ser aberto porque é de um desenvolvedor não identificado"
(acontece com arquivos baixados): **clique com o botão direito → Abrir**. Ou, no Terminal:

```bash
cd "caminho/da/pasta/do/projeto" && bash instalar.command
```

Requisitos: macOS 13 ou mais novo e as **Command Line Tools** da Apple (o instalador pede pra
instalar se faltar; é o compilador Swift, não precisa do Xcode inteiro).

## Instalar

1. Baixe ou clone esta pasta onde quiser.
2. Dois cliques em **`instalar.command`**.
3. Feche e abra de novo o Claude Code em cada terminal, pra ele carregar os hooks.
4. Pronto. Um bigodinho aparece no topo do monitor principal e um ✦ na barra de menus.

O instalador deixa:

| Onde                                              | O quê                                           |
|---------------------------------------------------|-------------------------------------------------|
| `~/Applications/Bigodinho Apple.app`              | o app (abre sozinho ao ligar o Mac)             |
| `~/.bigodinho/hook.sh`                            | o hook que o Claude Code chama                  |
| `~/.claude/settings.json`                         | hooks adicionados (com backup `.bak-…` do lado) |
| `~/Library/LaunchAgents/br.com.bigodinho.apple.plist` | item de login                               |

Esta pasta do projeto pode ficar no disco externo: o app instalado não depende dela.

## Menu ✦

- **Ativado** liga/desliga tudo.
- **Monitor** por padrão usa o monitor principal. Dá pra marcar um, vários ou **Todos os monitores** (um bigodinho em cada, sincronizados).
- **Abrir painel de chats** (⌘O no menu, ou clique no bigodinho): painel em vidro escuro com uma linha por pasta ativada: ponto colorido (âmbar aprovação, laranja pensando, verde respondeu, azul esperando), o que o chat está fazendo e uma % estimada enquanto pensa (média dos turnos anteriores daquela pasta). Clique na linha abre aquele chat no app Claude; clique fora fecha.
- **Chats (projetos)** lista as pastas vistas; marque só as que devem avisar. "Chats novos já entram ativados" define o padrão.
- **Mostrar "pensando…"**, **Som**, **Bigodinho sempre visível** (desligado = só aparece quando tem evento).
- **Recolher "respondeu" após** 4, 6, 10 ou 15 segundos. Aprovações não recolhem sozinhas.
- **Testar…** dispara cada animação na hora. `testar.command` faz a sequência inteira.

## Como funciona por dentro

```
Claude Code ──hook (Stop / Notification / UserPromptSubmit…)──▶ ~/.bigodinho/hook.sh
                                                                     │ curl POST (JSON)
                                                                     ▼
                                                   Bigodinho Apple.app  127.0.0.1:47321
                                                                     │
                                                                     ▼
                                                   bigodinho no topo do monitor
```

- O app escuta **só em 127.0.0.1** (nada sai do seu Mac) e **só** recebe os eventos do Claude Code.
- O hook não imprime nada e sempre sai com 0, então nunca interfere na conversa.
- O JSON do Claude Code traz `cwd` (pasta do chat) e `session_id`; é assim que o app sabe de qual chat é cada evento.
- O hook manda junto `TERM_PROGRAM`, `__CFBundleIdentifier`, `CLAUDE_CODE_HOST_SESSION_ID` e `CLAUDE_CODE_ENTRYPOINT`. Com o id da sessão do app Claude, o clique abre direto aquele chat (`claude://claude.ai/epitaxy/<id>`); sem ele, traz o terminal pra frente.

Código: `app/Sources/BigodinhoApple/` (Swift + SwiftUI, sem dependências).

| Arquivo               | Papel                                                        |
|-----------------------|--------------------------------------------------------------|
| `NotchView.swift`     | o desenho do bigodinho, o painel de chats e as animações     |
| `NotchController.swift` | decide o que mostrar, posiciona no monitor, timers         |
| `EventServer.swift`   | servidor HTTP local minúsculo                                |
| `NotchEvent.swift`    | traduz o JSON dos hooks                                      |
| `AppDelegate.swift`   | ícone ✦ e menu                                               |
| `Settings.swift`      | preferências                                                 |

## Problemas comuns

- **Nada aparece quando o Claude responde.** Reabra o Claude Code (os hooks carregam na abertura). Depois rode `testar.command`: se as animações aparecem, o app está bem e o problema é o hook. Em um chat, digite `/hooks` e confira se `~/.bigodinho/hook.sh` está listado.
- **Apareceu no monitor errado.** Menu ✦ → Monitor → escolha o monitor desejado.
- **Idioma.** A interface segue o idioma do Mac (inglês ou português). Para forçar um: ✦ → Idioma.
- **Porta ocupada.** Mude com `defaults write br.com.bigodinho.apple port 47322` e `export BIGODINHO_PORT=47322` no seu shell; reinicie o app.
- **Claude Desktop (o app de chat).** Conversas comuns do chat não têm hooks, então o bigodinho não as enxerga. Funciona com o **Claude Code**: terminal, VS Code, Cursor, Warp, iTerm e a aba Code do app Claude.
- **Compilação falhou.** Veja `~/.bigodinho/build.log` e abra uma issue com o erro. Se o log falar em
  `Invalid manifest` ou `redefinition of module 'SwiftBridging'`, as Command Line Tools estão com
  versões misturadas; o instalador contorna isso compilando direto com `swiftc`, mas o conserto
  definitivo é reinstalar: `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`.

## Remover

Dois cliques em `desinstalar.command`. Tira o app, o item de login e os hooks (deixa o resto do seu `settings.json` intacto).
