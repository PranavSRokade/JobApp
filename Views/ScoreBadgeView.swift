import SwiftUI

struct ScoreBadgeView: View {
    let label: String
    let value: Int

    private var color: Color {
        switch value {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(width: 36)
    }
}
