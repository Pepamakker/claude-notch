#!/bin/bash
# Remove o Bigodinho Apple por completo (app, hooks, item de login). Não mexe no resto do seu Claude Code.
set -uo pipefail
cd "$(dirname "$0")"
# Idioma das mensagens / message language: português se o Mac estiver em pt, senão inglês.
PT=0
case "$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n"()')" in pt*) PT=1 ;; esac
t() { if [ "$PT" = 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
WORK="$HOME/.bigodinho"
BUNDLE_ID="br.com.bigodinho.apple"
APP_DIR="$HOME/Applications/Bigodinho Apple.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

echo "▶ $(t "Stopping the app…" "Parando o app…")"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
pkill -x BigodinhoApple 2>/dev/null || true
rm -f "$PLIST"

echo "▶ $(t "Removing the Claude Code hooks…" "Tirando os hooks do Claude Code…")"
python3 scripts/configurar-hooks.py --remover || true

echo "▶ $(t "Deleting the app and working files…" "Apagando o app e os arquivos de trabalho…")"
rm -rf "$APP_DIR" "$WORK"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "✔ $(t "Claude Notch removed. This project folder is untouched." "Bigodinho removido. Esta pasta do projeto fica intacta.")"
read -r -p "$(t "Press Enter to close." "Aperte Enter pra fechar.")"
