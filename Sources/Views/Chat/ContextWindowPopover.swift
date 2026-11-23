import SwiftUI

enum ContextWindowFormatting {
    static func tokens(_ count: Int) -> String {
        if count >= 999_950 {
            let value = Double(count) / 1_000_000.0
            let rounded = (value * 10).rounded() / 10
            if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(rounded))M"
            }
            return String(format: "%.1fM", rounded)
        }
        if count >= 1_000 {
            let value = Double(count) / 1_000.0
            let rounded = (value * 10).rounded() / 10
            if rounded >= 1_000 {
                return "1M"
            }
            if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(rounded))K"
            }
            return String(format: "%.1fK", rounded)
        }
        return "\(max(0, count))"
    }

    static func percent(_ value: Double) -> String {
        let clamped = max(0, value)
        let rounded = (clamped * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))%"
        }
        return String(format: "%.1f%%", rounded)
    }
}

struct ContextWindowPopover: View {
    let usage: ContextUsageSnapshot?
    let fallbackUsedPercent: Int
    @Environment(\.zcodePalette) private var palette

    private var cardFill: Color {
        palette.isDark ? Color(red: 0.129, green: 0.129, blue: 0.129) : palette.menuBackground
    }

    private var trackFill: Color {
        palette.isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    private var effectiveFraction: Double {
        if let usage {
            return max(0, min(1, usage.fraction))
        }
        return max(0, min(1, Double(fallbackUsedPercent) / 100.0))
    }

    private var headerRightText: String {
        if let usage {
            let used = ContextWindowFormatting.tokens(usage.usedTokens)
            let maxT = ContextWindowFormatting.tokens(usage.maxTokens)
            let pct = ContextWindowFormatting.percent(usage.fraction * 100)
            return "\(used)/\(maxT) (\(pct))"
        }
        return "\(max(0, min(100, fallbackUsedPercent)))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Context windows")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(headerRightText)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                }

                segmentedBar

                VStack(alignment: .leading, spacing: 10) {
                    if let usage, !usage.breakdown.isEmpty {
                        ForEach(Array(usage.breakdown.enumerated()), id: \.element.id) { idx, slice in
                            breakdownRow(
                                color: Self.sliceColor(for: slice.source, index: idx),
                                label: slice.label,
                                percentText: ContextWindowFormatting.percent(slice.fraction * 100)
                            )
                        }
                    } else {
                        let pctText = usage.map { ContextWindowFormatting.percent($0.fraction * 100) }
                            ?? "\(max(0, min(100, fallbackUsedPercent)))%"
                        breakdownRow(
                            color: Self.sliceShades[0],
                            label: "Context used",
                            percentText: pctText
                        )
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if let hitRate = usage?.cacheHitRate {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)

                HStack(spacing: 8) {
                    Text("Average cache hit rate")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                    Spacer(minLength: 8)
                    Text(ContextWindowFormatting.percent(hitRate * 100))
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 16, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contextWindowPopover")
    }

    private var segmentedBar: some View {
        GeometryReader { geo in
            let totalWidth = max(0, geo.size.width)
            let filledWidth = totalWidth * CGFloat(effectiveFraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackFill)

                if let usage, !usage.breakdown.isEmpty, filledWidth > 0 {
                    let slices = usage.breakdown.filter { $0.fraction > 0 }
                    let sliceSum = max(1e-6, slices.reduce(0) { $0 + $1.fraction })
                    HStack(spacing: 0) {
                        ForEach(Array(slices.enumerated()), id: \.element.id) { idx, slice in
                            let segWidth = filledWidth * CGFloat(slice.fraction / sliceSum)
                            Rectangle()
                                .fill(Self.sliceColor(for: slice.source, index: idx))
                                .frame(width: segWidth)
                        }
                    }
                    .frame(width: max(4, filledWidth), height: 8, alignment: .leading)
                    .clipShape(Capsule())
                } else if filledWidth > 0 {
                    Capsule()
                        .fill(Self.sliceShades[0])
                        .frame(width: max(4, filledWidth), height: 8)
                }
            }
        }
        .frame(height: 8)
    }

    private func breakdownRow(color: Color, label: String, percentText: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(palette.foregroundSubtle)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(percentText)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
        }
    }

    private static let sliceShades: [Color] = [
        Color(hex: 0x4C8DFF),
        Color(hex: 0x628AD8),
        Color(hex: 0x5675AE),
        Color(hex: 0x526A91),
        Color(hex: 0x55647B),
        Color(hex: 0x5B6678)
    ]

    private static func sliceColor(for source: String, index: Int) -> Color {
        switch source {
        case "messages":
            return sliceShades[0]
        case "mcp_tool_schemas":
            return sliceShades[1]
        case "system_tool_schemas", "tool_prompt":
            return sliceShades[2]
        case "skills":
            return sliceShades[3]
        case "system_prompt":
            return sliceShades[4]
        case "meta_user_context":
            return sliceShades[5]
        default:
            return sliceShades[index % sliceShades.count]
        }
    }
}
