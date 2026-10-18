import Foundation

/// Um evento vindo do Claude Code (via hook) já traduzido pro que o bigodinho entende.
struct NotchEvent {
    enum Kind {
        case thinking      // usuário mandou um prompt, Claude está trabalhando
        case done          // Claude terminou de responder
        case approval      // Claude pediu permissão / precisa de uma resposta sua
        case waiting       // Claude está parado esperando você (idle)
        case toolStart     // uma ferramenta vai rodar (mostra "rodando Bash…")
        case toolDone      // uma ferramenta rodou (serve pra saber que a aprovação passou)
        case sessionStart
        case sessionEnd
        case ignored
    }

    let kind: Kind
    let sessionId: String
    let cwd: String
    let message: String
    let termProgram: String
    let bundleId: String
    /// Evento de um subagente (agent_id no JSON): não conta como chat.
    var isSubagent: Bool = false
    /// Sessão no app Claude (CLAUDE_CODE_HOST_SESSION_ID): abre o chat certo via claude://
    var hostSession: String = ""
    /// De onde o Claude Code foi aberto (CLAUDE_CODE_ENTRYPOINT), só pra registro.
    var entrypoint: String = ""

    /// Nome curto do projeto = última pasta do caminho.
    var projectName: String {
        if cwd.isEmpty { return "Claude" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    /// Interpreta o JSON que o Claude Code manda pro hook no stdin.
    static func parse(json: Data, termProgram: String, bundleId: String) -> NotchEvent? {
        guard let obj = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        let name = obj["hook_event_name"] as? String ?? ""
        let sid = obj["session_id"] as? String ?? ""
        let cwd = obj["cwd"] as? String ?? ""
        var kind: Kind = .ignored
        var message = ""

        switch name {
        case "UserPromptSubmit":
            kind = .thinking
            message = obj["prompt"] as? String ?? ""

        case "Stop":
            kind = .done
            message = obj["last_assistant_message"] as? String ?? ""

        case "Notification":
            let type = obj["notification_type"] as? String ?? ""
            let msg = (obj["message"] as? String) ?? (obj["title"] as? String) ?? ""
            message = msg
            switch type {
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog":
                kind = .approval
            case "idle_prompt", "agent_needs_input":
                kind = .waiting
            case "":
                // Versões antigas do Claude Code não mandam notification_type: deduz pelo texto.
                let l = msg.lowercased()
                if l.contains("permission") || l.contains("permiss") || l.contains("approv") {
                    kind = .approval
                } else if l.contains("waiting") || l.contains("esperando") || l.contains("input") {
                    kind = .waiting
                }
            default:
                kind = .ignored
            }

        case "PermissionRequest":
            kind = .approval
            if let tool = obj["tool_name"] as? String { message = "Quer usar \(tool)" }

        case "PreToolUse":
            kind = .toolStart
            message = toolLabel(obj)

        case "PostToolUse":
            kind = .toolDone
            message = toolLabel(obj)

        case "SessionStart":
            kind = .sessionStart

        case "SessionEnd":
            kind = .sessionEnd

        default:
            kind = .ignored
        }

        var ev = NotchEvent(kind: kind, sessionId: sid, cwd: cwd, message: clean(message),
                            termProgram: termProgram, bundleId: bundleId)
        let agentId = obj["agent_id"] as? String ?? ""
        let agentType = obj["agent_type"] as? String ?? ""
        ev.isSubagent = !agentId.isEmpty || !agentType.isEmpty
        return ev
    }

    /// "Bash · npm install", "Edit · NotchView.swift", "Read", "mcp__x__y"…
    private static func toolLabel(_ obj: [String: Any]) -> String {
        let tool = obj["tool_name"] as? String ?? ""
        guard let input = obj["tool_input"] as? [String: Any] else { return tool }
        var hint = ""
        if let d = input["description"] as? String, !d.isEmpty { hint = d }
        else if let c = input["command"] as? String { hint = c }
        else if let f = input["file_path"] as? String { hint = URL(fileURLWithPath: f).lastPathComponent }
        else if let f = input["notebook_path"] as? String { hint = URL(fileURLWithPath: f).lastPathComponent }
        else if let q = input["pattern"] as? String { hint = q }
        else if let q = input["query"] as? String { hint = q }
        else if let u = input["url"] as? String { hint = u }
        hint = hint.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if hint.count > 48 { hint = String(hint.prefix(48)) + "…" }
        return hint.isEmpty ? tool : "\(tool) · \(hint)"
    }

    /// Deixa a mensagem apresentável numa linha: tira quebras, markdown básico e corta no tamanho.
    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        for token in ["**", "`", "###", "##", "# "] {
            t = t.replacingOccurrences(of: token, with: "")
        }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 140 {
            t = String(t.prefix(140)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return t
    }
}

/// Mapeia o TERM_PROGRAM (variável que o terminal exporta) pro bundle id do app,
/// pra quando o hook não trouxer o __CFBundleIdentifier.
enum TerminalMap {
    static func bundleId(for termProgram: String) -> String {
        switch termProgram {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        case "vscode": return "com.microsoft.VSCode"
        case "ghostty": return "com.mitchellh.ghostty"
        case "Alacritty": return "org.alacritty"
        case "kitty": return "net.kovidgoyal.kitty"
        case "Hyper": return "co.zeit.hyper"
        case "WezTerm": return "com.github.wez.wezterm"
        case "Tabby": return "org.tabby"
        default: return ""
        }
    }
}
