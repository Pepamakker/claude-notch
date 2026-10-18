import SwiftUI

/// Em que "humor" o bigodinho está.
enum NotchPhase: Equatable {
    case idle       // só o bigodinho preto, quietinho
    case thinking   // Claude trabalhando: pontinho pulsando
    case done       // Claude respondeu: abre com ✓
    case approval   // Claude precisa da sua aprovação: abre e fica pulsando até você clicar
    case waiting    // Claude parado esperando você

    var isExpanded: Bool { self == .done || self == .approval || self == .waiting }
}

/// Estado de um chat (uma sessão do Claude Code) na lista do painel.
enum ChatStatus: Int, Equatable, Comparable {
    case approval = 0   // precisa de você agora
    case waiting = 1    // parado esperando você
    case thinking = 2   // trabalhando
    case done = 3       // respondeu
    case idle = 4       // sem nada acontecendo

    static func < (a: ChatStatus, b: ChatStatus) -> Bool { a.rawValue < b.rawValue }

    var color: Color {
        switch self {
        case .approval: return .warnAmber
        case .waiting: return .infoBlue
        case .thinking: return .claude
        case .done: return .okGreen
        case .idle: return Color.white.opacity(0.35)
        }
    }

    var label: String {
        switch self {
        case .approval: return L.t("Approval", "Aprovação")
        case .waiting: return L.t("Waiting for you", "Esperando você")
        case .thinking: return L.t("Thinking", "Pensando")
        case .done: return L.t("Replied", "Respondeu")
        case .idle: return L.t("Idle", "Ocioso")
        }
    }

    /// Pontinho pulsa quando precisa de atenção ou está trabalhando.
    var pulses: Bool { self == .approval || self == .thinking }
}

/// Uma linha do painel: um chat e o que ele está fazendo agora.
struct ChatRow: Identifiable, Equatable {
    let id: String          // pasta do chat (cwd); vários processos na mesma pasta viram uma linha
    let name: String        // nome curto do projeto (última pasta)
    let status: ChatStatus
    let detail: String      // o que está fazendo / última mensagem
    let progress: Double?   // 0…1 estimado, só enquanto pensa
    let elapsed: String     // "há 32 s", "há 4 min"
    let since: Date
    let sessions: Int       // quantos processos do Claude Code nessa pasta
}

/// Tamanhos do bigodinho em cada fase (pontos).
enum NotchMetrics {
    static let collapsed = CGSize(width: 196, height: 32)
    static let thinking = CGSize(width: 240, height: 32)
    static let thinkingWide = CGSize(width: 330, height: 32)   // vários projetos pensando
    static let expanded = CGSize(width: 380, height: 76)

    /// Painel aberto (clique no bigodinho).
    static let openWidth: CGFloat = 480
    static let openHeader: CGFloat = 40
    static let openRow: CGFloat = 58
    static let openEmpty: CGFloat = 44
    static let openBottom: CGFloat = 18
    static let openMaxRows = 6

    /// Folga em volta pra mola da animação poder "passar do ponto" sem cortar.
    static let padX: CGFloat = 18
    static let padBottom: CGFloat = 22

    static func size(for phase: NotchPhase, wide: Bool = false) -> CGSize {
        switch phase {
        case .idle: return collapsed
        case .thinking: return wide ? thinkingWide : thinking
        case .done, .approval, .waiting: return expanded
        }
    }

    static func openSize(rows: Int) -> CGSize {
        let n = min(rows, openMaxRows)
        let body = n == 0 ? openEmpty : CGFloat(n) * openRow
        return CGSize(width: openWidth, height: openHeader + body + openBottom)
    }

    /// Tamanho do bigodinho considerando fase e painel aberto.
    static func size(for phase: NotchPhase, open: Bool, rows: Int, wide: Bool = false) -> CGSize {
        open ? openSize(rows: rows) : size(for: phase, wide: wide)
    }

    static func windowSize(for phase: NotchPhase, open: Bool, rows: Int, wide: Bool = false) -> CGSize {
        let s = size(for: phase, open: open, rows: rows, wide: wide)
        return CGSize(width: s.width + padX * 2, height: s.height + padBottom)
    }
}

/// Estado observado pela view SwiftUI.
final class NotchState: ObservableObject {
    @Published var phase: NotchPhase = .idle
    @Published var title: String = ""
    @Published var subtitle: String = ""
    @Published var project: String = ""
    @Published var visible: Bool = true
    /// Mais de um projeto pensando: bigodinho "pensando" mais largo.
    @Published var thinkingWide: Bool = false

    /// Painel com a lista de chats aberto?
    @Published var isOpen: Bool = false
    @Published var rows: [ChatRow] = []

    /// Clique no corpo do bigodinho (abre/fecha o painel).
    var onTap: (() -> Void)?
    /// Clique no selo "abrir →" do aviso (vai direto pro terminal).
    var onOpenTap: (() -> Void)?
    /// Clique numa linha do painel (traz o terminal daquele chat).
    var onRowTap: ((String) -> Void)?
    /// Mouse entrou/saiu do painel aberto.
    var onHoverChange: ((Bool) -> Void)?
}
