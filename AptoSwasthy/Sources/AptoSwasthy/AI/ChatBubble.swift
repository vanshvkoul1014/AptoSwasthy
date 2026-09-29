import SwiftUI

struct ChatBubble: View {
    let message: ConversationMessage

    var isPearl: Bool { message.role == .pearl }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isPearl {
                // Pearl avatar
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .glassBackground(cornerRadius: 10)
            } else {
                Spacer(minLength: 60)
            }

            VStack(alignment: isPearl ? .leading : .trailing, spacing: 4) {
                Text(message.content)
                    .font(.pearlBody)
                    .foregroundColor(.primaryText)
                    .lineSpacing(5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        isPearl
                            ? Color.glassBackground
                            : Color.pearlGreen.opacity(0.25)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isPearl ? Color.glassBorder : Color.pearlGreen.opacity(0.4),
                                lineWidth: 1
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.pearlCaption2)
                    .foregroundColor(.quaternaryText)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 280, alignment: isPearl ? .leading : .trailing)

            if !isPearl {
                // User avatar
                Circle()
                    .fill(LinearGradient(colors: [.pearlGreen.opacity(0.6), .pearlMint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.primaryText)
                    }
            } else {
                Spacer(minLength: 60)
            }
        }
    }
}
