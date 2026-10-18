#!/bin/bash
# ╭──────────────────────────────────────────────────────────────╮
# │  Claude Notch · installer / instalador                        │
# │  Dê dois cliques neste arquivo. Ele:                          │
# │   1. confere se o compilador Swift da Apple está instalado    │
# │   2. compila o app                                            │
# │   3. instala em ~/Applications/Bigodinho Apple.app            │
# │   4. liga os hooks do Claude Code (~/.claude/settings.json)   │
# │   5. deixa o app abrindo sozinho junto com o Mac              │
# ╰──────────────────────────────────────────────────────────────╯
set -euo pipefail

cd "$(dirname "$0")"
SRC="$(pwd)"
WORK="$HOME/.bigodinho"
APP_NAME="Bigodinho Apple"
BUNDLE_ID="br.com.bigodinho.apple"
APP_DIR="$HOME/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
PORT="${BIGODINHO_PORT:-47321}"

# Idioma das mensagens / message language: português se o Mac estiver em pt, senão inglês.
PT=0
case "$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n"()')" in pt*) PT=1 ;; esac
t() { if [ "$PT" = 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

say() { printf '\n\033[1;33m▶ %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*"; echo; read -r -p "$(t "Press Enter to close." "Aperte Enter pra fechar.")"; exit 1; }

echo
echo "  ✦  Claude Notch · Claude Code"
echo "  $(t "project folder" "pasta do projeto"): $SRC"

# Arquivos baixados da internet vêm com "quarentena"; tira pra não travar nada.
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

say "1/5 $(t "Checking the Swift compiler (Apple Command Line Tools)…" "Conferindo o compilador Swift (Command Line Tools da Apple)…")"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  echo "  $(t "Not installed yet. Asking macOS to install it (one time, a few minutes)." "Ainda não tem. Vou pedir pro macOS instalar (é uma vez só, uns minutos).")"
  xcode-select --install 2>/dev/null || true
  die "$(t "Accept the install in the window that opened. When it finishes, double-click instalar.command again." "Aceite a instalação na janela que abriu. Quando terminar, dê dois cliques de novo em instalar.command.")"
fi
if ! swift --version >/dev/null 2>&1; then
  die "$(t "The 'swift' command exists but does not run. Open Xcode once (or run: sudo xcode-select --reset) and try again." "O comando 'swift' existe mas não roda. Abra o Xcode uma vez (ou rode: sudo xcode-select --reset) e tente de novo.")"
fi
ok "$(swift --version 2>/dev/null | head -1)"

say "2/5 $(t "Compiling (the first time takes 1 to 3 minutes)…" "Compilando (a primeira vez leva 1 a 3 minutos)…")"
mkdir -p "$WORK/src" "$WORK/build/release"
rsync -a --delete --exclude '._*' --exclude '.DS_Store' "$SRC/app/" "$WORK/src/"
BIN="$WORK/build/release/BigodinhoApple"
rm -f "$BIN"
: > "$WORK/build.log"

# Caminho normal: SwiftPM.
( cd "$WORK/src" && swift build -c release --scratch-path "$WORK/build" >>"$WORK/build.log" 2>&1 ) || true

# Plano B: algumas instalações das Command Line Tools vêm com versões misturadas e o SwiftPM
# nem consegue ler o Package.swift. Como o app não tem dependências, compila direto com swiftc.
if [ ! -x "$BIN" ]; then
  echo "  $(t "SwiftPM failed; compiling directly with swiftc…" "SwiftPM não deu; compilando direto com swiftc…")"
  EXTRA=()
  INC="$(xcode-select -p)/usr/include/swift"
  # Toolchain com dois modulemaps definindo SwiftBridging (um de 2023, outro de 2025): esconde o velho.
  if [ -f "$INC/module.modulemap" ] && [ -f "$INC/bridging.modulemap" ]; then
    : > "$WORK/empty.modulemap"
    cat > "$WORK/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [
  { "name": "$INC", "type": "directory", "contents": [
     { "name": "module.modulemap", "type": "file", "external-contents": "$WORK/empty.modulemap" } ] } ] }
EOF
    EXTRA=(-vfsoverlay "$WORK/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$WORK/overlay.yaml")
  fi
  ( cd "$WORK/src" && swiftc -O -target "$(uname -m)-apple-macosx13.0" ${EXTRA[@]+"${EXTRA[@]}"} \
      Sources/BigodinhoApple/*.swift -o "$BIN" >>"$WORK/build.log" 2>&1 ) || true
fi
if [ ! -x "$BIN" ]; then
  grep -E "error:" "$WORK/build.log" | grep -v "Invalid manifest" | sort -u | head -20 || true
  die "$(t "The build failed. See $WORK/build.log and open an issue with the error." "A compilação falhou. Veja $WORK/build.log e me mande o erro.")"
fi
ok "$(t "built" "compilou")"

say "3/5 $(t "Assembling the app at" "Montando o app em") $APP_DIR…"
pkill -x BigodinhoApple 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/BigodinhoApple"
cp "$SRC/app/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
ok "$(t "app ready" "app pronto")"

say "4/5 $(t "Wiring up the Claude Code hooks…" "Ligando os hooks do Claude Code…")"
cp "$SRC/hooks/hook.sh" "$WORK/hook.sh"
chmod +x "$WORK/hook.sh"
python3 "$SRC/scripts/configurar-hooks.py" "$WORK/hook.sh"

say "5/5 $(t "Making Claude Notch start at login…" "Deixando o Bigodinho abrir junto com o Mac…")"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__BINARY__|$APP_DIR/Contents/MacOS/BigodinhoApple|g" \
    -e "s|__LOG__|$WORK/bigodinho.log|g" \
    "$SRC/scripts/LaunchAgent.plist.template" > "$PLIST"
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || open "$APP_DIR"
ok "$(t "configured" "configurado")"

sleep 2
if curl -s -m 2 "http://127.0.0.1:$PORT/ping" | grep -q bigodinho; then
  ok "$(t "Claude Notch is running! Look at the top of your main display." "Bigodinho rodando! Olha o topo do seu monitor principal.")"
  curl -s -m 2 "http://127.0.0.1:$PORT/test?kind=done" >/dev/null || true
else
  echo "  $(t "No answer on port $PORT yet. Try opening it manually:" "Ainda não respondeu na porta $PORT. Tente abrir manualmente:") $APP_DIR"
  echo "  Log: $WORK/bigodinho.log"
fi

if [ "$PT" = 1 ]; then
cat <<FIM

  ────────────────────────────────────────────────────
  Pronto. Como usar:
   • O ícone ✦ na barra de menus abre as opções.
   • Em "Chats (projetos)" você escolhe quais chats do Claude Code
     fazem o bigodinho reagir. Um chat aparece na lista na primeira
     vez que você usa o Claude Code naquela pasta.
   • Em "Monitor" você escolhe em qual monitor ele aparece.
   • Em "Idioma" você troca entre inglês e português.
   • Reinicie o Claude Code (saia e abra de novo) pra ele carregar os hooks.
  ────────────────────────────────────────────────────
FIM
else
cat <<FIM

  ────────────────────────────────────────────────────
  Done. How to use it:
   • The ✦ icon in the menu bar opens the options.
   • Under "Chats (projects)" you choose which Claude Code chats make
     the notch react. A chat shows up in the list the first time you
     use Claude Code in that folder.
   • Under "Display" you choose which monitor it appears on.
   • Under "Language" you switch between English and Portuguese.
   • Restart Claude Code (quit and reopen) so it loads the hooks.
  ────────────────────────────────────────────────────
FIM
fi
read -r -p "$(t "Press Enter to close." "Aperte Enter pra fechar.")"
