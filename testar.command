#!/bin/bash
# Dispara as animações sem precisar do Claude Code / Fires the animations without Claude Code.
PORT="${BIGODINHO_PORT:-47321}"
# Idioma das mensagens / message language: português se o Mac estiver em pt, senão inglês.
PT=0
case "$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n"()')" in pt*) PT=1 ;; esac
t() { if [ "$PT" = 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
if ! curl -s -m 2 "http://127.0.0.1:$PORT/ping" | grep -q bigodinho; then
  echo "✖ $(t "Claude Notch is not running. Open ~/Applications/Bigodinho Apple.app or run instalar.command." "O Bigodinho não está rodando. Abra ~/Applications/Bigodinho Apple.app ou rode instalar.command.")"
  read -r -p "$(t "Press Enter to close." "Aperte Enter pra fechar.")"; exit 1
fi
echo "▶ $(t "thinking…" "pensando…")";           curl -s "http://127.0.0.1:$PORT/test?kind=thinking" >/dev/null; sleep 3
echo "▶ $(t "Claude replied" "Claude respondeu")";     curl -s "http://127.0.0.1:$PORT/test?kind=done"     >/dev/null; sleep 5
echo "▶ $(t "needs approval (click the notch to dismiss)" "precisa de aprovação (clique no bigodinho pra dispensar)")"
curl -s "http://127.0.0.1:$PORT/test?kind=approval" >/dev/null
echo "✔ $(t "done" "feito")"
sleep 1
