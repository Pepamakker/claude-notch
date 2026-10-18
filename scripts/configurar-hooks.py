#!/usr/bin/env python3
"""Adiciona (ou remove, com --remover) o hook do Bigodinho em ~/.claude/settings.json
sem mexer em nada que já estiver lá. Faz backup antes de gravar."""
import json
import os
import shutil
import sys
import subprocess
import time

EVENTS = ["UserPromptSubmit", "Stop", "Notification", "PreToolUse", "PostToolUse", "SessionStart", "SessionEnd"]
MARK = ".bigodinho/hook.sh"


def _is_pt():
    try:
        langs = subprocess.run(["defaults", "read", "-g", "AppleLanguages"],
                               capture_output=True, text=True).stdout
        return langs.replace("(", "").replace(")", "").replace('"', "").split()[0].lower().startswith("pt")
    except Exception:
        return False


PT = _is_pt()


def t(en, pt):
    return pt if PT else en


def main():
    remove = "--remover" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    hook_cmd = args[0] if args else os.path.expanduser("~/.bigodinho/hook.sh")

    path = os.path.expanduser("~/.claude/settings.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)

    cfg = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            raw = f.read().strip()
        if raw:
            try:
                cfg = json.loads(raw)
            except json.JSONDecodeError as e:
                print(t(f"✖ ~/.claude/settings.json is not valid JSON ({e}). Leaving it alone.", f"✖ ~/.claude/settings.json não é um JSON válido ({e}). Não vou mexer nele."))
                print(t("  Open the file, fix it and run the installer again.", "  Abra o arquivo, corrija e rode o instalador de novo."))
                sys.exit(1)
        backup = path + f".bak-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(path, backup)
        print(f"  backup: {backup}")

    hooks = cfg.setdefault("hooks", {})

    for ev in EVENTS:
        groups = hooks.get(ev, [])
        # tira qualquer entrada antiga do Bigodinho
        for g in groups:
            g["hooks"] = [h for h in g.get("hooks", []) if MARK not in h.get("command", "")]
        groups = [g for g in groups if g.get("hooks")]
        if not remove:
            groups.append({"hooks": [{"type": "command", "command": hook_cmd, "timeout": 5}]})
        if groups:
            hooks[ev] = groups
        else:
            hooks.pop(ev, None)

    if not hooks:
        cfg.pop("hooks", None)

    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")

    if remove:
        print(t("✔ Claude Notch hooks removed from ~/.claude/settings.json", "✔ hooks do Bigodinho removidos de ~/.claude/settings.json"))
    else:
        print(t(f"✔ hooks installed in ~/.claude/settings.json → {hook_cmd}", f"✔ hooks instalados em ~/.claude/settings.json → {hook_cmd}"))
        print(t("  events: ", "  eventos: ") + ", ".join(EVENTS))


if __name__ == "__main__":
    main()
