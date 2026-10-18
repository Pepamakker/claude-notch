import SwiftUI

extension Color {
    /// Laranja do Claude (#D97757).
    static let claude = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let okGreen = Color(red: 0.20, green: 0.84, blue: 0.45)
    static let warnAmber = Color(red: 1.0, green: 0.72, blue: 0.20)
    static let infoBlue = Color(red: 0.36, green: 0.62, blue: 1.0)
}

/// Formato do bigodinho: cantos de cima "escorrem" pra fora (igual o notch do MacBook),
/// cantos de baixo arredondados.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = topRadius
        let br = min(bottomRadius, (rect.height - tr) / 2, (rect.width - 2 * tr) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// O bigodinho em si.
struct NotchView: View {
    @ObservedObject var state: NotchState
    @State private var pulse = false
    @State private var ring = false
    @State private var hovering = false

    private var size: CGSize {
        NotchMetrics.size(for: state.phase, open: state.isOpen, rows: state.rows.count, wide: state.thinkingWide)
    }
    private var topRadius: CGFloat { 10 }
    private var bottomRadius: CGFloat {
        if state.isOpen { return 34 }
        return state.phase.isExpanded ? 26 : 13
    }
    private var spring: Animation { .spring(response: 0.4, dampingFraction: 0.85) }
    private var shape: NotchShape { NotchShape(topRadius: topRadius, bottomRadius: bottomRadius) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Fechado: preto do notch. Aberto: vidro escuro (material desfocado) com o preto a 38%.
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(state.isOpen ? 1 : 0)
                shape
                    .fill(Color.black)
                    .opacity(state.isOpen ? 0.12 : 1)
                if state.isOpen {
                    // brilho de vidro: reflexo no topo e borda com luz
                    shape
                        .fill(LinearGradient(colors: [.white.opacity(0.16), .clear],
                                             startPoint: .top, endPoint: .center))
                    shape
                        .stroke(LinearGradient(colors: [.white.opacity(0.40), .white.opacity(0.10)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        .padding(0.5)
                } else {
                    // brilho bem discreto na borda de baixo, pra dar volume
                    shape
                        .stroke(Color.white.opacity(hovering ? 0.16 : 0.07), lineWidth: 0.8)
                        .mask {
                            LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                        }
                }
                if state.isOpen {
                    openPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                } else {
                    content
                        .padding(.horizontal, topRadius + 12)
                        .padding(.bottom, 2)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .contentShape(Rectangle())
            .onTapGesture { state.onTap?() }
            .onHover { inside in
                hovering = inside
                if state.isOpen { state.onHoverChange?(inside) }
            }
            .scaleEffect(hovering && !state.phase.isExpanded && !state.isOpen ? 1.03 : 1.0, anchor: .top)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: state.phase)
        .animation(spring, value: state.isOpen)
        .animation(spring, value: state.thinkingWide)
        .animation(spring, value: state.rows.count)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .opacity(state.visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: state.visible)
    }

    // MARK: - Aviso (fechado)

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            Color.clear

        case .thinking:
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.claude)
                    .opacity(pulse ? 1 : 0.45)
                Text(state.project)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Circle()
                    .fill(Color.claude)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.25 : 0.75)
                    .shadow(color: Color.claude.opacity(pulse ? 0.9 : 0.2), radius: pulse ? 6 : 1)
            }
            .transition(.opacity)
            .onAppear { startPulse() }
            .onDisappear { pulse = false }

        case .done, .approval, .waiting:
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(state.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(state.phase == .done ? L.t("open", "abrir") : L.t("open →", "abrir →"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(state.phase == .done ? 0.10 : 0.18)))
                    .contentShape(Capsule())
                    .onTapGesture { state.onOpenTap?() }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            .onAppear { startPulse() }
            .onDisappear { pulse = false; ring = false }
        }
    }

    @ViewBuilder
    private var icon: some View {
        let (symbol, color): (String, Color) = {
            switch state.phase {
            case .approval: return ("hand.raised.fill", Color.warnAmber)
            case .waiting: return ("ellipsis.bubble.fill", Color.infoBlue)
            default: return ("checkmark", Color.okGreen)
            }
        }()
        ZStack {
            if state.phase == .approval || state.phase == .waiting {
                Circle()
                    .stroke(color.opacity(ring ? 0 : 0.8), lineWidth: 2)
                    .scaleEffect(ring ? 1.4 : 1.0)
            }
            Circle()
                .fill(color.opacity(0.18))
            Circle()
                .stroke(color.opacity(0.6), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 30, height: 30)
    }

    private func startPulse() {
        pulse = false
        ring = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { ring = true }
    }

    // MARK: - Painel aberto (lista de chats)

    private var headerCount: String {
        let n = state.rows.count
        let urgent = state.rows.filter { $0.status == .approval || $0.status == .waiting }.count
        if urgent > 0 { return L.isPT ? (urgent == 1 ? "1 precisa de você" : "\(urgent) precisam de você") : (urgent == 1 ? "1 needs you" : "\(urgent) need you") }
        let working = state.rows.filter { $0.status == .thinking }.count
        if working > 0 { return L.isPT ? (working == 1 ? "1 trabalhando" : "\(working) trabalhando") : "\(working) working" }
        return n == 1 ? "1 chat" : "\(n) chats"
    }

    private var openPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.claude)
                Text("Claude Code")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 8)
                Text(headerCount)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: NotchMetrics.openHeader)

            hairline

            if state.rows.isEmpty {
                Text(L.t("No active chats", "Nenhum chat ativo agora"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: NotchMetrics.openEmpty)
            } else {
                ForEach(Array(state.rows.enumerated()), id: \.element.id) { i, row in
                    ChatRowView(row: row, index: i) { state.onRowTap?(row.id) }
                    if i < state.rows.count - 1 {
                        hairline.padding(.leading, 40)
                    }
                }
            }
        }
        .padding(.horizontal, topRadius + 8)
        .padding(.bottom, NotchMetrics.openBottom)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }
}

/// Uma linha do painel: ponto de estado, nome do chat, o que está fazendo e progresso.
struct ChatRowView: View {
    let row: ChatRow
    let index: Int
    let action: () -> Void

    @State private var shown = false
    @State private var hover = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(row.status.color.opacity(pulse ? 0.5 : 0.15))
                    .frame(width: 18, height: 18)
                    .blur(radius: 3)
                Circle()
                    .fill(row.status.color)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.15 : 0.95)
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if row.sessions > 1 {
                        Text("×\(row.sessions)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer(minLength: 8)
                    Text(row.status.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(row.status.color)
                        .lineLimit(1)
                }
                Text(row.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let p = row.progress {
                        ProgressBar(value: p, color: row.status.color)
                            .frame(height: 3)
                        Text("~\(Int((p * 100).rounded()))%")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(width: 34, alignment: .trailing)
                    } else {
                        Text(row.elapsed)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 10)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(hover ? 0.7 : 0.25))
        }
        .padding(.horizontal, 10)
        .frame(height: NotchMetrics.openRow)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hover ? 0.07 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hover = $0 }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : -6)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.045)) {
                shown = true
            }
            updatePulse()
        }
        .onChange(of: row.status) { _ in updatePulse() }
    }

    private func updatePulse() {
        if row.status.pulses {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { pulse = false }
        }
    }
}

/// Barra fina de progresso, estilo Apple.
struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, g.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .animation(.easeOut(duration: 0.5), value: value)
    }
}
