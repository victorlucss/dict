import Foundation
import os

/// Simple logger that writes to both os_log and a log file.
/// Log file: /tmp/dict.log
enum Log {
    private static let logger = Logger(subsystem: "com.dict.app", category: "Dict")
    private static let logFile = URL(fileURLWithPath: "/tmp/dict.log")

    static func info(_ message: String) {
        logger.info("\(message)")
        write("[INFO] \(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message)")
        write("[ERROR] \(message)")
    }

    private static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    /// Clear log on app start
    static func clear() {
        try? "".write(to: logFile, atomically: true, encoding: .utf8)
    }
}
