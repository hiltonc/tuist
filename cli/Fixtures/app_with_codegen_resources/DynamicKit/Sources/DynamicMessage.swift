import Foundation

public enum DynamicMessage {
    public static var message: String? {
        Bundle.module.url(forResource: "dynamic", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
