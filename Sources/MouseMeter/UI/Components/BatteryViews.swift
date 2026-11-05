import SwiftUI

extension BatteryStatus {
    var tint: Color {
        if state == .charging || state == .full { return .green }
        switch percent {
        case ..<15: return .red
        case ..<30: return .orange
        case ..<50: return .yellow
        default: return .green
        }
    }

    var gradient: [Color] {
        if state == .charging || state == .full { return [.mint, .green] }
        switch percent {
        case ..<15: return [.pink, .red]
        case ..<30: return [.yellow, .orange]
        case ..<50: return [.yellow, .orange.opacity(0.9)]
        default: return [.mint, .green]
        }
    }

    var percentText: String { isEstimated ? "≈\(percent)%" : "\(percent)%" }
}

/// 横向电池图标，填充宽度与电量精确对应。菜单栏与列表中使用。
struct BatteryGlyph: View {
    var percent: Int?
    var isCharging = false
    var height: CGFloat = 11
    /// nil 时使用前景色（菜单栏模板图）
    var fill: Color?

    var body: some View {
        let width = height * 2.1
        let lineWidth = max(1, height / 10)
        let inset = lineWidth + 1
        HStack(spacing: lineWidth) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3)
                    .strokeBorder(.primary.opacity(fill == nil ? 0.55 : 0.35), lineWidth: lineWidth)
                if let percent {
                    RoundedRectangle(cornerRadius: height * 0.18)
                        .fill(fill ?? .primary)
                        .frame(width: max(lineWidth, (width - inset * 2) * CGFloat(percent) / 100))
                        .padding(inset)
                }
            }
            .frame(width: width, height: height)
            .overlay {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.85, weight: .black))
                        .foregroundStyle(.black)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()

            RoundedRectangle(cornerRadius: lineWidth)
                .fill(.primary.opacity(fill == nil ? 0.55 : 0.35))
                .frame(width: lineWidth * 1.5, height: height * 0.36)
        }
    }
}

/// 环形电量仪表
struct BatteryRing: View {
    var battery: BatteryStatus?
    var size: CGFloat = 160
    var lineWidth: CGFloat = 14

    @State private var animatedFraction: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)

            if let battery {
                Circle()
                    .trim(from: 0, to: animatedFraction)
                    .stroke(
                        AngularGradient(colors: battery.gradient + [battery.gradient[0]], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: battery.tint.opacity(0.35), radius: lineWidth * 0.6)
            }

            VStack(spacing: size * 0.02) {
                if let battery {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        if battery.isEstimated {
                            Text("≈").font(.system(size: size * 0.14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(battery.percent)")
                            .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.system(size: size * 0.12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: size * 0.09))
                            .foregroundStyle(.green)
                    }
                } else {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: size * 0.2))
                        .foregroundStyle(.tertiary)
                }
            }
            .monospacedDigit()
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
        .onAppear { animate(to: battery) }
        .onChange(of: battery) { _, newValue in animate(to: newValue) }
    }

    private func animate(to battery: BatteryStatus?) {
        withAnimation(.spring(duration: 0.9, bounce: 0.15)) {
            animatedFraction = Double(battery?.percent ?? 0) / 100
        }
    }
}
