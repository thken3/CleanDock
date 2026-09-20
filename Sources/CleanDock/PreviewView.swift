import SwiftUI

/// The before/after preview: the user's own Dock icons rendered the Dock's way and Clean Dock's way,
/// with one divider shared by the actual-size strip and the magnified view. Nothing here captures the screen.
struct PreviewView: View {
    @ObservedObject var state: AppState
    @State private var fraction = 0.5
    @State private var selected = 0

    private let gap: CGFloat = 7

    private var side: CGFloat { CGFloat(state.side) }
    private var magnification: Int { max(2, min(8, 140 / max(state.side, 1))) }
    private var selectedIcon: PreviewIcon? { state.icons.indices.contains(selected) ? state.icons[selected] : state.icons.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner {
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(.secondary).frame(width: 6, height: 6).padding(.top, 5)
                    Text(banner).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.5)))
            }
            VStack(spacing: 6) {
                HStack {
                    Text("Standard Dock")
                    Spacer()
                    Text("Clean Dock")
                }
                .foregroundStyle(.secondary)
                strip
                HStack {
                    Text("1:1 — actual size, \(state.side) px icons")
                    Spacer()
                    Text("drag the divider")
                }
                .foregroundStyle(.tertiary)
            }
            HStack(alignment: .top, spacing: 14) {
                magnifier
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(selectedIcon?.name ?? "Icon"), \(magnification)× magnified").fontWeight(.semibold)
                    Text("One pixel of the Dock is one square here. Click an icon in the strip above to magnify it.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 220, alignment: .leading)
            }
            Text(state.caption).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }

    private var banner: String? {
        switch state.previewMode {
        case .normal: return nil
        case .retina: return "The Dock looks fine on this display — here is what Clean Dock does on a non-Retina display."
        case .noPermission: return "Accessibility is not granted yet, so this preview uses a few default system icons."
        }
    }

    // MARK: Strip

    private var stripWidth: CGFloat { side * CGFloat(state.icons.count) + gap * CGFloat(max(state.icons.count - 1, 0)) }

    private var strip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(Color.gray.opacity(0.28))
                RoundedRectangle(cornerRadius: 13).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                if let strip = state.strip {
                    PixelCompareView(standard: strip.standard, clean: strip.clean, fraction: fraction)
                }
                divider(height: proxy.size.height, knob: true).position(x: width * fraction, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { fraction = min(max($0.location.x / width, 0), 1) }
                .onEnded { value in
                    guard abs(value.translation.width) < 3 else { return }      // a click, not a drag: pick the icon
                    let local = value.location.x - ((width - stripWidth) / 2).rounded()
                    let index = Int((local / (side + gap)).rounded(.down))
                    if local >= 0, state.icons.indices.contains(index) { selected = index }
                })
            .accessibilityElement()
            .accessibilityLabel("Divider between Standard Dock rendering and Clean Dock rendering")
            .accessibilityValue("\(Int(fraction * 100)) percent")
            .accessibilityAdjustableAction { direction in
                fraction = min(max(fraction + (direction == .increment ? 0.1 : -0.1), 0), 1)
            }
        }
        .frame(height: side + 14)
    }

    // MARK: Magnifier

    private var magnifier: some View {
        let size = side * CGFloat(magnification)
        return ZStack {
            Color.gray.opacity(0.1)
            if let icon = selectedIcon {
                PixelCompareView(standard: icon.standard, clean: icon.clean, fraction: fraction, magnification: magnification, grid: true)
                    .accessibilityLabel("Standard Dock rendering left of the divider, Clean Dock rendering right of it")
            }
            divider(height: size, knob: false).position(x: size * fraction, y: size / 2)
        }
        .frame(width: size, height: size)
    }

    private func divider(height: CGFloat, knob: Bool) -> some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.55)).frame(width: 1, height: height)
                .overlay(Rectangle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
            if knob {
                Circle().fill(Color(white: 0.96)).frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
            }
        }
    }
}
