import Foundation
import SwiftData

@Model
final class ConversationMessage {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var attachedMetricType: String?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        attachedMetricType: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachedMetricType = attachedMetricType
    }
}

enum MessageRole: String, Codable {
    case user = "user"
    case pearl = "pearl"
}
