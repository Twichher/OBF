import AppKit
import SwiftUI

/// Sidebar "Структура" tab: the document's H1 / H2 headings. A row lifts
/// on hover (a soft card with a shadow), a click jumps to the heading, an
/// H1 with H2s under it folds with the "−" / "+" at its right edge, and a
/// title cut short by "…" shows in full in a tooltip above the row after a
/// short hover.
struct OutlineView: View {
    @EnvironmentObject private var appState: AppState

    /// How long the pointer rests on a cut-short title before the tooltip.
    static let tooltipDelay: TimeInterval = 0.6

    /// Row under the pointer whose title is cut short, and the one whose
    /// tooltip is showing.
    @State private var hoveredID: Int?
    @State private var tooltipID: Int?
    @State private var pendingTooltip: DispatchWorkItem?

    var body: some View {
        let visible = appState.visibleOutline
        let foldable = appState.foldableOutlineIDs
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(visible) { item in
                    OutlineRow(
                        item: item,
                        foldable: foldable.contains(item.id),
                        current: appState.currentOutlineIDs.contains(item.id),
                        collapsed: appState.collapsedOutline.contains(item.title),
                        onToggle: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                appState.toggleOutlineFold(item)
                            }
                        },
                        onHover: { hovering, truncated in
                            hoverChanged(item, hovering: hovering, truncated: truncated)
                        })
                        // Where the row is right now — read when the
                        // tooltip is drawn, so scrolling never leaves it
                        // at a stale spot.
                        .anchorPreference(key: RowBoundsKey.self, value: .bounds) { [item.id: $0] }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .animation(.easeInOut(duration: 0.18), value: appState.outline)
        }
        .overlayPreferenceValue(RowBoundsKey.self) { rows in
            GeometryReader { proxy in
                if let id = tooltipID, let anchor = rows[id],
                   let item = appState.outline.first(where: { $0.id == id }) {
                    let row = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        OutlineTooltip(text: item.title)
                            .padding(.horizontal, 6)
                            // Just above the row; below it when the row is
                            // too close to the top.
                            .alignmentGuide(.top) { d in
                                let above = row.minY - d.height - 4
                                return -(above >= 0 ? above : row.maxY + 4)
                            }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.14), value: tooltipID)
    }

    private func hoverChanged(_ item: OutlineItem, hovering: Bool, truncated: Bool) {
        pendingTooltip?.cancel()
        pendingTooltip = nil
        guard hovering, truncated else {
            if hoveredID == item.id || hovering {
                hoveredID = nil
                tooltipID = nil
            }
            return
        }
        hoveredID = item.id
        tooltipID = nil
        let work = DispatchWorkItem {
            guard hoveredID == item.id else { return }
            tooltipID = item.id
        }
        pendingTooltip = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tooltipDelay, execute: work)
    }
}

/// Bounds of each visible row, by outline id.
private struct RowBoundsKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One heading row. Measures whether its title fits, so the tooltip only
/// shows for titles cut short.
private struct OutlineRow: View {
    @EnvironmentObject private var appState: AppState
    let item: OutlineItem
    let foldable: Bool
    /// The caret is under this heading: its title shimmers in the accent.
    let current: Bool
    let collapsed: Bool
    let onToggle: () -> Void
    let onHover: (Bool, Bool) -> Void

    @State private var hovering = false
    @State private var textWidth: CGFloat = 0

    private var title: String { item.title.isEmpty ? "—" : item.title }
    private var isH1: Bool { item.level == 1 }

    /// Whether the full title is wider than the space the row gives it.
    private var truncated: Bool {
        let font = OBFTheme.uiNSFont(size: isH1 ? 16 : 14, bold: isH1)
        let full = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        return textWidth > 0 && full > textWidth + 0.5
    }

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if current {
                    ShimmerText(text: title, size: isH1 ? 16 : 14, bold: isH1)
                } else {
                    Text(title)
                        .font(isH1 ? OBFTheme.uiBold(16) : OBFTheme.ui(14))
                        .foregroundColor(OBFTheme.text)
                }
            }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { textWidth = geo.size.width }
                        .onChange(of: geo.size.width) { textWidth = geo.size.width }
                })
            if foldable {
                FoldButton(collapsed: collapsed, action: onToggle)
            }
        }
        .padding(.leading, item.level == 2 ? 20 : 0)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? OBFTheme.elevated : Color.clear)
                .shadow(color: .black.opacity(hovering ? OBFTheme.theme.shadow * 0.55 : 0), radius: 6, x: 0, y: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            appState.editor?.scrollToOutline(item)
        }
        .onHover { inside in
            hovering = inside
            onHover(inside, truncated)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Text in the accent (H1) colour with a soft light band gliding across it
/// every couple of seconds — marks the heading the caret is in. Drawn and
/// animated by Core Animation (a gradient masked by the text), so the
/// shimmer costs the app next to no CPU — a SwiftUI timeline redrawing the
/// row 30 times a second cost ~23% of a core.
private struct ShimmerText: NSViewRepresentable {
    let text: String
    let size: CGFloat
    let bold: Bool

    func makeNSView(context: Context) -> ShimmerTextView {
        ShimmerTextView()
    }

    func updateNSView(_ view: ShimmerTextView, context: Context) {
        view.configure(text: text, font: OBFTheme.uiNSFont(size: size, bold: bold))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShimmerTextView, context: Context) -> CGSize? {
        let font = OBFTheme.uiNSFont(size: size, bold: bold)
        let height = ceil(font.ascender - font.descender + font.leading)
        return CGSize(width: proposal.width ?? nsView.naturalWidth, height: height)
    }
}

final class ShimmerTextView: NSView {
    /// The title itself, in the accent colour (always visible).
    private let base = CALayer()
    /// The light band: a gradient clear → glow → clear, masked by the text
    /// so it only lights up the letters.
    private let gradient = CAGradientLayer()
    private let mask = CALayer()
    private var text = ""
    private var font = NSFont.systemFont(ofSize: 14)
    private var renderedFor: (String, NSFont, CGSize, CGFloat)?
    private(set) var naturalWidth: CGFloat = 0

    /// Seconds for one pass of the band, and the whole cycle with the rest.
    private static let pass = 1.8
    private static let cycle = 2.6

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let glow = OBFTheme.h1TextNS.blended(withFraction: 0.55, of: .white) ?? OBFTheme.h1TextNS
        for layer in [base, mask] {
            layer.contentsGravity = .topLeft
        }
        layer?.addSublayer(base)
        gradient.colors = [glow.withAlphaComponent(0).cgColor, glow.cgColor, glow.withAlphaComponent(0).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = [-0.6, -0.4, -0.2]
        gradient.mask = mask
        layer?.addSublayer(gradient)

        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.6, -0.4, -0.2]
        sweep.toValue = [1.2, 1.4, 1.6]
        sweep.duration = Self.pass
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let group = CAAnimationGroup()
        group.animations = [sweep]
        group.duration = Self.cycle
        group.repeatCount = .infinity
        gradient.add(group, forKey: "shimmer")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(text: String, font: NSFont) {
        self.text = text
        self.font = font
        naturalWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.frame = bounds
        gradient.frame = bounds
        mask.frame = gradient.bounds
        renderText()
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderedFor = nil
        needsLayout = true
    }

    /// Draws the title exactly like the other rows' text (tail-truncated
    /// with "…", top-aligned) into an image: shown in the accent colour and
    /// used as the band's mask.
    private func renderText() {
        let size = bounds.size
        let scale = window?.backingScaleFactor ?? 2
        guard size.width > 0, size.height > 0 else { return }
        if let done = renderedFor, done.0 == text, done.1 == font, done.2 == size, done.3 == scale { return }
        renderedFor = (text, font, size, scale)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: OBFTheme.h1TextNS, .paragraphStyle: style,
        ])
        let image = NSImage(size: size, flipped: true) { rect in
            string.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return true
        }
        var proposed = NSRect(origin: .zero, size: size)
        let cgImage = image.cgImage(forProposedRect: &proposed, context: nil,
                                    hints: [.ctm: AffineTransform(scale: scale)])
        for layer in [base, mask] {
            layer.contents = cgImage
            layer.contentsScale = scale
        }
    }
}

/// "−" folds an H1's H2 headings away, "+" brings them back.
private struct FoldButton: View {
    let collapsed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(collapsed ? "+" : "−")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(hovering ? OBFTheme.text : .secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(hovering ? OBFTheme.hover : Color.clear))
                .contentShape(Circle())
                .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(collapsed ? "Развернуть" : "Свернуть")
    }
}

/// The full title of a cut-short heading, in a small floating card.
private struct OutlineTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OBFTheme.ui(13))
            .foregroundColor(OBFTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(OBFTheme.elevated)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(OBFTheme.paperBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(OBFTheme.theme.shadow), radius: 10, x: 0, y: 4))
    }
}
