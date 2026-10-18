import AppKit

// Ponto de entrada. O app é um "agente" de barra de menus: sem ícone no Dock,
// sem janela principal. Só o bigodinho no topo do monitor e um ícone ✦ na barra.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
