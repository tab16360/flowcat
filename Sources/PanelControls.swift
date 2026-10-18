import SwiftUI

// Explicit surfaces keep small controls consistent with the approved panel in all macOS appearances.
struct PanelSegments<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(Value, String)]
    var label: String
    var horizontalPadding: CGFloat = 9
    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(dark: scheme == .dark) }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index], selected = selection == option.0
                Button { selection = option.0 } label: {
                    Text(option.1).font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? palette.text : palette.secondary)
                        .padding(.horizontal, horizontalPadding).padding(.vertical, 3)
                        .background(selected ? palette.surface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 1, y: 1)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(label)，\(option.1)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(2).background(palette.track).clipShape(RoundedRectangle(cornerRadius: 7)).fixedSize()
    }
}
struct PanelRecordingStatus: View {
    var title: String
    var warning = false
    var paused = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        HStack(spacing: 5) {
            if warning { Image(systemName: "exclamationmark.circle").foregroundStyle(palette.warning) }
            else { Circle().fill(paused ? palette.secondary : palette.success).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(title).foregroundStyle(palette.secondary)
        }.font(.system(size: 11))
    }
}

// Keep the label in SwiftUI; the system menu style otherwise replaces its font and colors.
struct PanelMenu<Content: View>: View {
    var entries: [(String, () -> Void)]
    @ViewBuilder var label: () -> Content
    @ViewState private var anchor: NSView?
    var body: some View {
        Button {
            guard let anchor else { return }
            let handler = PanelMenuHandler(actions: entries.map { $0.1 })
            let menu = NSMenu(); menu.autoenablesItems = false
            for (index, entry) in entries.enumerated() {
                let item = NSMenuItem(title: entry.0, action: #selector(PanelMenuHandler.select(_:)), keyEquivalent: "")
                item.tag = index; item.target = handler; menu.addItem(item)
            }
            _ = withExtendedLifetime(handler) {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY-4), in: anchor)
            }
        } label: { label() }
            .buttonStyle(.plain)
            .background(PanelMenuAnchor { anchor = $0 }.allowsHitTesting(false))
    }
}
private final class PanelMenuHandler: NSObject {
    let actions: [() -> Void]
    init(actions: [() -> Void]) { self.actions = actions }
    @objc func select(_ sender: NSMenuItem) { if actions.indices.contains(sender.tag) { actions[sender.tag]() } }
}
private struct PanelMenuAnchor: NSViewRepresentable {
    var ready: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); DispatchQueue.main.async { ready(view) }; return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
