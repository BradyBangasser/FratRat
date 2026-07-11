//
//  LogCapture.swift
//  FratRat
//
//  Created by Brady Bangasser on 7/5/26.
//
//  Captures ALL process output — Rust `tracing` (writes to stdout) and Swift
//  `print` (stdout) — by redirecting the stdout/stderr file descriptors to a
//  pipe, teeing every chunk to (1) an on-disk log file and (2) the original
//  console so a debugger, if attached, still shows live output.
//
//  This works with NO debugger attached: the file write happens regardless of
//  whether anything is reading the console. It is the mechanism that lets you
//  collect logs from a TestFlight / physical device in another state.
//
//  Call LogCapture.shared.start() once, as early as possible in app launch.
//

import Foundation

final class LogCapture {
    static let shared = LogCapture()

    private let logFileURL: URL
    private let maxBytes: Int = 5 * 1024 * 1024   // upload trims to last ~5 MB
    private var started = false

    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1

    private let outPipe = Pipe()
    private let queue = DispatchQueue(label: "com.fratrat.logcapture")
    private var fileHandle: FileHandle?

    private init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        logFileURL = dir.appendingPathComponent("fratrat.log")
    }

    // MARK: - Start

    func start() {
        guard !started else { return }
        started = true

        rotateExisting()
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logFileURL)

        // Preserve the real fds so we can echo back to the console when present.
        originalStdout = dup(fileno(stdout))
        originalStderr = dup(fileno(stderr))

        // Redirect stdout AND stderr into the pipe.
        dup2(outPipe.fileHandleForWriting.fileDescriptor, fileno(stdout))
        dup2(outPipe.fileHandleForWriting.fileDescriptor, fileno(stderr))

        // Unbuffered so lines land promptly even without a newline flush.
        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)

        let echoFd = originalStdout
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }

            // Echo to real console (no-op if nothing is attached).
            if echoFd >= 0 {
                data.withUnsafeBytes { raw in
                    _ = write(echoFd, raw.baseAddress, data.count)
                }
            }
            // Persist to disk.
            self?.queue.async {
                self?.fileHandle?.seekToEndOfFile()
                self?.fileHandle?.write(data)
            }
        }

        log("──── FratRat log session \(Self.timestamp()) ────")
    }

    // MARK: - Direct logging entry point
    //
    // For anything you want guaranteed in the log regardless of stdout
    // behaviour, call LogCapture.shared.log(...) directly. Also useful from
    // Swift code paths where you'd rather not rely on print().

    func log(_ message: String) {
        let line = "\(Self.timestamp()) \(message)\n"
        let data = Data(line.utf8)
        queue.async { [weak self] in
            self?.fileHandle?.seekToEndOfFile()
            self?.fileHandle?.write(data)
        }
        // Also mirror to console.
        if originalStdout >= 0 {
            data.withUnsafeBytes { raw in
                _ = write(originalStdout, raw.baseAddress, data.count)
            }
        }
    }

    // MARK: - Retrieval

    /// Full current log as Data, trimmed to the most recent `maxBytes`.
    func currentLogData() -> Data {
        queue.sync {
            // Flush any buffered writes first.
            try? fileHandle?.synchronize()
            guard let data = try? Data(contentsOf: logFileURL) else { return Data() }
            return data.count > maxBytes ? data.suffix(maxBytes) : data
        }
    }

    func currentLogSize() -> Int {
        (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int) ?? 0
    }

    func clear() {
        queue.sync {
            try? fileHandle?.close()
            try? FileManager.default.removeItem(at: logFileURL)
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            fileHandle = try? FileHandle(forWritingTo: logFileURL)
        }
    }

    // MARK: - Helpers

    private func rotateExisting() {
        let prev = logFileURL.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: prev)
        try? FileManager.default.moveItem(at: logFileURL, to: prev)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
