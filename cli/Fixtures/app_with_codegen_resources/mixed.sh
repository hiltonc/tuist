#!/bin/sh
set -e
printf Mixed > "$TUIST_OUTPUT_SOURCES_DIR/mixed.txt"
cat > "$TUIST_OUTPUT_SOURCES_DIR/MixedMessage.swift" <<'SWIFT'
import Foundation

public enum MixedMessage {
    public static var message: String? {
        Bundle.module.url(forResource: "mixed", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
SWIFT
