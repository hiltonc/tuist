import DynamicKit
import MixedKit
import StaticKit

print([DynamicMessage.message, StaticMessage.message, MixedMessage.message].map { $0 ?? "missing" }.joined(separator: " "))
