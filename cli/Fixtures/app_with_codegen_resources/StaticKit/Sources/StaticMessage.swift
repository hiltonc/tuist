import Foundation

public enum StaticMessage {
    public static var message: String? {
        Bundle.module.url(forResource: "static", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
