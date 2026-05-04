//
//  TerminalSession.swift
//  agentrocky
//

import Foundation
import Combine

/// A real interactive shell session (persistent PTY)
class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()

    struct Line: Identifiable {
        let id = UUID()
        let text: String
        let isInput: Bool
    }

    @Published var lines: [Line] = []
    @Published var isRunning: Bool = false

    let workingDirectory: String

    private var process: Process?
    private var masterFd: Int32 = -1
    private var readThread: Thread?

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        launch()
    }

    // MARK: - Shell

    private func launch() {
        var master: Int32 = -1
        var slave: Int32 = -1

        // Open a PTY pair
        var ws = winsize(ws_row: 24, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
        if openpty(&master, &slave, nil, nil, &ws) == -1 {
            appendLine("⚠ Failed to open PTY", isInput: false)
            return
        }

        masterFd = master

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["--login", "-i"]
        p.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        p.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "xterm-256color",
            "COLUMNS": "200",
            "LINES": "24"
        ]) { _, new in new }

        let slaveFH = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        p.standardInput  = slaveFH
        p.standardOutput = slaveFH
        p.standardError  = slaveFH

        do {
            try p.run()
        } catch {
            appendLine("⚠ Failed to launch shell: \(error.localizedDescription)", isInput: false)
            return
        }

        process = p
        _DarwinFoundation3.close(slave)

        // Read output on background thread
        let thread = Thread {
            self.readLoop(fd: master)
        }
        thread.qualityOfService = .userInitiated
        thread.start()
        readThread = thread
    }

    private func readLoop(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        var partial = ""

        while true {
            let n = read(fd, &buf, buf.count)
            guard n > 0 else { break }

            let raw = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
            // Strip ANSI escape sequences for clean display
            let clean = stripANSI(raw)
            partial += clean

            // Split on newlines and emit complete lines
            var parts = partial.components(separatedBy: "\n")
            partial = parts.removeLast() // keep incomplete tail

            let toEmit = parts.map { $0.trimmingCharacters(in: .controlCharacters) }.filter { !$0.isEmpty }

            DispatchQueue.main.async {
                for line in toEmit {
                    self.lines.append(Line(text: line, isInput: false))
                }
            }
        }

        // Emit any remaining partial
        if !partial.isEmpty {
            let final = partial.trimmingCharacters(in: .controlCharacters)
            if !final.isEmpty {
                DispatchQueue.main.async {
                    self.lines.append(Line(text: final, isInput: false))
                }
            }
        }
    }

    func send(_ command: String) {
        guard masterFd >= 0 else { return }
        let full = command + "\n"
        appendLine(command, isInput: true)
        full.withCString { ptr in
            _ = write(masterFd, ptr, strlen(ptr))
        }
    }

    func close() {
        process?.terminate()
        process = nil
        if masterFd >= 0 {
            Darwin.close(masterFd)
            masterFd = -1
        }
    }

    func restart() {
        close()
        lines = []
        launch()
    }

    private func appendLine(_ text: String, isInput: Bool) {
        DispatchQueue.main.async {
            self.lines.append(Line(text: text, isInput: isInput))
        }
    }

    // MARK: - ANSI Stripping

    private func stripANSI(_ s: String) -> String {
        // Remove ESC[ ... m sequences and other control sequences
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}", s.index(after: i) < s.endIndex {
                let next = s.index(after: i)
                if s[next] == "[" {
                    // Skip until we find a letter (the command terminator)
                    var j = s.index(after: next)
                    while j < s.endIndex && !s[j].isLetter {
                        j = s.index(after: j)
                    }
                    if j < s.endIndex {
                        i = s.index(after: j)
                    } else {
                        i = j
                    }
                    continue
                } else if s[next] == "]" {
                    // OSC sequence — skip to BEL or ST
                    var j = s.index(after: next)
                    while j < s.endIndex && s[j] != "\u{07}" && s[j] != "\u{1B}" {
                        j = s.index(after: j)
                    }
                    if j < s.endIndex { j = s.index(after: j) }
                    i = j
                    continue
                }
            }
            if s[i] != "\r" { result.append(s[i]) }
            i = s.index(after: i)
        }
        return result
    }
}
