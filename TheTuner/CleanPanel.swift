import SwiftUI

struct CleanPanel<Content: View>: View {
    @Environment(\.tunerTheme) private var theme
    private var style: CleanStyle { theme.style }
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 24, weight: .medium))
                    if let subtitle { Text(subtitle).technical(10, spacing: 1).foregroundStyle(style.muted) }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).frame(width: 44, height: 44)
                        .background(style.silver.opacity(0.35), in: Circle())
                }.accessibilityLabel("Done").accessibilityIdentifier("close-\(title)")
            }.padding(24)
            Rectangle().fill(style.silver).frame(height: 1).padding(.horizontal, 24)
            ScrollView { VStack(spacing: 12, content: content).padding(24) }
                .scrollIndicators(.hidden)
        }
        .background(style.face).foregroundStyle(style.ink).tint(style.ink)
        .presentationDragIndicator(.visible).presentationCornerRadius(28)
    }
}
struct CleanRow: View {
    @Environment(\.tunerTheme) private var theme
    private var style: CleanStyle { theme.style }
    let title: String
    var detail: String? = nil
    var selected = false
    var symbol: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let symbol { Image(systemName: symbol).frame(width: 22).foregroundStyle(style.muted) }
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.system(size: 16, weight: .medium))
                    if let detail { Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(style.muted).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                if selected { Circle().fill(style.orange).frame(width: 8, height: 8) }
            }.padding(17).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(selected ? style.orange.opacity(0.07) : style.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? style.orange.opacity(0.5) : style.silver, lineWidth: 0.8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(selected ? "Selected" : "")
    }
}
