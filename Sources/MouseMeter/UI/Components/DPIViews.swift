import SwiftUI

/// DPI 在传感器范围内的位置（对数刻度，低 DPI 区间更易分辨）
struct DPIRangeBar: View {
    var dpi: DPIStatus

    var body: some View {
        if let range = dpi.range {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { proxy in
                    let position = fraction(of: dpi.current, in: range)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, proxy.size.width * position))
                        if let defaultValue = dpi.defaultValue, range.contains(defaultValue) {
                            Rectangle()
                                .fill(.primary.opacity(0.5))
                                .frame(width: 2, height: 12)
                                .offset(x: proxy.size.width * fraction(of: defaultValue, in: range) - 1)
                                .help("默认 \(defaultValue) DPI")
                        }
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(range.lowerBound)")
                    Spacer()
                    Text("\(range.upperBound)")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func fraction(of value: Int, in range: ClosedRange<Int>) -> CGFloat {
        let low = log(Double(range.lowerBound))
        let high = log(Double(range.upperBound))
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((log(Double(clamped)) - low) / (high - low))
    }
}

extension DPIStatus {
    var displayText: String {
        if let currentY { "\(current) × \(currentY)" } else { "\(current)" }
    }
}
