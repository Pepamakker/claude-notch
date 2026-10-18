import Foundation

/// Preferências do usuário, guardadas em UserDefaults (~/Library/Preferences/br.com.bigodinho.apple.plist).
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private enum K {
        static let enabled = "enabled"
        static let sound = "soundEnabled"
        static let thinking = "showThinking"
        static let alwaysVisible = "alwaysVisible"
        static let autoHide = "autoHideSeconds"
        static let screen = "screenName"
        static let projects = "projects"
        static let newProjects = "newProjectsEnabled"
        static let port = "port"
        static let language = "language"
    }

    private init() {
        d.register(defaults: [
            K.enabled: true,
            K.sound: true,
            K.thinking: true,
            K.alwaysVisible: true,
            K.autoHide: 6.0,
            K.newProjects: true,
            K.port: 47321,
        ])
    }

    /// Liga/desliga tudo.
    var enabled: Bool {
        get { d.bool(forKey: K.enabled) }
        set { d.set(newValue, forKey: K.enabled) }
    }

    /// Toca um som discreto junto com a animação.
    var soundEnabled: Bool {
        get { d.bool(forKey: K.sound) }
        set { d.set(newValue, forKey: K.sound) }
    }

    /// Mostra o pontinho pulsando enquanto o Claude está trabalhando.
    var showThinking: Bool {
        get { d.bool(forKey: K.thinking) }
        set { d.set(newValue, forKey: K.thinking) }
    }

    /// Bigodinho sempre no topo (true) ou só aparece quando tem evento (false).
    var alwaysVisible: Bool {
        get { d.bool(forKey: K.alwaysVisible) }
        set { d.set(newValue, forKey: K.alwaysVisible) }
    }

    /// Idioma da interface: "auto", "en" ou "pt".
    var language: String {
        get { d.string(forKey: K.language) ?? "auto" }
        set { d.set(newValue, forKey: K.language) }
    }

    /// Segundos que o aviso "respondeu" fica aberto antes de recolher.
    var autoHideSeconds: Double {
        get { d.double(forKey: K.autoHide) }
        set { d.set(newValue, forKey: K.autoHide) }
    }

    /// Monitores escolhidos (NSScreen.localizedName). Vazio = automático (monitor principal).
    /// ["*"] = todos os monitores ao mesmo tempo. Migra a escolha antiga de um monitor só.
    var screenNames: [String] {
        get {
            if let v = d.stringArray(forKey: "screenNames") { return v }
            if let old = d.string(forKey: K.screen) { return [old] }
            return []
        }
        set {
            d.set(newValue, forKey: "screenNames")
            d.removeObject(forKey: K.screen)
        }
    }

    static let allScreens = "*"

    /// Porta local onde o app escuta os hooks do Claude Code.
    var port: Int {
        get { d.integer(forKey: K.port) }
        set { d.set(newValue, forKey: K.port) }
    }

    /// Chats/projetos conhecidos: caminho da pasta (cwd) → ativado?
    var projects: [String: Bool] {
        get { (d.dictionary(forKey: K.projects) as? [String: Bool]) ?? [:] }
        set { d.set(newValue, forKey: K.projects) }
    }

    /// Projetos novos entram ativados por padrão?
    var newProjectsEnabled: Bool {
        get { d.bool(forKey: K.newProjects) }
        set { d.set(newValue, forKey: K.newProjects) }
    }

    /// Registra o projeto se for a primeira vez que aparece e devolve se está ativado.
    func isProjectEnabled(_ cwd: String) -> Bool {
        guard !cwd.isEmpty else { return true }
        var p = projects
        if let v = p[cwd] { return v }
        p[cwd] = newProjectsEnabled
        projects = p
        return newProjectsEnabled
    }

    func setProject(_ cwd: String, enabled: Bool) {
        var p = projects
        p[cwd] = enabled
        projects = p
    }

    func forgetProjects() {
        projects = [:]
    }
}
