import AppKit
import SwiftUI

/// O que o bigodinho sabe de cada chat (sessão) do Claude Code.
struct SessionInfo {
    var cwd: String
    var status: ChatStatus = .idle
    var detail: String = ""
    var since: Date = Date()            // quando o status atual começou
    var thinkingStart: Date?            // início do turno atual (prompt → Stop)
    var lastSeen: Date = Date()
    var termProgram: String = ""
    var bundleId: String = ""
    var hostSession: String = ""
    var entrypoint: String = ""

    var projectName: String {
        if cwd.isEmpty { return "Claude" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}

/// Dono do bigodinho: posiciona a janela, decide o que mostrar e quando recolher.
/// Tudo aqui roda na thread principal.
final class NotchController {
    let state = NotchState()
    /// Um painel por monitor escolhido; todos mostram o mesmo estado.
    private var panels: [NotchPanel] = []
    private var currentSize: CGSize = .zero
    private var hideTimer: Timer?

    /// Aprovações pendentes por sessão (chat) do Claude Code, na ordem em que chegaram.
    private var pending: [String: NotchEvent] = [:]
    private var pendingOrder: [String] = []
    /// Sessões que estão "pensando" agora.
    private var thinking: Set<String> = []
    private var lastEvent: NotchEvent?

    /// Registro de todas as sessões vistas (filtra por projeto só na hora de mostrar).
    private var sessions: [String: SessionInfo] = [:]
    /// Sessão some da lista depois de tanto tempo sem evento (terminal fechado sem SessionEnd).
    private let sessionTTL: TimeInterval = 2 * 60 * 60
    /// Duração típica de um turno por projeto (média móvel), pra estimar o progresso.
    private var turnDurations: [String: Double]
    private let defaultTurnSeconds = 45.0

    private var ticker: Timer?
    private var clickMonitor: Any?
    private var leaveTimer: Timer?
    private var hoveredOnce = false

    init() {
        turnDurations = (UserDefaults.standard.dictionary(forKey: "turnDurations") as? [String: Double]) ?? [:]
        state.onTap = { [weak self] in self?.toggleOpen() }
        state.onOpenTap = { [weak self] in self?.openTapped() }
        state.onRowTap = { [weak self] sid in self?.rowTapped(sid) }
        state.onHoverChange = { [weak self] inside in self?.hoverChanged(inside) }
        syncPanels()
        applyVisibility()

        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }
    }

    // MARK: - Monitor

    static func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }
        let names = Settings.shared.screenNames
        if names.contains(Settings.allScreens) { return screens }
        let chosen = screens.filter { names.contains($0.localizedName) }
        if !chosen.isEmpty { return chosen }
        return [screens[0]]  // monitor principal (o da barra de menus)
    }

    func reposition() {
        syncPanels()
    }

    /// Cria/remove painéis pra bater com os monitores escolhidos e posiciona todos.
    private func syncPanels() {
        let screens = NotchController.targetScreens()
        while panels.count < screens.count {
            let hosting = NotchHostingView(rootView: NotchView(state: state))
            panels.append(NotchPanel(contentView: hosting))
        }
        while panels.count > screens.count {
            panels.removeLast().orderOut(nil)
        }
        setWindowFrame(desiredWindowSize())
        for p in panels {
            p.ignoresMouseEvents = !state.visible
            p.orderFrontRegardless()
        }
    }

    // MARK: - Tamanho da janela (uma função só decide)

    private func desiredWindowSize() -> CGSize {
        NotchMetrics.windowSize(for: state.phase, open: state.isOpen, rows: state.rows.count, wide: state.thinkingWide)
    }

    private func setWindowFrame(_ size: CGSize) {
        currentSize = size
        for (p, screen) in zip(panels, NotchController.targetScreens()) {
            let origin = NSPoint(x: screen.frame.midX - size.width / 2,
                                 y: screen.frame.maxY - size.height)
            p.setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    /// Crescendo: a janela cresce na hora (é transparente) e o bigodinho anima dentro.
    /// Encolhendo: deixa a animação terminar e só então reduz a janela.
    private func applyWindowSize() {
        let want = desiredWindowSize()
        let cur = currentSize
        if want == cur { return }
        let grown = CGSize(width: max(want.width, cur.width), height: max(want.height, cur.height))
        if grown != cur { setWindowFrame(grown) }
        if want != grown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self = self, self.desiredWindowSize() == want else { return }
                self.setWindowFrame(want)
            }
        }
    }

    // MARK: - Fases

    private func setPhase(_ phase: NotchPhase) {
        state.phase = phase
        applyVisibility()
        applyWindowSize()
    }

    func applyVisibility() {
        let s = Settings.shared
        let visible = s.enabled && (s.alwaysVisible || state.phase != .idle || state.isOpen)
        state.visible = visible
        // Invisível = não atrapalha cliques em quem está embaixo.
        for p in panels { p.ignoresMouseEvents = !visible }
        if !s.enabled && (state.phase != .idle || state.isOpen) {
            cancelHide()
            pending.removeAll(); pendingOrder.removeAll(); thinking.removeAll()
            state.phase = .idle
            setOpen(false)
            applyWindowSize()
        }
    }

    private func show(_ phase: NotchPhase, title: String = "", subtitle: String = "", project: String = "") {
        state.title = title
        state.subtitle = subtitle
        state.project = project
        setPhase(phase)
    }

    // MARK: - Eventos do Claude Code

    func handle(_ e: NotchEvent) {
        let settings = Settings.shared
        if e.isSubagent { return }
        track(e)

        switch e.kind {
        case .sessionStart:
            _ = settings.isProjectEnabled(e.cwd) // só registra o projeto na lista
            return
        case .sessionEnd:
            thinking.remove(e.sessionId)
            clearPending(e.sessionId)
            refresh()
            return
        default:
            break
        }

        guard settings.enabled, settings.isProjectEnabled(e.cwd) else { return }
        lastEvent = e

        switch e.kind {
        case .thinking:
            clearPending(e.sessionId)
            thinking.insert(e.sessionId)
            cancelHide()
            refresh()

        case .toolStart, .toolDone:
            // Uma ferramenta rodou = a permissão foi concedida.
            if pending[e.sessionId] != nil {
                clearPending(e.sessionId)
                thinking.insert(e.sessionId)
                refresh()
            }

        case .done:
            thinking.remove(e.sessionId)
            clearPending(e.sessionId)
            let sub = e.message.isEmpty ? L.t("Reply ready in \(e.projectName)", "Resposta pronta em \(e.projectName)") : "\(e.projectName) · \(e.message)"
            show(.done, title: L.t("Claude replied", "Claude respondeu"), subtitle: sub, project: e.projectName)
            play("Glass")
            scheduleHide()

        case .approval:
            thinking.remove(e.sessionId)
            addPending(e)
            let sub = e.message.isEmpty ? e.projectName : "\(e.projectName) · \(e.message)"
            show(.approval, title: L.t("Claude needs your approval", "Claude precisa da sua aprovação"), subtitle: sub, project: e.projectName)
            play("Ping")
            cancelHide()

        case .waiting:
            thinking.remove(e.sessionId)
            addPending(e)
            let sub = e.message.isEmpty ? e.projectName : "\(e.projectName) · \(e.message)"
            show(.waiting, title: L.t("Claude is waiting for you", "Claude está esperando você"), subtitle: sub, project: e.projectName)
            play("Pop")
            cancelHide()

        default:
            break
        }
    }

    /// Atualiza o registro de sessões com o evento (independe do filtro de projetos).
    private func track(_ e: NotchEvent) {
        let now = Date()
        if e.kind == .sessionEnd {
            sessions[e.sessionId] = nil
            if state.isOpen { rebuildRows() }
            return
        }
        var s = sessions[e.sessionId] ?? SessionInfo(cwd: e.cwd)
        if !e.cwd.isEmpty { s.cwd = e.cwd }
        if !e.termProgram.isEmpty { s.termProgram = e.termProgram }
        if !e.bundleId.isEmpty { s.bundleId = e.bundleId }
        if !e.hostSession.isEmpty { s.hostSession = e.hostSession }
        if !e.entrypoint.isEmpty { s.entrypoint = e.entrypoint }
        s.lastSeen = now

        func set(_ st: ChatStatus) {
            if s.status != st { s.since = now }
            s.status = st
        }

        switch e.kind {
        case .thinking:
            set(.thinking)
            s.thinkingStart = now
            s.detail = e.message.isEmpty ? L.t("Working…", "Trabalhando…") : "“\(e.message)”"
        case .toolStart:
            set(.thinking)
            if s.thinkingStart == nil { s.thinkingStart = now }
            s.detail = e.message.isEmpty ? L.t("Running a tool…", "Rodando uma ferramenta…") : L.t("Running \(e.message)…", "Rodando \(e.message)…")
        case .toolDone:
            set(.thinking)
            if s.thinkingStart == nil { s.thinkingStart = now }
            s.detail = e.message.isEmpty ? L.t("Working…", "Trabalhando…") : L.t("Ran \(e.message)", "Rodou \(e.message)")
        case .done:
            set(.done)
            if let start = s.thinkingStart { learnTurn(cwd: s.cwd, seconds: now.timeIntervalSince(start)) }
            s.thinkingStart = nil
            s.detail = e.message.isEmpty ? L.t("Reply ready", "Resposta pronta") : e.message
        case .approval:
            set(.approval)
            s.detail = e.message.isEmpty ? L.t("Wants your approval", "Quer sua aprovação") : e.message
        case .waiting:
            set(.waiting)
            s.thinkingStart = nil
            s.detail = e.message.isEmpty ? L.t("Waiting for your reply", "Esperando sua resposta") : e.message
        case .sessionStart:
            set(.idle)
            s.detail = L.t("Chat open", "Chat aberto")
        default:
            break
        }
        sessions[e.sessionId] = s
        if state.isOpen { rebuildRows() }
    }

    // MARK: - Progresso estimado

    private func learnTurn(cwd: String, seconds: Double) {
        guard seconds > 1, seconds < 3600 else { return }
        let old = turnDurations[cwd] ?? defaultTurnSeconds
        turnDurations[cwd] = old * 0.7 + seconds * 0.3
        UserDefaults.standard.set(turnDurations, forKey: "turnDurations")
    }

    /// 0…1. Chega a 80% no tempo típico do projeto e sobe devagar até 97%; 100% só com o Stop.
    private func estimateProgress(_ s: SessionInfo, now: Date) -> Double? {
        guard s.status == .thinking, let start = s.thinkingStart else { return nil }
        let expected = max(5, turnDurations[s.cwd] ?? defaultTurnSeconds)
        let t = now.timeIntervalSince(start)
        if t <= expected { return max(0.02, 0.8 * t / expected) }
        return 0.8 + 0.17 * (1 - exp(-(t - expected) / expected))
    }

    private func elapsedText(_ since: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(since))
        if s < 60 { return L.isPT ? "há \(max(s, 0)) s" : "\(max(s, 0)) s ago" }
        if s < 3600 { return L.isPT ? "há \(s / 60) min" : "\(s / 60) min ago" }
        return L.isPT ? "há \(s / 3600) h" : "\(s / 3600) h ago"
    }

    /// Linha do painel → sessão que a representa (a mais urgente daquela pasta).
    private var rowSession: [String: String] = [:]

    /// Monta as linhas do painel: uma por pasta ativada, mais urgente primeiro.
    private func rebuildRows() {
        let now = Date()
        let settings = Settings.shared
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastSeen) < sessionTTL }

        var groups: [String: [(String, SessionInfo)]] = [:]
        for (sid, s) in sessions where settings.isProjectEnabled(s.cwd) {
            groups[s.cwd, default: []].append((sid, s))
        }
        var rows: [ChatRow] = []
        var map: [String: String] = [:]
        for (cwd, list) in groups {
            // representante da pasta: o mais urgente; empate = o mais recente
            guard let lead = list.min(by: { a, b in
                a.1.status != b.1.status ? a.1.status < b.1.status : a.1.since > b.1.since
            }) else { continue }
            let id = cwd.isEmpty ? lead.0 : cwd
            map[id] = lead.0
            rows.append(ChatRow(id: id, name: lead.1.projectName, status: lead.1.status, detail: lead.1.detail,
                                progress: estimateProgress(lead.1, now: now),
                                elapsed: elapsedText(lead.1.since, now: now),
                                since: lead.1.since, sessions: list.count))
        }
        rows.sort { $0.status != $1.status ? $0.status < $1.status : $0.since > $1.since }
        rowSession = map
        let shown = Array(rows.prefix(NotchMetrics.openMaxRows))
        if shown != state.rows { state.rows = shown }
    }

    // MARK: - Painel aberto

    func toggleOpen() { setOpen(!state.isOpen) }

    func setOpen(_ open: Bool) {
        guard open != state.isOpen else { return }
        if open {
            rebuildRows()
            hoveredOnce = false
        }
        state.isOpen = open
        applyVisibility()
        applyWindowSize()
        if open {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.rebuildRows()
                self?.applyWindowSize()
            }
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.setOpen(false)
            }
        } else {
            ticker?.invalidate(); ticker = nil
            leaveTimer?.invalidate(); leaveTimer = nil
            if let m = clickMonitor { NSEvent.removeMonitor(m) }
            clickMonitor = nil
        }
    }

    private func hoverChanged(_ inside: Bool) {
        guard state.isOpen else { return }
        leaveTimer?.invalidate(); leaveTimer = nil
        if inside {
            hoveredOnce = true
        } else if hoveredOnce {
            leaveTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                self?.setOpen(false)
            }
        }
    }

    private func rowTapped(_ rowId: String) {
        if let sid = rowSession[rowId], let s = sessions[sid] {
            activate(hostSession: s.hostSession, bundleId: s.bundleId, termProgram: s.termProgram)
            if s.status == .approval || s.status == .waiting {
                clearPending(sid)
                refresh()
            }
        }
        setOpen(false)
    }

    /// Mostra o que for mais importante no momento: aprovação pendente > pensando > nada.
    private func refresh() {
        if let sid = pendingOrder.last, let e = pending[sid] {
            let sub = e.message.isEmpty ? e.projectName : "\(e.projectName) · \(e.message)"
            if e.kind == .waiting {
                show(.waiting, title: L.t("Claude is waiting for you", "Claude está esperando você"), subtitle: sub, project: e.projectName)
            } else {
                show(.approval, title: L.t("Claude needs your approval", "Claude precisa da sua aprovação"), subtitle: sub, project: e.projectName)
            }
        } else if !thinking.isEmpty && Settings.shared.showThinking {
            // Uma linha por pasta: "A · B" ou "3 pensando · A · B +1"
            let folders = Set(thinking.compactMap { sessions[$0]?.cwd })
            let names = folders.map { SessionInfo(cwd: $0).projectName }.sorted()
            let label: String
            if names.count <= 1 {
                label = names.first ?? lastEvent?.projectName ?? "Claude"
            } else {
                let shown = names.prefix(2).joined(separator: " · ")
                label = names.count > 2 ? L.t("\(names.count) thinking · \(shown) +\(names.count - 2)", "\(names.count) pensando · \(shown) +\(names.count - 2)") : shown
            }
            state.thinkingWide = names.count > 1
            show(.thinking, project: label)
        } else {
            state.thinkingWide = false
            show(.idle)
        }
    }

    private func addPending(_ e: NotchEvent) {
        pending[e.sessionId] = e
        pendingOrder.removeAll { $0 == e.sessionId }
        pendingOrder.append(e.sessionId)
    }

    private func clearPending(_ sid: String) {
        pending[sid] = nil
        pendingOrder.removeAll { $0 == sid }
    }

    // MARK: - Timer de recolher

    private func scheduleHide() {
        cancelHide()
        let secs = max(2.0, Settings.shared.autoHideSeconds)
        hideTimer = Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }

    private func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Clique no selo "abrir →"

    private func openTapped() {
        switch state.phase {
        case .approval, .waiting:
            if let sid = pendingOrder.last, let e = pending[sid] {
                activate(e)
                clearPending(sid)
            }
            refresh()
        case .done:
            activate(lastEvent)
            cancelHide()
            refresh()
        case .thinking:
            activate(lastEvent)
        case .idle:
            toggleOpen()
        }
    }

    /// Traz pra frente o terminal/editor onde aquele chat do Claude Code está rodando.
    private func activate(_ e: NotchEvent?) {
        guard let e = e else { return }
        activate(hostSession: e.hostSession, bundleId: e.bundleId, termProgram: e.termProgram)
    }

    /// Sessão do app Claude: abre direto o chat (claude://). Senão, traz o terminal pela frente.
    private func activate(hostSession: String, bundleId: String, termProgram: String) {
        if !hostSession.isEmpty, let url = URL(string: "claude://claude.ai/epitaxy/\(hostSession)") {
            NSLog("Bigodinho: abrindo %@", url.absoluteString)
            NSWorkspace.shared.open(url)
            return
        }
        var id = bundleId
        if id.isEmpty { id = TerminalMap.bundleId(for: termProgram) }
        guard !id.isEmpty else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func play(_ name: String) {
        guard Settings.shared.soundEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Teste

    func test(_ kind: String) {
        let fake: NotchEvent
        switch kind {
        case "open":
            toggleOpen()
            return
        case "reposition":
            reposition()
            return
        case "approval":
            fake = NotchEvent(kind: .approval, sessionId: "teste", cwd: "", message: L.t("Wants to run npm install", "Quer rodar o comando npm install"),
                              termProgram: "", bundleId: "")
        case "waiting":
            fake = NotchEvent(kind: .waiting, sessionId: "teste", cwd: "", message: L.t("Is waiting for your reply", "Está esperando sua resposta"),
                              termProgram: "", bundleId: "")
        case "thinking":
            fake = NotchEvent(kind: .thinking, sessionId: "teste", cwd: "", message: "",
                              termProgram: "", bundleId: "")
        default:
            fake = NotchEvent(kind: .done, sessionId: "teste", cwd: "", message: L.t("Done! I created the file and ran the tests.", "Pronto! Criei o arquivo e rodei os testes."),
                              termProgram: "", bundleId: "")
        }
        handle(fake)
    }
}
