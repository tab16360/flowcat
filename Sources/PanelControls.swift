import AppKit
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

struct PanelMenuEntry {
    var title: String
    var checked = false
    var enabled = true
    var action: () -> Void
}
// Keep the label in SwiftUI; the system menu style otherwise replaces its font and colors.
struct PanelMenu<Content: View>: View {
    var entries: [PanelMenuEntry]
    @ViewBuilder var label: () -> Content
    @ViewState private var anchor: NSView?
    var body: some View {
        Button {
            guard let anchor else { return }
            let handler = PanelMenuHandler(actions: entries.map(\.action))
            let menu = NSMenu(); menu.autoenablesItems = false
            for (index, entry) in entries.enumerated() {
                let item = NSMenuItem(title: entry.title, action: #selector(PanelMenuHandler.select(_:)), keyEquivalent: "")
                item.tag = index; item.target = handler; item.state = entry.checked ? .on : .off
                item.isEnabled = entry.enabled; menu.addItem(item)
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

// One sort control for every ranking so network and disk lists read the same.
struct PanelSortMenu: View {
    @Binding var selection: Int
    var options: [String]
    var label: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        PanelMenu(entries: options.indices.map { index in
            PanelMenuEntry(title: options[index], checked: index == selection) { selection = index }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down").font(.system(size: 9, weight: .semibold))
                Text(options[min(selection, options.count - 1)])
                Image(systemName: "chevron.down").font(.system(size: 8))
            }.font(.system(size: 11)).foregroundStyle(palette.secondary).contentShape(Rectangle())
        }.fixedSize().help(tr("Sort by", "排序方式")).accessibilityLabel("\(label), \(options[min(selection, options.count - 1)])")
    }
}

// Explanations live behind an info button so the panel keeps its space for data.
struct InfoButton: View {
    var title: String? = nil
    var text: String
    var help = tr("Learn more", "查看说明")
    @ViewState private var shown = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        Button { shown.toggle() } label: {
            if let title { Label(title, systemImage: "info.circle") }
            else { Image(systemName: "info.circle").frame(width: 16, height: 16).contentShape(Rectangle()) }
        }.buttonStyle(.borderless).foregroundStyle(palette.secondary).help(help).accessibilityLabel(title ?? help)
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                ScrollView {
                    Text(text).font(.system(size: 12)).lineSpacing(3).foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).textSelection(.enabled)
                }.frame(width: 300).frame(maxHeight: 340)
            }
    }
}

struct PanelSearchField: View {
    @Binding var text: String
    var prompt: String
    var focusRequest = 0
    var autofocus = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(palette.secondary)
            TextField(prompt, text: $text).font(.system(size: 12)).textFieldStyle(.plain).focused($focused)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondary) }
                    .buttonStyle(.plain).help(tr("Clear search", "清除搜索")).accessibilityLabel(tr("Clear search", "清除搜索"))
            }
        }.padding(.horizontal, 10).frame(height: 28).background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .onChange(of: focusRequest) { _ in focused = true }
            .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }
}

// Letter tiles replace dashed placeholders, which read as a failed icon load.
struct FallbackIcon: View {
    var name: String
    var symbol: String? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(palette.track)
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .medium)) }
            else { Text(name.first.map { String($0).uppercased() } ?? "?").font(.system(size: 12, weight: .semibold)) }
        }.foregroundStyle(palette.secondary)
    }
}

struct RankRow<Icon: View, Detail: View>: View {
    var name: String
    var value: String
    var fraction: Double
    var subtitle: String
    var badge: String? = nil
    var badgeHelp = ""
    var actions: [PanelMenuEntry] = []
    var expanded: Bool? = nil
    var toggle: () -> Void = {}
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var detail: () -> Detail
    @ViewState private var hovering = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 9) {
                icon().frame(width: 24, height: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle).help(name)
                        if let badge {
                            Text(badge).font(.system(size: 9)).foregroundStyle(palette.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(palette.track).clipShape(Capsule())
                                .fixedSize().help(badgeHelp)
                        }
                        Spacer(minLength: 6)
                        Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
                    }
                    HStack(spacing: 8) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.track)
                                Capsule().fill(palette.accent).frame(width: geometry.size.width * min(1, max(0, fraction)))
                            }
                        }.frame(height: 3).accessibilityHidden(true)
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(palette.secondary).monospacedDigit().fixedSize()
                    }
                }
                HStack(spacing: 2) {
                    if !actions.isEmpty {
                        PanelMenu(entries: actions) {
                            Image(systemName: "ellipsis").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary)
                                .frame(width: 18, height: 20).contentShape(Rectangle())
                        }.opacity(hovering ? 1 : 0).allowsHitTesting(hovering).help(tr("More actions", "更多操作")).accessibilityLabel(tr("\(name), more actions", "\(name)，更多操作"))
                    }
                    if let expanded {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9))
                            .foregroundStyle(palette.secondary).frame(width: 14).accessibilityHidden(true)
                    }
                }
            }
            if expanded == true { detail().padding(.leading, 33) }
        }.padding(.vertical, 7).padding(.horizontal, 6)
            .background(hovering ? palette.surface : Color.clear).clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onTapGesture { if expanded != nil { toggle() } }
            .onHover { hovering = $0 }
            .contextMenu {
                ForEach(actions.indices, id: \.self) { index in
                    Button(actions[index].title) { actions[index].action() }.disabled(!actions[index].enabled)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: expanded == true ? tr("Collapse details", "收起详情") : tr("Expand details", "展开详情")) { if expanded != nil { toggle() } }
    }
}

struct TrendPoint {
    var label: String
    var value: UInt64?
}
// Gray bars mark periods without samples; they are not zero usage.
struct TrendBars: View {
    var points: [TrendPoint]
    var trailingLabel: String? = nil
    var help: String
    var accessibility: String
    var format: (UInt64) -> String = volume
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        let top = max(1, points.compactMap(\.value).max() ?? 1)
        VStack(spacing: 3) {
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: points.count > 40 ? 1 : 2) {
                    ForEach(points.indices, id: \.self) { index in
                        let point = points[index]
                        RoundedRectangle(cornerRadius: 1)
                            .fill(point.value == nil ? palette.track : palette.accent)
                            .frame(height: max(1, CGFloat(Double(point.value ?? 0) / Double(top)) * geometry.size.height))
                            .help("\(point.label): \(point.value.map(format) ?? tr("No data", "未记录"))")
                    }
                }.frame(maxHeight: .infinity, alignment: .bottom)
            }.frame(height: 28)
            HStack {
                Text(points.first?.label ?? "")
                Spacer()
                Text(points.isEmpty ? "" : points[points.count / 2].label)
                Spacer()
                Text(trailingLabel ?? points.last?.label ?? "")
            }.font(.system(size: 10)).foregroundStyle(palette.secondary).monospacedDigit()
        }.padding(.top, 4).help(help)
            .accessibilityElement(children: .ignore).accessibilityLabel(accessibility)
    }
}

// Shown at the top of either tab so a paused recorder is never mistaken for zero usage.
struct PausedBanner: View {
    var resume: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill").foregroundStyle(palette.warning)
            Text(tr("Recording is paused. Traffic and disk activity are not counted.", "已暂停记录，期间的流量和读写不会计入。")).font(.system(size: 11)).foregroundStyle(palette.text)
            Spacer(minLength: 4)
            Button(tr("Resume", "继续记录"), action: resume).controlSize(.small)
        }.padding(.horizontal, 10).padding(.vertical, 7).background(palette.warningSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
