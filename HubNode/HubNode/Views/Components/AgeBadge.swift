import SwiftUI

struct AgeBadge: View {
    let ageSeconds: TimeInterval
    let isStale: Bool

    var body: some View {
        Text(AgeFormatting.label(ageSeconds: ageSeconds))
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isStale ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(isStale ? .orange : .secondary)
    }
}

struct PostureBanner: View {
    let posture: Posture
    let hubName: String
    let summary: String?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(posture.title.uppercased())
                .font(.title2.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(posture.tint.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(posture.tint, lineWidth: 2)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(hubName)
                    .font(.title3.weight(.semibold))
                if let summary, !summary.isEmpty {
                    MarkdownText(source: summary, font: .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text(posture.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
