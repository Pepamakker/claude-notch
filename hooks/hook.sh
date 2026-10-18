#!/bin/bash
# Hook do Claude Code → Bigodinho Apple.
# O Claude Code roda este script e manda o JSON do evento no stdin.
# A gente só repassa pro app (porta local) e sai com 0, sem imprimir nada
# (qualquer texto no stdout viraria contexto da conversa).
PORT="${BIGODINHO_PORT:-47321}"
curl -s -m 2 -o /dev/null -X POST "http://127.0.0.1:${PORT}/event" \
  -H "Content-Type: application/json" \
  -H "X-Term-Program: ${TERM_PROGRAM:-}" \
  -H "X-Bundle-Id: ${__CFBundleIdentifier:-}" \
  -H "X-Host-Session: ${CLAUDE_CODE_HOST_SESSION_ID:-}" \
  -H "X-Entrypoint: ${CLAUDE_CODE_ENTRYPOINT:-}" \
  --data-binary @- >/dev/null 2>&1 </dev/stdin || true
exit 0
