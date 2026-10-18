import AppKit

/// Ícone ✦ na barra de menus + menu de opções + servidor que recebe os hooks.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var controller: NotchController!
    private let server = EventServer()
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude Notch")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "Claude Notch · Claude Code"
        }
        menu.delegate = self
        statusItem.menu = menu

        server.onRequest = { [weak self] req in
            self?.route(req) ?? "ok"
        }
        server.start(port: UInt16(clamping: Settings.shared.port))
    }

    // MARK: - HTTP

    private func route(_ req: EventServer.Request) -> String {
        let path = req.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? req.path
        switch path {
        case "/ping":
            return "bigodinho ok"

        case "/test":
            let kind = req.path.split(separator: "=", maxSplits: 1).last.map(String.init) ?? "done"
            DispatchQueue.main.async { [weak self] in self?.controller.test(kind) }
            return "ok"

        case "/event":
            let term = req.headers["x-term-program"] ?? ""
            let bundle = req.headers["x-bundle-id"] ?? ""
            guard var e = NotchEvent.parse(json: req.body, termProgram: term, bundleId: bundle) else {
                return "invalid json"
            }
            e.hostSession = req.headers["x-host-session"] ?? ""
            e.entrypoint = req.headers["x-entrypoint"] ?? ""
            DispatchQueue.main.async { [weak self] in self?.controller.handle(e) }
            return "ok"

        default:
            return "bigodinho"
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared

        let header = NSMenuItem(title: "Claude Notch · Claude Code", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(toggle(L.t("Enabled", "Ativado"), s.enabled, #selector(toggleEnabled)))
        menu.addItem(item(L.t("Open chat panel", "Abrir painel de chats"), #selector(openPanel), key: "o"))
        menu.addItem(.separator())

        // Monitor
        let mon = NSMenu()
        let names = s.screenNames
        let auto = item(L.t("Automatic (main display)", "Automático (monitor principal)"), #selector(pickScreen(_:)), rep: "")
        auto.state = names.isEmpty ? .on : .off
        mon.addItem(auto)
        let all = item(L.t("All displays", "Todos os monitores"), #selector(pickScreen(_:)), rep: Settings.allScreens)
        all.state = names.contains(Settings.allScreens) ? .on : .off
        mon.addItem(all)
        mon.addItem(.separator())
        let hint = NSMenuItem(title: L.t("Select one or more:", "Marque um ou mais:"), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        mon.addItem(hint)
        for sc in NSScreen.screens {
            let it = item(sc.localizedName, #selector(toggleScreen(_:)), rep: sc.localizedName)
            it.state = names.contains(sc.localizedName) ? .on : .off
            mon.addItem(it)
        }
        let monItem = NSMenuItem(title: L.t("Display", "Monitor"), action: nil, keyEquivalent: "")
        monItem.submenu = mon
        menu.addItem(monItem)

        // Chats / projetos
        let proj = NSMenu()
        let projects = s.projects.sorted { $0.key.lowercased() < $1.key.lowercased() }
        if projects.isEmpty {
            let none = NSMenuItem(title: L.t("No chats seen yet — use Claude Code and it shows up here", "Nenhum chat visto ainda — use o Claude Code e ele aparece aqui"),
                                  action: nil, keyEquivalent: "")
            none.isEnabled = false
            proj.addItem(none)
        } else {
            for (cwd, on) in projects {
                let name = URL(fileURLWithPath: cwd).lastPathComponent
                let it = item(name.isEmpty ? cwd : name, #selector(toggleProject(_:)), rep: cwd)
                it.toolTip = cwd
                it.state = on ? .on : .off
                proj.addItem(it)
            }
        }
        proj.addItem(.separator())
        proj.addItem(toggle(L.t("New chats start enabled", "Chats novos já entram ativados"), s.newProjectsEnabled, #selector(toggleNewProjects)))
        proj.addItem(item(L.t("Clear list", "Limpar lista"), #selector(forgetProjects)))
        let projItem = NSMenuItem(title: L.t("Chats (projects)", "Chats (projetos)"), action: nil, keyEquivalent: "")
        projItem.submenu = proj
        menu.addItem(projItem)
        menu.addItem(.separator())

        menu.addItem(toggle(L.t("Show \"thinking…\"", "Mostrar \"pensando…\""), s.showThinking, #selector(toggleThinking)))
        menu.addItem(toggle(L.t("Sound", "Som"), s.soundEnabled, #selector(toggleSound)))
        menu.addItem(toggle(L.t("Always show the notch", "Bigodinho sempre visível"), s.alwaysVisible, #selector(toggleAlwaysVisible)))

        let hide = NSMenu()
        for secs in [4.0, 6.0, 10.0, 15.0] {
            let it = item(L.t("\(Int(secs)) seconds", "\(Int(secs)) segundos"), #selector(pickAutoHide(_:)), rep: secs)
            it.state = abs(s.autoHideSeconds - secs) < 0.1 ? .on : .off
            hide.addItem(it)
        }
        let hideItem = NSMenuItem(title: L.t("Collapse \"replied\" after", "Recolher \"respondeu\" após"), action: nil, keyEquivalent: "")
        hideItem.submenu = hide
        menu.addItem(hideItem)

        let lang = NSMenu()
        for (code, title) in [("auto", L.t("Automatic", "Automático")), ("en", "English"), ("pt", "Português")] {
            let it = item(title, #selector(pickLanguage(_:)), rep: code)
            it.state = s.language == code ? .on : .off
            lang.addItem(it)
        }
        let langItem = NSMenuItem(title: L.t("Language", "Idioma"), action: nil, keyEquivalent: "")
        langItem.submenu = lang
        menu.addItem(langItem)
        menu.addItem(.separator())

        menu.addItem(item(L.t("Test: Claude replied", "Testar: Claude respondeu"), #selector(testDone)))
        menu.addItem(item(L.t("Test: needs approval", "Testar: precisa de aprovação"), #selector(testApproval)))
        menu.addItem(item(L.t("Test: thinking…", "Testar: pensando…"), #selector(testThinking)))
        menu.addItem(item(L.t("Test: open panel", "Testar: abrir painel"), #selector(testOpen)))
        menu.addItem(.separator())
        menu.addItem(item(L.t("Open config folder", "Abrir pasta de configuração"), #selector(openConfig)))
        menu.addItem(item(L.t("Quit Claude Notch", "Sair do Claude Notch"), #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ sel: Selector, rep: Any? = nil, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        it.representedObject = rep
        return it
    }

    private func toggle(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let it = item(title, sel)
        it.state = on ? .on : .off
        return it
    }

    // MARK: - Ações

    @objc private func toggleEnabled() {
        Settings.shared.enabled.toggle()
        controller.applyVisibility()
    }

    @objc private func toggleSound() { Settings.shared.soundEnabled.toggle() }
    @objc private func toggleThinking() { Settings.shared.showThinking.toggle() }
    @objc private func toggleNewProjects() { Settings.shared.newProjectsEnabled.toggle() }

    @objc private func toggleAlwaysVisible() {
        Settings.shared.alwaysVisible.toggle()
        controller.applyVisibility()
    }

    /// "Automático" (vazio) ou "Todos" ("*").
    @objc private func pickLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        Settings.shared.language = code
    }

    @objc private func pickScreen(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        Settings.shared.screenNames = name.isEmpty ? [] : [name]
        controller.reposition()
    }

    /// Liga/desliga um monitor específico; pode marcar vários.
    @objc private func toggleScreen(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var names = Settings.shared.screenNames.filter { $0 != Settings.allScreens }
        if let i = names.firstIndex(of: name) { names.remove(at: i) } else { names.append(name) }
        Settings.shared.screenNames = names
        controller.reposition()
    }

    @objc private func toggleProject(_ sender: NSMenuItem) {
        guard let cwd = sender.representedObject as? String else { return }
        let current = Settings.shared.projects[cwd] ?? true
        Settings.shared.setProject(cwd, enabled: !current)
    }

    @objc private func forgetProjects() { Settings.shared.forgetProjects() }

    @objc private func pickAutoHide(_ sender: NSMenuItem) {
        if let secs = sender.representedObject as? Double { Settings.shared.autoHideSeconds = secs }
    }

    @objc private func testDone() { controller.test("done") }
    @objc private func testApproval() { controller.test("approval") }
    @objc private func testThinking() { controller.test("thinking") }
    @objc private func testOpen() { controller.test("open") }
    @objc private func openPanel() { controller.setOpen(true) }

    @objc private func openConfig() {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".bigodinho")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
